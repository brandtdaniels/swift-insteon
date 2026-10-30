import InsteonCLICore
import InsteonDeviceCatalog
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

  static func links(_ modem: Modem, options: LinksOptions, names: ProductNames, printsJSON: Bool) async throws {

    Output.note("Reading the modem's ALL-Link database...")

    let records = try await modem.allLinkRecords()
    var identities = IdentityStore.load()

    if options.identifiesDevices {

      var asked: Set<InsteonAddress> = []

      for record in records where asked.insert(record.address).inserted {

        if let identity = try await identify(record.address, modem: modem) {

          identities[record.address] = identity

        }

      }

    }

    let rows = records.map { record in

      let known = identities[record.address].map(names.device)

      return Record(
        role: record.flags.contains(.controller) ? "controller" : "responder",
        group: Int(record.group.rawValue),
        address: "\(record.address)",
        data: [record.data1, record.data2, record.data3].map(Hex.byte),
        category: known.map { "\($0.category)" },
        subcategory: known.map { "\($0.subcategory)" },
        firmwareVersion: known?.firmwareVersion.map { "\($0)" },
        product: known?.displayName
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
    Output.line(
      "\(Wording.count(rows.count, "record")). The modem controls a device in a controller record, and responds to it in a responder record."
    )

    if !options.identifiesDevices, rows.contains(where: { $0.category == nil }) {

      Output.note(
        "Devices are named from the identities they reported to 'insteon link' and 'insteon device ADDRESS id'. "
          + "'insteon links --identify' asks each device with ID Request."
      )

    }

  }

  /// Asks a device for its identity and remembers it, saying on standard error if it didn't
  /// answer.
  ///
  /// - Throws: `CancellationError` after Control-C; other errors are reported and passed
  ///   over, so one device that doesn't answer doesn't stop the list.
  private static func identify(_ device: InsteonAddress, modem: Modem) async throws -> ReportedIdentity? {

    Output.note("Asking \(device) for its identity with ID Request...")

    do {

      let identification = try await DeviceIdentifier(modem: modem).identify(device)

      guard let pressed = identification.identity else {

        Output.note(
          identification.acceptsModem
            ? "\(device) didn't report its identity."
            : "\(device) runs i2CS and has no link to the modem, so it won't say what it is."
        )

        return nil

      }

      let identity = ReportedIdentity(pressed)

      IdentityStore.remember(identity, for: device)

      return identity

    } catch let error as CancellationError {

      throw error

    } catch {

      Output.note(Names.message(for: error))

      return nil

    }

  }

  // MARK: - link

  /// A link the modem reported as `--json` prints it, with the device's identity when it's
  /// known.
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
    let first: AllLinkingCompleted

    if let device = options.device {

      first = try await linkByAddress(device, options: options, timeout: timeout, modem: modem, names: names)

    } else {

      first = try await linkBySETButton(options: options, timeout: timeout, modem: modem)

    }

    let known = try await Identities.learn(from: first, modem: modem, names: names)
    var made = [first]

    if !printsJSON {

      report(first, known: known, names: names)

    }

    // A device that can control is linked back, so the modem hears its buttons.
    let linksBack = first.mode == .controller && (options.isTwoWay || (options.device != nil && canControl(known)))
    var failure: (any Error)?

    if linksBack {

      Output.note(
        "Linking back: sending \(first.address) Enter Linking Mode for its group \(LinkOptions.deviceGroup), "
          + "so the modem becomes its responder..."
      )

      do {

        let back = try await Linker(modem: modem).linkRemotely(
          first.address,
          modemRole: .responder,
          modemGroup: LinkOptions.deviceGroup,
          deviceGroup: LinkOptions.deviceGroup
        )

        made.append(back)

        if !printsJSON {

          // The first leg printed the device's identity already.
          report(back, known: nil, names: names)

        }

      } catch let error as CancellationError {

        throw error

      } catch {

        failure = error

      }

    }

    if printsJSON {

      let reports = made.map { json(for: $0, known: known) }

      if reports.count == 1 {

        try Output.json(reports[0])

      } else {

        try Output.json(reports)

      }

    }

    if let failure {

      throw CommandFailure(
        description: "\(first.address) is linked with the modem as controller, but it didn't link back: \(Names.message(for: failure)) "
          + "To link back with its SET button, run 'insteon link \(first.address) --responder'."
      )

    }

  }

  /// Links a device by its address: the modem starts ALL-Linking and sends the device Enter
  /// Linking Mode, extended for i2CS. A device that doesn't answer, such as an i2CS device that
  /// isn't linked yet, is linked with its SET button instead, and only its link is accepted.
  private static func linkByAddress(
    _ device: InsteonAddress,
    options: LinkOptions,
    timeout: Duration,
    modem: Modem,
    names: ProductNames
  ) async throws -> AllLinkingCompleted {

    let role: ModemRole = options.role == .responder ? .responder : .controller
    let modemGroup = role == .responder ? LinkOptions.deviceGroup : options.group
    let linker = Linker(modem: modem)
    let known: DeviceDescription? = try await Identities.known(device, modem: modem, names: names, asking: false)

    // The device responds, so it memorizes its state as its on-level for the group. Light On
    // goes only to a device the catalog says is a light or switched load.
    if role == .controller {

      if known?.setsOnLevelFromLoadWhenLinked == true {

        try await turnOnBeforeLinking(device, linker: linker)

      } else {

        Output.note(
          "Not turning \(device) on first: the catalog doesn't identify it as a light or switched load, "
            + "so it links with whatever on-level it captures."
        )

      }

    }

    Output.note(
      "Linking \(device) without its SET button: the modem starts ALL-Linking as \(role == .controller ? "controller" : "responder") "
        + "and sends the device Enter Linking Mode..."
    )

    do {

      return try await linker.linkRemotely(device, modemRole: role, modemGroup: modemGroup, deviceGroup: LinkOptions.deviceGroup)

    } catch let error as CancellationError {

      throw error

    } catch let LinkingError.unexpectedLink(link) {

      throw CommandFailure(description: LinkOutcome.mismatch(link, mode: .linking, device: device) ?? Names.message(for: LinkingError.unexpectedLink(link)))

    } catch {

      Output.note("\(device) didn't link remotely: \(Names.message(for: error)) Link it with its SET button instead.")

    }

    let steps = known?.profile?.lifecycle?.linking.map(LinkingInstructions.steps(of:)) ?? []
    let label = deviceLabel(device, known: known)

    if role == .responder {

      try await deviceGoesFirst(.linking, device: label, steps: steps)
      Output.note("The modem is joining as responder. Waiting up to \(seconds(timeout)) seconds; Control-C stops.")

      return try await linker.linkManually(as: .responder, group: modemGroup, device: device, timeout: timeout)

    }

    let lines: [String] = LinkingInstructions.modemFirst(.linking, group: modemGroup, seconds: seconds(timeout), device: label, steps: steps)

    return try await linker.linkManually(as: .controller, group: modemGroup, device: device, timeout: timeout, ready: notes(lines))

  }

  /// Turns a light or switched load fully on before it links as a responder, so it memorizes
  /// full on as its on-level for the group, rather than off. A device that doesn't turn on,
  /// such as an i2CS device that isn't linked to the modem yet, links in whatever state it's in.
  ///
  /// - Throws: `CancellationError` after Control-C.
  private static func turnOnBeforeLinking(_ device: InsteonAddress, linker: Linker) async throws {

    Output.note("Turning \(device) on with Light On first, so it links with full on as its on-level...")

    do {

      try await linker.prepareResponder(device)

    } catch let error as CancellationError {

      throw error

    } catch {

      Output.note("\(device) didn't turn on: \(Names.message(for: error)) It links in the state it's in; if it's off, turn it on first.")

    }

  }

  /// Links whichever device's SET button is pressed.
  private static func linkBySETButton(options: LinkOptions, timeout: Duration, modem: Modem) async throws -> AllLinkingCompleted {

    let linker = Linker(modem: modem)

    switch options.role {
    case .responder:
      try await deviceGoesFirst(.linking, device: nil, steps: [])
      Output.note("The modem is joining as responder. Waiting up to \(seconds(timeout)) seconds; Control-C stops.")

      return try await linker.linkManually(as: .responder, group: options.group, timeout: timeout)
    case .controller, .either:
      let role: ManualLinkingRole = options.role == .either ? .either : .controller
      let lines: [String] = LinkingInstructions.modemFirst(.linking, group: options.group, seconds: seconds(timeout), device: nil, steps: [])

      return try await linker.linkManually(as: role, group: options.group, timeout: timeout, ready: notes(lines))
    }

  }

  // MARK: - unlink

  /// A removed link as `--json` prints it.
  struct Unlink: Encodable {

    let address: String

    let group: Int

    let product: String?

  }

  static func unlink(_ modem: Modem, options: UnlinkOptions, names: ProductNames, printsJSON: Bool) async throws {

    if options.removesAllLinks, let device = options.device {

      try await unlinkAll(device, modem: modem, options: options, names: names, printsJSON: printsJSON)

      return

    }

    let timeout = options.timeoutSeconds.map { Duration.seconds($0) } ?? Linker.defaultManualLinkingTimeout
    let known = options.device.flatMap { IdentityStore.load()[$0] }.map(names.device)
    let label = options.device.map { deviceLabel($0, known: known) }
    let cache = AllLinkDatabaseCache(modem: modem)
    let unlinker = Unlinker(modem: modem, cache: cache)
    let group: AllLinkGroupNumber = try await unlinkGroup(cache, options: options)
    let link: AllLinkingCompleted

    if options.role == .responder {

      // The device is the controller, so it goes into unlinking mode first, then the modem
      // joins in linking mode as its responder.
      try await deviceGoesFirst(.unlinking, device: label, steps: known?.profile?.lifecycle?.unlinking.map(LinkingInstructions.steps(of:)) ?? [])
      Output.note("The modem is joining as responder. Waiting up to \(seconds(timeout)) seconds; Control-C stops.")
      link = try await unlinker.unlinkManually(as: .responder, group: group, device: options.device, timeout: timeout)

    } else {

      // A responder leaves a controller's group the way it joins one, so the device's
      // linking steps apply.
      let steps = known?.profile?.lifecycle?.linking.map(LinkingInstructions.steps(of:)) ?? []
      let lines: [String] = LinkingInstructions.modemFirst(.unlinking, group: group, seconds: seconds(timeout), device: label, steps: steps)

      link = try await unlinker.unlinkManually(as: .controller, group: group, device: options.device, timeout: timeout, ready: notes(lines))

    }

    // A deletion carries no identity, so the device is named only if it was known before.
    let removed: DeviceDescription? = IdentityStore.load()[link.address].map(names.device)
    let product: String? = removed?.displayName

    if printsJSON {

      try Output.json(Unlink(address: "\(link.address)", group: Int(link.group.rawValue), product: product))

    } else {

      Output.line("Unlinked \(LinkingInstructions.deviceLabel(link.address, profile: removed?.profile)) from group \(link.group).")

    }

    try await noteRemainingLinks(of: link.address, cache: cache)

  }

  /// A link `unlink ADDRESS --all` removed, as `--json` prints it.
  struct RemovedLink: Encodable {

    let address: String

    let group: Int

    let modemRole: String

    let product: String?

  }

  /// Removes every link between the modem and a device, in both directions, without its SET
  /// button, and says how to remove what's left with the SET button if that fails.
  private static func unlinkAll(_ device: InsteonAddress, modem: Modem, options: UnlinkOptions, names: ProductNames, printsJSON: Bool) async throws {

    let timeout = options.timeoutSeconds.map { Duration.seconds($0) } ?? Linker.defaultRemoteLinkingTimeout
    let known: DeviceDescription? = IdentityStore.load()[device].map(names.device)
    let label: String = deviceLabel(device, known: known)
    let cache = AllLinkDatabaseCache(modem: modem)
    let unlinker = Unlinker(modem: modem, cache: cache)
    // Battery-powered i2CS devices take Enter Unlinking Mode extended.
    let isBatteryPowered: Bool = known?.profile?.isBatteryPowered ?? false
    let unlinkingMode: UnlinkingModeMessage = isBatteryPowered ? .extendedForI2cs : .standard

    Output.note("Reading the modem's ALL-Link database for \(device)'s links...")

    let removed: [ModemLink]

    do {

      removed = try await unlinker.unlinkAllRemotely(device, unlinkingMode: unlinkingMode, timeout: timeout) { (link: ModemLink) async -> Void in

        Output.note(LinkingInstructions.remoteUnlinking(modemRole: link.modemRole, device: label, group: link.group))

      }

    } catch let error as CancellationError {

      throw error

    } catch {

      try await noteRemainingLinks(of: device, cache: cache)

      let steps: [String] = known?.profile?.lifecycle?.unlinking.map(LinkingInstructions.steps(of:)) ?? []

      for line in LinkingInstructions.setButtonUnlinking(device: label, steps: steps) {

        Output.note(line)

      }

      throw CommandFailure(description: "\(label) wasn't unlinked without its SET button: \(Names.message(for: error))")

    }

    let product: String? = known?.displayName
    let reports: [RemovedLink] = removed.map { (link: ModemLink) -> RemovedLink in

      RemovedLink(address: "\(device)", group: Int(link.group.rawValue), modemRole: link.modemRole == .controller ? "controller" : "responder", product: product)

    }

    if printsJSON {

      try Output.json(reports)

    } else if reports.isEmpty {

      Output.line("The modem has no links with \(label).")

    } else {

      for report in reports {

        Output.line("Unlinked \(label) from group \(report.group), modem as \(report.modemRole).")

      }

    }

    try await noteRemainingLinks(of: device, cache: cache)

  }

  /// The modem's group to unlink in: the one given, or else the group of the modem's
  /// records for the device in the modem's role, or group 0.
  ///
  /// Links made before group 0 was the default are in group 1, so the device's own records
  /// say which group its link is in.
  private static func unlinkGroup(_ cache: AllLinkDatabaseCache, options: UnlinkOptions) async throws -> AllLinkGroupNumber {

    if let group = options.group {

      return group

    }

    guard let device = options.device else {

      return LinkOptions.defaultGroup

    }

    Output.note("Reading the modem's ALL-Link database for \(device)'s groups...")

    let records: [AllLinkRecord] = try await cache.modemLinks(of: device)
    let isController: Bool = options.role != .responder
    let matching: [AllLinkRecord] = records.filter { (record: AllLinkRecord) -> Bool in

      record.flags.contains(.controller) == isController

    }

    let groups: [UInt8] = Array(Set(matching.map(\.group.rawValue))).sorted()

    guard let first = groups.first else {

      Output.note("The modem has no record for \(device) in that role, so the unlink uses group \(LinkOptions.defaultGroup).")

      return LinkOptions.defaultGroup

    }

    let group = AllLinkGroupNumber(rawValue: first)

    Output.note("The modem's records link \(device) in group \(group), so the unlink uses it.")

    return group

  }

  /// Says which of the modem's groups still link a device, with the command that unlinks
  /// each.
  ///
  /// The modem's database is read again for this, so a failure to read it is only noted.
  private static func noteRemainingLinks(of device: InsteonAddress, cache: AllLinkDatabaseCache) async throws {

    let records: [AllLinkRecord]

    do {

      records = try await cache.modemLinks(of: device)

    } catch let error as CancellationError {

      throw error

    } catch {

      Output.note("Couldn't check the modem for \(device)'s other links: \(Names.message(for: error))")

      return

    }

    var noted: Set<String> = []

    for record in records {

      let roleOption: String = record.flags.contains(.controller) ? "" : " --responder"
      let line: String =
        "\(device) still has links in group \(record.group); run 'insteon unlink \(device) --group \(record.group)\(roleOption)'."

      if noted.insert(line).inserted {

        Output.note(line)

      }

    }

  }

  static func cancelLinking(_ modem: Modem) async throws {

    try await modem.send(.cancelAllLinking)

    Output.line("The modem has left linking mode.")

  }

  // MARK: - Helpers

  /// Tells the person to put the device into a mode first, since it's the controller, and
  /// waits for Return when standard input is a terminal, before the modem joins.
  private static func deviceGoesFirst(_ mode: LinkingInstructions.Mode, device: String?, steps: [String]) async throws {

    let waits = Terminal.readsFromTerminal

    for line in LinkingInstructions.deviceFirst(mode, device: device, steps: steps, waitsForReturn: waits) {

      Output.note(line)

    }

    if waits {

      try await Terminal.waitForReturn()

    }

  }

  /// A callback for when the modem is ready that tells the person what to do.
  private static func notes(_ lines: [String]) -> @Sendable () async -> Void {

    { () async -> Void in

      for line in lines {

        Output.note(line)

      }

    }

  }

  /// Whether the catalog says a device can be a controller, as the product or in one of its
  /// groups, so the modem can respond to it. `false` when the catalog doesn't have the device.
  private static func canControl(_ known: DeviceDescription?) -> Bool {

    guard let known else {

      return false

    }

    let productControls: Bool = known.profile?.role?.includesController ?? false

    return productControls || !known.controllerGroups.isEmpty

  }

  /// A device's address, with its product's name and model when it's known.
  private static func deviceLabel(_ device: InsteonAddress, known: DeviceDescription?) -> String {

    LinkingInstructions.deviceLabel(device, profile: known?.profile)

  }

  /// Prints a new link, with the device's identity when it's known. Pass `nil` for `known` to
  /// print the link alone.
  private static func report(_ link: AllLinkingCompleted, known: DeviceDescription?, names: ProductNames) {

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

  private static func json(for link: AllLinkingCompleted, known: DeviceDescription?) -> Link {

    Link(
      address: "\(link.address)",
      group: Int(link.group.rawValue),
      modemRole: Names.mode(link.mode),
      category: known.map { "\($0.category)" },
      subcategory: known.map { "\($0.subcategory)" },
      firmwareVersion: known?.firmwareVersion.map { "\($0)" },
      product: known?.displayName
    )

  }

  /// A duration in whole seconds.
  private static func seconds(_ duration: Duration) -> Int64 {

    duration.components.seconds

  }

}
