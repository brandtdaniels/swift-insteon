import InsteonCLICore
import InsteonCore
import InsteonDeviceCatalog
import InsteonLinking
import InsteonModem
import InsteonProtocol

/// `insteon device ADDRESS ACTION`: commands sent to one device.
enum DeviceCommands {

  static func run(_ action: DeviceAction, device: InsteonAddress, modem: Modem, hub: HubLocation?, names: ProductNames, printsJSON: Bool) async throws {

    switch action {
    case .id:
      try await IdentityStore.withNetwork(modem: modem, hub: hub, names: names) { (network: DeviceNetwork) async throws -> Void in

        try await identify(device, network: network, modem: modem, names: names, printsJSON: printsJSON)

      }
    case .ping:
      try await ping(device, modem: modem)
    case let .on(levelPercent):
      // A level means something only to a device that dims, so the device is looked up first.
      var kind: GroupType.Kind?

      if levelPercent != nil {

        kind = try await Identities.known(device, modem: modem, names: names, asking: true)?.mainGroupType?.kind

      }

      try await modem.request(StandardMessage(to: device, command: StandardDirectCommand.on(level: ControlText.level(percent: levelPercent, kind: kind))))

      Output.line(ControlText.turnedOn(device, percent: levelPercent, kind: kind))
    case let .onFast(levelPercent):
      let known = try await Identities.known(device, modem: modem, names: names, asking: true)
      let kind: GroupType.Kind? = known?.mainGroupType?.kind

      try checkListed("lightOnFast", named: "Light On Fast", for: known)
      try await modem.request(StandardMessage(to: device, command: StandardDirectCommand.fastOn(level: ControlText.level(percent: levelPercent, kind: kind))))

      Output.line(ControlText.turnedOn(device, percent: levelPercent, kind: kind))
    case .off:
      try await modem.request(StandardMessage(to: device, command: StandardDirectCommand.off))

      Output.line("Turned \(device) off.")
    case .offFast:
      let known = try await Identities.known(device, modem: modem, names: names, asking: true)

      try checkListed("lightOffFast", named: "Light Off Fast", for: known)
      try await modem.request(StandardMessage(to: device, command: StandardDirectCommand.fastOff))

      Output.line("Turned \(device) off.")
    case let .instant(levelPercent):
      try await instant(device, percent: levelPercent, modem: modem, names: names)
    case .beep:
      try await beep(device, modem: modem, names: names)
    case let .settings(showsAdvanced):
      try await SettingsCommands.show(device, showsAdvanced: showsAdvanced, modem: modem, names: names, printsJSON: printsJSON)
    case let .set(request):
      try await SettingsCommands.set(request, device: device, modem: modem, names: names)
    case let .send(request):
      try await ExploreCommands.send(request, to: device, modem: modem)
    case .status:
      try await status(device, modem: modem, names: names, printsJSON: printsJSON)
    case .links:
      try await IdentityStore.withNetwork(modem: modem, hub: hub, names: names) { (network: DeviceNetwork) async throws -> Void in

        try await links(device, network: network, printsJSON: printsJSON)

      }
    }

  }

  // MARK: - Commands the catalog lists

  /// Refuses a command the device's command set doesn't list. A device the catalog doesn't
  /// describe is sent it anyway, with a note.
  private static func checkListed(_ name: SettingName, named label: String, for known: DeviceDescription?) throws {

    guard let commands = known?.commandSet else {

      Output.note("The Insteon device catalog doesn't describe this device's commands; sending \(label) anyway.")

      return

    }

    guard commands.standardCommand(named: name) != nil else {

      throw CommandFailure(description: "The Insteon device catalog doesn't list \(label) for \(known?.displayName ?? "this device").")

    }

  }

  /// Light Instant Change, or Light On or Light Off for a relay whose command set doesn't list
  /// it.
  private static func instant(_ device: InsteonAddress, percent: Int, modem: Modem, names: ProductNames) async throws {

    let known = try await Identities.known(device, modem: modem, names: names, asking: true)
    let kind: GroupType.Kind? = known?.mainGroupType?.kind
    let level: UInt8 = ControlText.instantLevel(percent: percent, kind: kind)
    let isListed: Bool = known?.commandSet?.standardCommand(named: "instantChange") != nil

    if kind == .relay, !isListed {

      let command: StandardDirectCommand = level == 0 ? .off : .on(level: 0xFF)

      try await modem.request(StandardMessage(to: device, command: command))

    } else {

      try checkListed("instantChange", named: "Light Instant Change", for: known)
      try await modem.request(StandardMessage(to: device, command: StandardDirectCommand.instantChange(level: level)))

    }

    Output.line(ControlText.changedInstantly(device, percent: percent, kind: kind))

  }

  /// Beep, which the device is sent even when its command set doesn't list it.
  private static func beep(_ device: InsteonAddress, modem: Modem, names: ProductNames) async throws {

    let known = try await Identities.known(device, modem: modem, names: names, asking: true)

    if known?.commandSet?.standardCommand(named: "beep") == nil {

      Output.note("The Insteon device catalog doesn't list Beep for this device; sending anyway.")

    }

    do {

      try await modem.request(StandardMessage(to: device, command: StandardDirectCommand.beep))

    } catch ModemError.deviceRejected(_, let reason) {

      throw CommandFailure(description: "\(device) rejected Beep (NAK): \(reason.summary).")

    } catch ModemError.deviceTimedOut {

      throw CommandFailure(description: "\(device) didn't answer Beep. Check that it's powered and in range.")

    }

    Output.line("\(device) beeped.")

  }

  // MARK: - id

  /// A device's identity as `--json` prints it.
  struct Identity: Encodable {

    let address: String

    let engine: String

    let acceptsModem: Bool

    let category: String?

    let categoryName: String?

    let subcategory: String?

    let firmwareVersion: String?

    let productKey: String?

    let product: String?

  }

  private static func identify(_ device: InsteonAddress, network: DeviceNetwork, modem: Modem, names: ProductNames, printsJSON: Bool) async throws {

    // The network records the identity the device reports.
    let identification = try await network.identify(device)
    var productData: ProductData?

    if identification.acceptsModem {

      productData = try await requestProductData(device, modem: modem)

    }

    let identity = identification.identity
    let category = identity?.category ?? productData?.category
    let subcategory = identity?.subcategory ?? productData?.subcategory
    var product: String?

    if let category, let subcategory {

      product = names.name(category: category, subcategory: subcategory, firmwareVersion: identity?.firmwareVersion)

    }

    // Newer devices leave the product key out, or report zeros; that's expected, not a failure.
    let productKey = productData.map(\.productKey).flatMap { $0 == ProductKey(0x00, 0x00, 0x00) ? nil : $0 }

    if printsJSON {

      try Output.json(Identity(
        address: "\(device)",
        engine: Names.engine(identification.engine),
        acceptsModem: identification.acceptsModem,
        category: category.map { "\($0)" },
        categoryName: category?.name,
        subcategory: subcategory.map { "\($0)" },
        firmwareVersion: identity?.firmwareVersion.map { "\($0)" },
        productKey: productKey.map { "\($0)" },
        product: product
      ))

      return

    }

    // Each value is its own statement, which keeps the type checker quick.
    let categoryText: String = category.map(Names.category) ?? "not reported"
    let subcategoryText: String = subcategory.map { "\($0)" } ?? "not reported"
    let firmwareText: String = identity?.firmwareVersion.map { "\($0)" } ?? "not reported"
    // A device that answered Product Data Request without a key is a newer one; a device that
    // didn't answer said nothing about its key.
    let missingKeyText: String = productData == nil ? "not reported" : "none; newer devices don't report one"
    let productKeyText: String = productKey.map { "\($0)" } ?? missingKeyText
    var rows: [[String]] = [
      ["Device:", "\(device)"],
      ["Engine:", Names.engine(identification.engine)],
      ["Category:", categoryText],
      ["Subcategory:", subcategoryText],
      ["Firmware:", firmwareText],
      ["Product key:", productKeyText]
    ]

    // Without an identity, or without the catalog, nothing is said about the product.
    if category != nil, names.catalog != nil {

      rows.append(["Product:", product ?? "not in the Insteon device catalog"])

    }

    Output.table(rows)

    if !identification.acceptsModem {

      Output.note("The device runs i2CS and isn't linked to the modem, so it won't say more. Link it first with 'insteon link \(device)'.")

    }

  }

  /// Sends Product Data Request and waits for the device's Product Data Response, or returns
  /// `nil` if the device doesn't send one.
  private static func requestProductData(_ device: InsteonAddress, modem: Modem) async throws -> ProductData? {

    do {

      // Listening starts before the request, so the response can't be missed.
      return try await modem.firstReply(
        within: Modem.defaultExtendedRequestTimeout,
        after: {

          do {

            _ = try await modem.request(StandardMessage(to: device, command: StandardDirectCommand.productDataRequest))

          } catch let error as ModemError {

            // Not every device answers Product Data Request.
            switch error {
            case .deviceRejected, .deviceTimedOut:
              throw NoProductData()
            default:
              throw error
            }

          }

        },
        matching: { (reply: ModemReply) -> ProductData? in

          guard case let .messageReceived(message) = reply, message.sender == device else {

            return nil

          }

          return ProductData(message)

        }
      )

    } catch is NoProductData {

      return nil

    }

  }

  /// A device didn't answer Product Data Request.
  private struct NoProductData: Error {}

  // MARK: - ping

  private static func ping(_ device: InsteonAddress, modem: Modem) async throws {

    let clock = ContinuousClock()
    let start = clock.now

    try await modem.request(StandardMessage(to: device, command: StandardDirectCommand.ping))

    let elapsed = start.duration(to: clock.now).components
    let milliseconds = elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000

    Output.line("\(device) answered in \(milliseconds) ms.")

  }

  // MARK: - status

  /// A device's status as `--json` prints it. A device that's on/off only has no `percent`.
  struct Status: Encodable {

    let address: String

    let level: String

    let isOn: Bool

    let percent: Int?

    let allLinkDatabaseDelta: String

  }

  private static func status(_ device: InsteonAddress, modem: Modem, names: ProductNames, printsJSON: Bool) async throws {

    let kind = try await Identities.known(device, modem: modem, names: names, asking: true)?.mainGroupType?.kind

    // The acknowledgment carries the level in cmd2 and the ALL-Link database delta in cmd1.
    let acknowledgment = try await modem.request(StandardMessage(to: device, command: StandardDirectCommand.statusRequest()))
    let level = acknowledgment.command.command2

    if printsJSON {

      try Output.json(Status(
        address: "\(device)",
        level: Hex.byte(level),
        isOn: level != 0,
        percent: kind == .relay ? nil : LightLevel.percent(level: level),
        allLinkDatabaseDelta: Hex.byte(acknowledgment.command.command1)
      ))

      return

    }

    Output.line(ControlText.status(device, level: level, kind: kind))

  }

  // MARK: - links

  /// A record of a device's ALL-Link database as `--json` prints it, with what its data
  /// means when the catalog says.
  struct Record: Encodable {

    let memoryAddress: String

    let role: String

    let group: Int

    let address: String

    let data: [String]

    let meaning: String?

  }

  private static func links(_ device: InsteonAddress, network: DeviceNetwork, printsJSON: Bool) async throws {

    let known = try await Identities.known(device, network: network, asking: true)

    // The network reads the database only if the device's delta changed since the copy it
    // holds, and says so only then. The last record marks the end of the database, and
    // deleted records are no longer in use.
    let database: AllLinkDatabaseCopy = try await network.allLinkDatabase(of: device, beforeReading: { () -> Void in

      Output.note("Reading the ALL-Link database of \(device), one record at a time...")

    })
    let records = database.records
      .filter { $0.record.flags.contains(.inUse) }
      .map { response in

        let record = response.record
        let data = [record.data1, record.data2, record.data3]
        let isController = record.flags.contains(.controller)
        let explanation: RecordDataExplanation? = known?.explain(record, isController: isController)

        return Record(
          memoryAddress: Hex.address(response.address),
          role: isController ? "controller" : "responder",
          group: Int(record.group.rawValue),
          address: "\(record.address)",
          data: data.map(Hex.byte),
          meaning: explanation.map(LinkDataText.meaning(of:))
        )

      }

    if printsJSON {

      try Output.json(records)

      return

    }

    guard !records.isEmpty else {

      Output.line("The ALL-Link database of \(device) has no records in use.")

      return

    }

    let explains = records.contains { $0.meaning != nil }
    let isDeviceInCatalog: Bool = known?.profile != nil
    let rows: [[String]] = records.map { (record: Record) -> [String] in

      let meaning: String = LinkDataText.column(
        meaning: record.meaning,
        isController: record.role == "controller",
        isDeviceInCatalog: isDeviceInCatalog
      )

      return [record.memoryAddress, record.role, "\(record.group)", record.address, record.data.joined(separator: " ")]
        + (explains ? [meaning] : [])

    }

    Output.table([["MEMORY", "ROLE", "GROUP", "DEVICE", "DATA"] + (explains ? ["MEANING"] : [])] + rows)
    Output.line()

    if explains, let product = known?.displayName {

      Output.line("\(Wording.count(records.count, "record")) in use. The data is read as the Insteon device catalog gives it for \(product).")

    } else {

      Output.line(
        "\(Wording.count(records.count, "record")) in use. What the data means depends on the device, "
          + "which the Insteon device catalog doesn't describe here."
      )

    }

  }

}
