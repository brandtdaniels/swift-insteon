import InsteonCLISupport
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
      try await IdentityStore.withNetwork(modem: modem, hub: hub, names: names) { (cached: CachedNetwork) async throws -> Void in

        try await identify(device, network: cached.network, names: names, printsJSON: printsJSON)

      }
    case .ping:
      try await withDevice(device, modem: modem, hub: hub, names: names) { (target: Device) async throws -> Void in

        try await ping(target)

      }
    case let .on(levelPercent):
      try await withDevice(device, modem: modem, hub: hub, names: names) { (target: Device) async throws -> Void in

        let result: DeviceTurnOnResult = try await target.turnOn(level: levelPercent)

        Output.line(DeviceText.turnedOn(device, result: result))

      }
    case let .onFast(levelPercent):
      try await withDevice(device, modem: modem, hub: hub, names: names) { (target: Device) async throws -> Void in

        let result: DeviceTurnOnResult = try await target.turnOnFast(level: levelPercent)

        noteUndescribed("Light On Fast", isDescribed: result.isCommandDescribed)
        Output.line(DeviceText.turnedOn(device, result: result))

      }
    case .off:
      try await withDevice(device, modem: modem, hub: hub, names: names) { (target: Device) async throws -> Void in

        try await target.turnOff()

        Output.line(DeviceText.turnedOff(device))

      }
    case .offFast:
      try await withDevice(device, modem: modem, hub: hub, names: names) { (target: Device) async throws -> Void in

        let result: DeviceTurnOffResult = try await target.turnOffFast()

        noteUndescribed("Light Off Fast", isDescribed: result.isCommandDescribed)
        Output.line(DeviceText.turnedOff(device))

      }
    case let .instant(levelPercent):
      try await withDevice(device, modem: modem, hub: hub, names: names) { (target: Device) async throws -> Void in

        let result: DeviceInstantChangeResult = try await target.changeInstantly(to: levelPercent)

        noteUndescribed("Light Instant Change", isDescribed: result.isCommandDescribed)
        Output.line(DeviceText.changedInstantly(device, result: result))

      }
    case .beep:
      try await withDevice(device, modem: modem, hub: hub, names: names) { (target: Device) async throws -> Void in

        try await beep(target)

      }
    case let .settings(showsAdvanced):
      try await withDevice(device, modem: modem, hub: hub, names: names) { (target: Device) async throws -> Void in

        try await SettingsCommands.show(target, showsAdvanced: showsAdvanced, printsJSON: printsJSON)

      }
    case let .set(request):
      try await withDevice(device, modem: modem, hub: hub, names: names) { (target: Device) async throws -> Void in

        try await SettingsCommands.set(request, device: target)

      }
    case let .send(request):
      try await ExploreCommands.send(request, to: device, modem: modem)
    case .status:
      try await withDevice(device, modem: modem, hub: hub, names: names) { (target: Device) async throws -> Void in

        try await status(target, printsJSON: printsJSON)

      }
    case .links:
      try await IdentityStore.withNetwork(modem: modem, hub: hub, names: names) { (cached: CachedNetwork) async throws -> Void in

        try await links(device, network: cached.network, printsJSON: printsJSON)

      }
    }

  }

  // MARK: - Devices

  /// Runs `body` with the device on a network that starts from the identity cache and saves
  /// what it learned there, such as the device's level, and turns the libraries' refusals into
  /// sentences.
  private static func withDevice(
    _ address: InsteonAddress,
    modem: Modem,
    hub: HubLocation?,
    names: ProductNames,
    _ body: (Device) async throws -> Void
  ) async throws {

    try await IdentityStore.withNetwork(modem: modem, hub: hub, names: names) { (cached: CachedNetwork) async throws -> Void in

      let device: Device = cached.network.device(address, beforeIdentifying: { () -> Void in

        Output.note("Asking \(address) for its identity with ID Request...")

      })

      do {

        try await body(device)

      } catch let error as DeviceControlError {

        throw CommandFailure(description: DeviceText.failure(error, device: address))

      }

    }

  }

  // MARK: - Commands the catalog lists

  /// Notes that a command was sent although the Insteon device catalog doesn't describe the
  /// device's commands.
  private static func noteUndescribed(_ command: String, isDescribed: Bool) {

    if !isDescribed {

      Output.note(DeviceText.undescribedCommandNote(command))

    }

  }

  /// Beep, which the device is sent even when its command set doesn't list it.
  private static func beep(_ device: Device) async throws {

    let address: InsteonAddress = device.address
    let result: DeviceBeepResult

    do {

      result = try await device.beep()

    } catch ModemError.deviceRejected(_, let reason) {

      throw CommandFailure(description: DeviceText.beepRejected(address, reason: reason))

    } catch ModemError.deviceTimedOut {

      throw CommandFailure(description: DeviceText.beepUnanswered(address))

    }

    if !result.isListed {

      Output.note(DeviceText.unlistedBeepNote)

    }

    Output.line(DeviceText.beeped(address))

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

    /// The product key the Insteon device catalog gives, or `"none"` for a product it says
    /// reports none.
    let catalogProductKey: String?

    let product: String?

  }

  private static func identify(_ device: InsteonAddress, network: DeviceNetwork, names: ProductNames, printsJSON: Bool) async throws {

    // The network records the identity the device reports.
    let identification = try await network.identify(device)
    var productData: DeviceProductData?

    if identification.acceptsModem {

      productData = try await network.productData(of: device)

    }

    let identity = identification.identity
    let category = identity?.category ?? productData?.category
    let subcategory = identity?.subcategory ?? productData?.subcategory
    var product: String?

    if let category, let subcategory {

      product = names.name(category: category, subcategory: subcategory, firmwareVersion: identity?.firmwareVersion)

    }

    // What the catalog says the product reports explains a key that's missing.
    let catalogKey: DeviceIdentity.ProductKeyEntry? = await network.registry.device(device)?.deviceDescription.productKey

    // Newer devices leave the product key out, or report zeros; that's expected, not a failure.
    let productKey = productData?.productKey

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
        catalogProductKey: IdentityText.catalogProductKey(catalogKey),
        product: product
      ))

      return

    }

    // Each value is its own statement, which keeps the type checker quick.
    let categoryText: String = category.map(Names.category) ?? "not reported"
    let subcategoryText: String = subcategory.map { "\($0)" } ?? "not reported"
    let firmwareText: String = identity?.firmwareVersion.map { "\($0)" } ?? "not reported"
    let productKeyText: String = IdentityText.productKey(reported: productKey, answered: productData != nil, catalog: catalogKey)
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

  // MARK: - ping

  private static func ping(_ device: Device) async throws {

    let clock = ContinuousClock()
    let start = clock.now

    try await device.ping()

    let elapsed = start.duration(to: clock.now).components
    let milliseconds = elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000

    Output.line("\(device.address) answered in \(milliseconds) ms.")

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

  private static func status(_ device: Device, printsJSON: Bool) async throws {

    let status: DeviceStatus = try await device.status()

    if printsJSON {

      try Output.json(Status(
        address: "\(device.address)",
        level: Hex.byte(status.value),
        isOn: status.isOn,
        percent: status.percent,
        allLinkDatabaseDelta: Hex.byte(status.allLinkDatabaseDelta)
      ))

      return

    }

    Output.line(DeviceText.status(device.address, status: status))

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
