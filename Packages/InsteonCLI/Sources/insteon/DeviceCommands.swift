import InsteonCLICore
import InsteonDeviceCatalog
import InsteonLinking
import InsteonModem
import InsteonProtocol

/// `insteon device ADDRESS ACTION`: commands sent to one device.
enum DeviceCommands {

  static func run(_ action: DeviceAction, device: InsteonAddress, modem: Modem, names: ProductNames, printsJSON: Bool) async throws {

    switch action {
    case .id:
      try await identify(device, modem: modem, names: names, printsJSON: printsJSON)
    case .ping:
      try await ping(device, modem: modem)
    case let .on(levelPercent):
      // A level means something only to a device that dims, so the device is looked up first.
      var kind: GroupType.Kind?

      if levelPercent != nil {

        kind = await Identities.known(device, modem: modem, names: names, asking: true)?.mainGroupType?.kind

      }

      try await modem.request(StandardMessage(to: device, command: StandardDirectCommand.on(level: ControlText.level(percent: levelPercent, kind: kind))))

      Output.line(ControlText.turnedOn(device, percent: levelPercent, kind: kind))
    case .off:
      try await modem.request(StandardMessage(to: device, command: StandardDirectCommand.off))

      Output.line("Turned \(device) off.")
    case .status:
      try await status(device, modem: modem, names: names, printsJSON: printsJSON)
    case .links:
      try await links(device, modem: modem, names: names, printsJSON: printsJSON)
    }

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

  private static func identify(_ device: InsteonAddress, modem: Modem, names: ProductNames, printsJSON: Bool) async throws {

    let identification = try await DeviceIdentifier(modem: modem).identify(device)
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

    if let identity {

      IdentityStore.remember(KnownIdentity(identity), for: device)

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
    let productKeyText: String = productKey.map { "\($0)" } ?? "none; newer devices don't report one"
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

    // Listening starts before the request, so the response can't be missed.
    let replies = await modem.replies()

    do {

      try await modem.request(StandardMessage(to: device, command: StandardDirectCommand.productDataRequest))

    } catch let error as ModemError {

      // Not every device answers Product Data Request.
      switch error {
      case .deviceRejected, .deviceTimedOut:
        return nil
      default:
        throw error
      }

    }

    return try await Replies.first(in: replies, within: Modem.defaultExtendedRequestTimeout) { (reply: ModemReply) -> ProductData? in

      guard case let .messageReceived(message) = reply, message.sender == device else {

        return nil

      }

      return ProductData(message)

    }

  }

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

    let kind = await Identities.known(device, modem: modem, names: names, asking: true)?.mainGroupType?.kind

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

  private static func links(_ device: InsteonAddress, modem: Modem, names: ProductNames, printsJSON: Bool) async throws {

    let known = await Identities.known(device, modem: modem, names: names, asking: true)

    Output.note("Reading the ALL-Link database of \(device), one record at a time...")

    // The last record marks the end of the database, and deleted records are no longer in use.
    let records = try await modem.readAllLinkDatabase(of: device)
      .filter { $0.record.flags.contains(.inUse) }
      .map { response in

        let record = response.record
        let data = [record.data1, record.data2, record.data3]
        let isController = record.flags.contains(.controller)

        return Record(
          memoryAddress: Hex.address(response.address),
          role: isController ? "controller" : "responder",
          group: Int(record.group.rawValue),
          address: "\(record.address)",
          data: data.map(Hex.byte),
          meaning: known.flatMap { meaning(of: data, isController: isController, group: record.group, in: $0) }
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
    let rows: [[String]] = records.map { record in

      [record.memoryAddress, record.role, "\(record.group)", record.address, record.data.joined(separator: " ")]
        + (explains ? [record.meaning ?? ""] : [])

    }

    Output.table([["MEMORY", "ROLE", "GROUP", "DEVICE", "DATA"] + (explains ? ["MEANING"] : [])] + rows)
    Output.line()

    if explains, let product = known?.productName {

      Output.line("\(Wording.count(records.count, "record")) in use. The data is read as the Insteon device catalog gives it for \(product).")

    } else {

      Output.line(
        "\(Wording.count(records.count, "record")) in use. What the data means depends on the device, "
          + "which the Insteon device catalog doesn't describe here."
      )

    }

  }

  /// What a record's data bytes hold, from the device's group type.
  private static func meaning(of data: [UInt8], isController: Bool, group: AllLinkGroupNumber, in device: KnownDevice) -> String? {

    // A controller record's group is the device's own; a responder record's is its
    // controller's, so the device's group comes from the data, or is its main one.
    let type = isController ? device.groupType(forGroup: group) ?? device.mainGroupType : device.responderGroupType(forRecordData: data)

    guard let type else {

      return nil

    }

    return LinkDataText.explanation(
      data: data,
      bytes: isController ? type.linkData.controller : type.linkData.responder,
      tables: device.commandSet?.valueTables ?? []
    )

  }

}
