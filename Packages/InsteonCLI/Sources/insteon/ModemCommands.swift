import InsteonCLISupport
import InsteonCore

/// The commands about the modem itself: `info`, `links`, `link`, `unlink` and `remove`.
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

  static func info(_ modem: ModemSession, names: ProductNames, printsJSON: Bool) async throws {

    let info = try await modem.info()
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

    var rows = [
      ["Insteon ID:", "\(info.address)"],
      ["Category:", Names.category(info.category)],
      ["Subcategory:", "\(info.subcategory)"],
      ["Firmware:", "\(info.firmwareVersion)"]
    ]

    if names.catalog != nil {

      rows.append(["Product:", product ?? "not in the Insteon device catalog"])

    }

    Output.table(rows)

  }

  // MARK: - links

  /// A record of the modem's ALL-Link database as `--json` prints it.
  ///
  /// The category, subcategory, firmware version and product come from the device's identity,
  /// when it's known, never from the record's data bytes; they're left out otherwise.
  struct Record: Encodable {

    let role: String

    let group: Int

    let address: String

    let data: [String]

    let category: String?

    let subcategory: String?

    let firmwareVersion: String?

    let product: String?

  }

  static func links(_ modem: ModemSession, hub: HubLocation?, options: LinksOptions, names: ProductNames, printsJSON: Bool) async throws {

    Output.note("Reading the modem's ALL-Link database...")

    try await IdentityStore.withNetwork(modem: modem, hub: hub, names: names) { (cached: CachedNetwork) async throws -> Void in

      try await links(cached, options: options, printsJSON: printsJSON)

    }

  }

  private static func links(_ cached: CachedNetwork, options: LinksOptions, printsJSON: Bool) async throws {

    let network: DeviceNetwork = cached.network
    let entries: [ModemDatabaseEntry] = try await network.modemDatabase()

    if options.identifiesDevices {

      var asked: Set<InsteonAddress> = []

      for entry in entries where asked.insert(entry.record.address).inserted {

        try await identify(entry.record.address, network: network)

        // Each identity is saved as it's learned, so a second Control-C, which ends the
        // command at once, loses at most the one being asked for.
        await cached.save()

      }

    }

    var rows: [Record] = []

    for entry in entries {

      let record: AllLinkRecord = entry.record
      // A device identified above is described from the registry.
      let registered: RegisteredDevice? = options.identifiesDevices ? await network.registry.device(record.address) : entry.device
      let known: DeviceDescription? = registered?.deviceDescription

      rows.append(Record(
        role: record.flags.contains(.controller) ? "controller" : "responder",
        group: Int(record.group.rawValue),
        address: "\(record.address)",
        data: [record.data1, record.data2, record.data3].map(Hex.byte),
        category: known.map { "\($0.category)" },
        subcategory: known.map { "\($0.subcategory)" },
        firmwareVersion: known?.firmwareVersion.map { "\($0)" },
        product: known?.displayName
      ))

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
    Output.line(
      "\(Wording.count(rows.count, "record")). The modem controls a device in a controller record, and responds to it in a responder record."
    )

    if !options.identifiesDevices, entries.contains(where: { (entry: ModemDatabaseEntry) -> Bool in entry.device == nil }) {

      Output.note(
        "Devices are named from the identities they reported to 'insteon link' and 'insteon device ADDRESS id'. "
          + "'insteon links --identify' asks each device with ID Request."
      )

    }

  }

  /// Asks a device for its identity through the network, which records it, saying on
  /// standard error if it didn't answer.
  ///
  /// - Throws: `CancellationError` after Control-C; other errors are reported and passed
  ///   over, so one device that doesn't answer doesn't stop the list.
  private static func identify(_ device: InsteonAddress, network: DeviceNetwork) async throws {

    Output.note("Asking \(device) for its identity with ID Request...")

    do {

      let identification = try await network.identify(device)

      guard identification.identity == nil else {

        return

      }

      Output.note(
        identification.acceptsModem
          ? "\(device) didn't report its identity."
          : "\(device) runs i2CS and has no link to the modem, so it won't say what it is."
      )

    } catch let error as CancellationError {

      throw error

    } catch {

      Output.note(Names.message(for: error))

    }

  }

  // MARK: - link

  static func link(_ modem: ModemSession, options: LinkOptions, names: ProductNames, printsJSON: Bool) async throws {

    try await IdentityStore.withNetwork(modem: modem, hub: nil, names: names) { (cached: CachedNetwork) async throws -> Void in

      try await link(cached, options: options, names: names, printsJSON: printsJSON)

    }

  }

  /// Links a device by its address, or whichever device's SET button is pressed, through the
  /// network's coordinator, which says what to do as it goes.
  private static func link(_ cached: CachedNetwork, options: LinkOptions, names: ProductNames, printsJSON: Bool) async throws {

    let timeout: Duration = options.timeoutSeconds.map { (seconds: Int) -> Duration in .seconds(seconds) } ?? DeviceLinkingCoordinator.defaultSETButtonTimeout
    let observer = LinkingPrompter(names: names, printsJSON: printsJSON, cached: cached)
    let coordinator: DeviceLinkingCoordinator = cached.network.linking
    // Linked back when the catalog says the device controls, by default, whether it's linked
    // by its address or its SET button.
    let twoWay: TwoWayLinking = options.twoWay
    let result: DeviceLinkingResult

    if let device = options.device {

      result = try await coordinator.link(
        device,
        as: options.role == .responder ? .responder : .controller,
        group: options.group,
        twoWay: twoWay,
        setButtonTimeout: timeout,
        usesCatalogLegs: options.followsCatalogLegs,
        observer: observer
      )

    } else {

      result = try await coordinator.linkBySETButton(as: manualRole(options.role), group: options.group, twoWay: twoWay, timeout: timeout, observer: observer)

    }

    if printsJSON {

      try Output.json(LinkingJSON.report(result, message: Names.message(for:)))

    }

    if let incomplete = LinkingEventText.incompleteLegs(result, message: Names.message(for:)) {

      throw CommandFailure(description: incomplete)

    }

    if let failure = result.linkBackFailure, let first = result.links.first {

      throw CommandFailure(
        description: "\(first.address) is linked with the modem as controller, but it didn't link back: \(Names.message(for: failure)) "
          + "To link back with its SET button, run 'insteon link \(first.address) --responder'."
      )

    }

  }

  /// The modem's role in a SET button link.
  private static func manualRole(_ role: LinkingRole) -> ManualLinkingRole {

    switch role {
    case .controller:
      return .controller
    case .responder:
      return .responder
    case .either:
      return .either
    }

  }

  // MARK: - unlink

  static func unlink(_ modem: ModemSession, options: UnlinkOptions, names: ProductNames, printsJSON: Bool) async throws {

    try await IdentityStore.withNetwork(modem: modem, hub: nil, names: names) { (cached: CachedNetwork) async throws -> Void in

      let coordinator: DeviceLinkingCoordinator = cached.network.linking
      let observer = LinkingPrompter(names: names, printsJSON: printsJSON, cached: cached)

      if options.removesAllLinks, let device = options.device {

        try await unlinkAll(device, coordinator: coordinator, options: options, observer: observer, printsJSON: printsJSON)

        return

      }

      let timeout: Duration = options.timeoutSeconds.map { (seconds: Int) -> Duration in .seconds(seconds) } ?? DeviceLinkingCoordinator.defaultSETButtonTimeout

      let result: DeviceUnlinkingResult = try await coordinator.unlink(
        options.device,
        as: options.role == .responder ? .responder : .controller,
        group: options.group,
        timeout: timeout,
        observer: observer
      )

      if printsJSON {

        try Output.json(LinkingJSON.unlink(result.link))

      }

    }

  }

  /// Removes every link between the modem and a device, in both directions, without its SET
  /// button; the coordinator says how to remove what's left with the SET button if that fails.
  private static func unlinkAll(
    _ device: InsteonAddress,
    coordinator: DeviceLinkingCoordinator,
    options: UnlinkOptions,
    observer: LinkingPrompter,
    printsJSON: Bool
  ) async throws {

    let timeout: Duration = options.timeoutSeconds.map { (seconds: Int) -> Duration in .seconds(seconds) } ?? DeviceLinkingCoordinator.defaultRemoteTimeout
    let result: DeviceUnlinkingAllResult

    do {

      result = try await coordinator.unlinkAll(device, timeout: timeout, observer: observer)

    } catch let failure as RemoteUnlinkingError {

      let label: String = LinkingInstructions.deviceLabel(device, profile: failure.deviceDescription?.profile)

      throw CommandFailure(description: "\(label) wasn't unlinked without its SET button: \(Names.message(for: failure.underlying))")

    }

    if printsJSON {

      try Output.json(LinkingJSON.removedLinks(result.removed))

    }

  }

  // MARK: - remove

  /// Removes a device from the network through the network's coordinator, which says what it
  /// does as it goes, after asking the person first when `asks` is `true`.
  static func remove(_ modem: ModemSession, options: RemoveOptions, asks: Bool, names: ProductNames, printsJSON: Bool) async throws {

    try await IdentityStore.withNetwork(modem: modem, hub: nil, names: names) { (cached: CachedNetwork) async throws -> Void in

      let device: InsteonAddress = options.device
      let known: RegisteredDevice? = await cached.network.registry.device(device)
      let label: String = LinkingInstructions.deviceLabel(device, profile: known?.deviceDescription.profile)

      if asks {

        let question: String = RemovalText.question(device: label, forcesModemSide: options.forcesModemSide)

        guard try await Terminal.confirm(question) else {

          throw CommandFailure(description: RemovalText.declined(device: label))

        }

      }

      let timeout: Duration = options.timeoutSeconds.map { (seconds: Int) -> Duration in .seconds(seconds) } ?? DeviceLinkingCoordinator.defaultRemoteTimeout
      let observer = LinkingPrompter(names: names, printsJSON: printsJSON, cached: cached)
      let result: DeviceRemovalResult

      do {

        result = try await cached.network.linking.remove(
          device,
          scan: options.scansOtherDevices,
          forceModemSide: options.forcesModemSide,
          timeout: timeout,
          observer: observer
        )

      } catch let failure as RemoteUnlinkingError {

        throw CommandFailure(description: RemovalText.notRemoved(device, device: label, reason: Names.message(for: failure.underlying)))

      }

      if printsJSON {

        try Output.json(LinkingJSON.removal(result, message: Names.message(for:)))

      }

      // A device whose links aren't confirmed gone stays in the cache, and the command fails.
      if let reason = result.keptBecause {

        throw CommandFailure(description: RemovalText.kept(device, device: label, reason: reason, message: Names.message(for:)))

      }

    }

  }

  static func cancelLinking(_ modem: ModemSession) async throws {

    try await modem.cancelLinking()

    Output.line("The modem has left linking mode.")

  }

  // MARK: - Helpers

  /// Prints a new link, with the device's identity when it's known. Pass `nil` for `known` to
  /// print the link alone.
  static func report(_ link: AllLinkingCompleted, known: DeviceDescription?, names: ProductNames) {

    Output.line("Linked \(link.address) in group \(link.group), modem as \(Names.mode(link.mode)).")

    guard let known else {

      return

    }

    var rows = [
      ["Category:", Names.category(known.category)],
      ["Subcategory:", "\(known.subcategory)"],
      ["Firmware:", known.firmwareVersion.map { "\($0)" } ?? "not reported"]
    ]

    if names.catalog != nil {

      rows.append(["Product:", known.displayName ?? "not in the Insteon device catalog"])

    }

    Output.table(rows)

  }

}
