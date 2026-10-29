import InsteonCLICore
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
      let percent = levelPercent ?? 100

      try await modem.request(StandardMessage(to: device, command: StandardDirectCommand.on(level: LightLevel.level(percent: percent))))

      Output.line("Turned \(device) on at \(percent)%.")
    case .off:
      try await modem.request(StandardMessage(to: device, command: StandardDirectCommand.off))

      Output.line("Turned \(device) off.")
    case .status:
      try await status(device, modem: modem, printsJSON: printsJSON)
    case .links:
      try await links(device, modem: modem, printsJSON: printsJSON)
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

    if printsJSON {

      try Output.json(Identity(
        address: "\(device)",
        engine: Names.engine(identification.engine),
        acceptsModem: identification.acceptsModem,
        category: category.map { "\($0)" },
        categoryName: category?.name,
        subcategory: subcategory.map { "\($0)" },
        firmwareVersion: identity?.firmwareVersion.map { "\($0)" },
        productKey: productData.map { "\($0.productKey)" },
        product: product
      ))

      return

    }

    Output.table([
      ["Device:", "\(device)"],
      ["Engine:", Names.engine(identification.engine)],
      ["Category:", category.map(Names.category) ?? "not reported"],
      ["Subcategory:", subcategory.map { "\($0)" } ?? "not reported"],
      ["Firmware:", identity?.firmwareVersion.map { "\($0)" } ?? "not reported"],
      ["Product key:", productData.map { "\($0.productKey)" } ?? "not reported"],
      ["Product:", product ?? "not found in the Insteon device catalog"]
    ])

    if !identification.acceptsModem {

      Output.note("The device runs i2CS and isn't linked to the modem, so it won't say more. Link it first with 'insteon link'.")

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

  /// A device's status as `--json` prints it.
  struct Status: Encodable {

    let address: String

    let level: String

    let percent: Int

    let allLinkDatabaseDelta: String

  }

  private static func status(_ device: InsteonAddress, modem: Modem, printsJSON: Bool) async throws {

    // The acknowledgment carries the level in cmd2 and the ALL-Link database delta in cmd1.
    let acknowledgment = try await modem.request(StandardMessage(to: device, command: StandardDirectCommand.statusRequest()))
    let level = acknowledgment.command.command2
    let percent = LightLevel.percent(level: level)

    if printsJSON {

      try Output.json(Status(
        address: "\(device)",
        level: Hex.byte(level),
        percent: percent,
        allLinkDatabaseDelta: Hex.byte(acknowledgment.command.command1)
      ))

      return

    }

    Output.line("\(device) is \(percent == 0 ? "off" : "on at \(percent)%") (level \(Hex.byte(level))).")

  }

  // MARK: - links

  /// A record of a device's ALL-Link database as `--json` prints it.
  struct Record: Encodable {

    let memoryAddress: String

    let role: String

    let group: Int

    let address: String

    let data: [String]

  }

  private static func links(_ device: InsteonAddress, modem: Modem, printsJSON: Bool) async throws {

    Output.note("Reading the ALL-Link database of \(device), one record at a time...")

    // The last record marks the end of the database, and deleted records are no longer in use.
    let records = try await modem.readAllLinkDatabase(of: device)
      .filter { $0.record.flags.contains(.inUse) }
      .map { response in

        Record(
          memoryAddress: Hex.address(response.address),
          role: response.record.flags.contains(.controller) ? "controller" : "responder",
          group: Int(response.record.group.rawValue),
          address: "\(response.record.address)",
          data: [response.record.data1, response.record.data2, response.record.data3].map(Hex.byte)
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

    let rows: [[String]] = records.map { record in

      [record.memoryAddress, record.role, "\(record.group)", record.address, record.data.joined(separator: " ")]

    }

    Output.table([["MEMORY", "ROLE", "GROUP", "DEVICE", "DATA"]] + rows)
    Output.line()
    Output.line("\(records.count) records. A responder record's data is usually its on-level, ramp rate and button.")

  }

}
