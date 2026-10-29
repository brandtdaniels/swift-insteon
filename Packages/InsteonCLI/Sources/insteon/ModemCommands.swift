import InsteonCLICore
import InsteonLinking
import InsteonModem
import InsteonProtocol

/// The commands about the modem itself: `info`, `links`, `link` and `unlink`.
enum ModemCommands {

  // MARK: - info

  /// The modem's identity as `--json` prints it.
  struct Info: Encodable {

    let insteonID: String

    let category: String

    let categoryName: String?

    let subcategory: String

    let firmwareVersion: String

    let product: String?

  }

  static func info(_ modem: Modem, names: ProductNames, printsJSON: Bool) async throws {

    let info = try await modem.modemInfo()
    let product = names.name(category: info.category, subcategory: info.subcategory, firmwareVersion: info.firmwareVersion)

    if printsJSON {

      try Output.json(Info(
        insteonID: "\(info.address)",
        category: "\(info.category)",
        categoryName: info.category.name,
        subcategory: "\(info.subcategory)",
        firmwareVersion: "\(info.firmwareVersion)",
        product: product
      ))

      return

    }

    Output.table([
      ["Insteon ID:", "\(info.address)"],
      ["Category:", Names.category(info.category)],
      ["Subcategory:", "\(info.subcategory)"],
      ["Firmware:", "\(info.firmwareVersion)"],
      ["Product:", product ?? "not in the Insteon device catalog"]
    ])

  }

  // MARK: - links

  /// A record of the modem's ALL-Link database as `--json` prints it.
  struct Record: Encodable {

    let role: String

    let group: Int

    let address: String

    let data: [String]

    let product: String?

  }

  static func links(_ modem: Modem, names: ProductNames, printsJSON: Bool) async throws {

    Output.note("Reading the modem's ALL-Link database...")

    let records = try await modem.allLinkRecords()

    // A controller record holds the linked device's category, subcategory and firmware
    // version, which names the device in its responder records too.
    var products: [InsteonAddress: String] = [:]

    for record in records where record.flags.contains(.controller) {

      let product = names.name(
        category: DeviceCategory(rawValue: record.data1),
        subcategory: DeviceSubcategory(rawValue: record.data2),
        firmwareVersion: FirmwareVersion(rawValue: record.data3)
      )

      if let product, products[record.address] == nil {

        products[record.address] = product

      }

    }

    let rows = records.map { record in

      Record(
        role: record.flags.contains(.controller) ? "controller" : "responder",
        group: Int(record.group.rawValue),
        address: "\(record.address)",
        data: [record.data1, record.data2, record.data3].map(Hex.byte),
        product: products[record.address]
      )

    }

    if printsJSON {

      try Output.json(rows)

      return

    }

    guard !rows.isEmpty else {

      Output.line("The modem's ALL-Link database is empty.")

      return

    }

    let table: [[String]] = rows.map { row in

      [row.role, "\(row.group)", row.address, row.data.joined(separator: " "), row.product ?? ""]

    }

    Output.table([["ROLE", "GROUP", "DEVICE", "DATA", "PRODUCT"]] + table)
    Output.line()
    Output.line("\(rows.count) records. The modem controls a device in a controller record, and responds to it in a responder record.")

  }

  // MARK: - link and unlink

  /// A link the modem reported as `--json` prints it.
  struct Link: Encodable {

    let address: String

    let group: Int

    let modemRole: String

    let category: String?

    let subcategory: String?

    let firmwareVersion: String?

    let product: String?

  }

  static func link(_ modem: Modem, options: LinkOptions, names: ProductNames, printsJSON: Bool) async throws {

    let timeout = options.timeoutSeconds.map { Duration.seconds($0) } ?? Linker.defaultManualLinkingTimeout

    if options.role == .responder {

      Output.note("First hold the device's SET button until it enters linking mode.")

    }

    Output.note(
      "The modem is in linking mode for group \(options.group). Press and hold the device's SET button "
        + "until it beeps or its light blinks. Waiting up to \(seconds(timeout)) seconds; Control-C stops."
    )

    let link: AllLinkingCompleted

    switch options.role {
    case .controller:
      link = try await Linker(modem: modem).linkManually(modemRole: .controller, group: options.group, timeout: timeout)
    case .responder:
      link = try await Linker(modem: modem).linkManually(modemRole: .responder, group: options.group, timeout: timeout)
    case .either:
      link = try await linkEither(modem, group: options.group, timeout: timeout)
    }

    try await report(link, verb: "Linked", modem: modem, names: names, printsJSON: printsJSON)

  }

  static func unlink(_ modem: Modem, options: UnlinkOptions, names: ProductNames, printsJSON: Bool) async throws {

    let timeout = options.timeoutSeconds.map { Duration.seconds($0) } ?? Linker.defaultManualLinkingTimeout
    let role: ModemRole = options.role == .responder ? .responder : .controller

    if role == .responder {

      Output.note("First put the device into unlinking mode with its SET button.")

    }

    Output.note(
      "The modem is in unlinking mode for group \(options.group). Press and hold the device's SET button "
        + "until it beeps or its light blinks. Waiting up to \(seconds(timeout)) seconds; Control-C stops."
    )

    let link = try await Unlinker(modem: modem).unlinkManually(modemRole: role, group: options.group, timeout: timeout)

    try await report(link, verb: "Unlinked", modem: modem, names: names, printsJSON: printsJSON)

  }

  static func cancelLinking(_ modem: Modem) async throws {

    try await modem.send(.cancelAllLinking)

    Output.line("The modem has left linking mode.")

  }

  /// Links with the modem as controller or responder, whichever the device asks for.
  ///
  /// `Linker` links in one role, so this sends Start ALL-Linking with code `0x03` itself and
  /// waits for the modem's report, taking the modem out of linking mode if none comes, or if
  /// the report is of a deleted link rather than a new one.
  private static func linkEither(_ modem: Modem, group: AllLinkGroupNumber, timeout: Duration) async throws -> AllLinkingCompleted {

    // Listening starts before the modem enters linking mode, so the report can't be missed.
    let replies = await modem.replies()
    let link: AllLinkingCompleted?

    do {

      try await modem.send(.startAllLinking(mode: .controllerOrResponder, group: group))

      link = try await Replies.first(in: replies, within: timeout) { (reply: ModemReply) -> AllLinkingCompleted? in

        guard case let .allLinkingCompleted(completed) = reply else {

          return nil

        }

        return completed

      }

    } catch {

      await cancelAllLinking(modem)

      throw error

    }

    guard let link else {

      await cancelAllLinking(modem)

      throw LinkingError.linkingTimedOut

    }

    // A deleted link means the device removed one, which linking mode didn't ask for.
    guard link.mode != .delete else {

      await cancelAllLinking(modem)

      throw LinkingError.unexpectedLink(link)

    }

    return link

  }

  /// Takes the modem out of linking mode, in a task of its own so it's sent even when this
  /// task was canceled by Control-C.
  private static func cancelAllLinking(_ modem: Modem) async {

    await Task {

      _ = try? await modem.send(.cancelAllLinking)

    }.value

  }

  /// Prints the device a link was made or removed with, asking the device for its identity
  /// when the modem didn't report it.
  private static func report(_ link: AllLinkingCompleted, verb: String, modem: Modem, names: ProductNames, printsJSON: Bool) async throws {

    var category = link.category
    var subcategory = link.subcategory
    var firmwareVersion = link.firmwareVersion

    // The modem reports the device's identity only when it became the controller.
    if category == nil, link.mode != .delete {

      Output.note("Asking \(link.address) for its identity...")

      if let identity = try? await DeviceIdentifier(modem: modem).identify(link.address).identity {

        category = identity.category
        subcategory = identity.subcategory
        firmwareVersion = identity.firmwareVersion

      }

    }

    var product: String?

    if let category, let subcategory {

      product = names.name(category: category, subcategory: subcategory, firmwareVersion: firmwareVersion)

    }

    if printsJSON {

      try Output.json(Link(
        address: "\(link.address)",
        group: Int(link.group.rawValue),
        modemRole: Names.mode(link.mode),
        category: category.map { "\($0)" },
        subcategory: subcategory.map { "\($0)" },
        firmwareVersion: firmwareVersion.map { "\($0)" },
        product: product
      ))

      return

    }

    Output.line("\(verb) \(link.address) in group \(link.group).")
    Output.table([
      ["Device:", "\(link.address)"],
      ["Modem role:", Names.mode(link.mode)],
      ["Category:", category.map(Names.category) ?? "not reported"],
      ["Subcategory:", subcategory.map { "\($0)" } ?? "not reported"],
      ["Firmware:", firmwareVersion.map { "\($0)" } ?? "not reported"],
      ["Product:", product ?? "not found in the Insteon device catalog"]
    ])

  }

  /// A duration in whole seconds.
  private static func seconds(_ duration: Duration) -> Int64 {

    duration.components.seconds

  }

}

/// Waits for replies from the modem.
enum Replies {

  /// The first reply `match` reads a value from, or `nil` if none arrives in time.
  ///
  /// - Throws: `ModemError.connectionClosed` if the modem closes first, or
  ///   `CancellationError` if the task is canceled.
  static func first<Value: Sendable>(
    in replies: AsyncStream<ModemReply>,
    within timeout: Duration,
    _ match: @escaping @Sendable (ModemReply) -> Value?
  ) async throws -> Value? {

    try await withThrowingTaskGroup(of: Value?.self) { group in

      group.addTask {

        for await reply in replies {

          if let value = match(reply) {

            return value

          }

        }

        // The stream ends early only when this task is canceled or the modem closes.
        try Task.checkCancellation()

        throw ModemError.connectionClosed

      }

      group.addTask {

        try await Task.sleep(for: timeout)

        return nil

      }

      defer { group.cancelAll() }

      return try await group.next() ?? nil

    }

  }

}
