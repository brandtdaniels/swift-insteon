import InsteonDeviceCatalog
import InsteonLinking
import InsteonModem
import InsteonProtocol

// Checking that a device is healthy and set up as the catalog expects.
extension Device {

  /// Checks that the device answers, that the Insteon device catalog describes it, that its
  /// ALL-Link database reads intact, that it and the modem hold both records of each link
  /// between them, that its records name only the modem and devices the modem knows, and that
  /// no operating flag locks it or cuts it off.
  ///
  /// The test only reads: it sends Get Insteon Engine Version, ID Request, the catalog's
  /// status request, the requests that read the device's ALL-Link database and its operating
  /// flags, and reads the modem's own database. It writes no record and no setting. With
  /// ``SelfTestOptions/actuates``, it also sends Beep when the catalog lists a Beep that's
  /// sent to the device, and nothing to a device the catalog doesn't describe.
  ///
  /// A device that doesn't answer, or rejects the modem, fails the first check, and the checks
  /// that need it to answer are skipped. A check the device doesn't answer fails or warns with
  /// what may put it right; it doesn't stop the test.
  ///
  /// ```swift
  /// let report = try await network.device(lamp).selfTest()
  ///
  /// for check in report.checks where check.outcome != .passed {
  ///   print(check.title, check.detail)
  /// }
  /// ```
  ///
  /// - Parameter options: What the test does beyond reading. Defaults to reading only.
  /// - Returns: Each check's outcome, and what only a person can check.
  /// - Throws: `CancellationError` if the task is canceled, and the errors of the modem and
  ///   the connection to it, such as `ModemError.connectionClosed`; never the device's own
  ///   timeouts or rejections, which the checks report.
  public func selfTest(_ options: SelfTestOptions = SelfTestOptions()) async throws -> SelfTestReport {

    var report = SelfTestReport(device: address, checks: [])
    let identification: DeviceIdentification

    // MARK: Answers

    do {

      identification = try await network.identify(address)

    } catch {

      let problem: SelfTestProblem = try SelfTestProblem(error)

      report.checks.append(SelfTestCheck(
        kind: .answers,
        outcome: .failed,
        detail: problem.isTimeout
          ? "The device didn't answer Get Insteon Engine Version."
          : "The device rejected Get Insteon Engine Version.",
        fixes: problem.isTimeout ? [.checkSignal, .link, .factoryReset] : [.link, .factoryReset]
      ))
      report.checks += Self.skipped(after: .answers, options: options, because: "The device didn't answer, so this wasn't checked.")
      report.checklist = [.powerCycle]

      return report

    }

    report.engine = identification.engine
    report.identity = identification.identity.map { (pressed: SetButtonPressed) -> ReportedIdentity in ReportedIdentity(pressed) }

    guard identification.acceptsModem else {

      report.checks.append(SelfTestCheck(
        kind: .answers,
        outcome: .failed,
        detail: "The device answered, but rejects the modem: it runs i2CS and isn't linked to it.",
        fixes: [.link]
      ))
      report.checks += Self.skipped(after: .answers, options: options, because: "The device rejects the modem until it's linked, so this wasn't checked.")

      return report

    }

    report.checks.append(SelfTestCheck(kind: .answers, outcome: .passed, detail: "The device answered and accepts the modem."))

    // MARK: Catalog

    let description: DeviceDescription? = await network.registry.device(address)?.deviceDescription
    let info: DeviceInfo? = description.map(DeviceInfo.init)

    report.productName = info?.displayName
    report.checks.append(Self.catalogCheck(identity: report.identity, info: info))

    // MARK: Status

    do {

      report.status = try await status()
      report.checks.append(SelfTestCheck(kind: .status, outcome: .passed, detail: "The device reported its state."))

    } catch is DeviceControlError {

      report.checks.append(SelfTestCheck(kind: .status, outcome: .skipped, detail: "The Insteon device catalog gives no way to read the device's state."))

    } catch {

      try report.checks.append(Self.unanswered(.status, error, outcome: .warning, what: "a status request"))

    }

    // MARK: ALL-Link database

    var database: LinkDatabase?

    do {

      database = try await network.allLinkDatabase(of: address)

    } catch {

      try report.checks.append(Self.unanswered(.linkDatabase, error, outcome: .failed, what: "the requests that read its ALL-Link database"))

    }

    if let database {

      report.checks.append(Self.databaseCheck(database))

    }

    // MARK: Links with the modem

    let modemAddress: InsteonAddress = try await network.modemInfo().address
    let modemRecords: [LinkRecord] = try await network.modemDatabase().map(\.record).filter(\.isInUse)
    let deviceRecords: [LinkRecord]? = database?.records.filter { (record: LinkRecord) -> Bool in record.isInUse && record.hasIntactChecksum }
    let legs: [HubLinkingLeg]? = HubLinkingLeg.legs(of: description, device: address)

    if let deviceRecords {

      report.checks.append(Self.linksCheck(
        device: address,
        modem: modemAddress,
        deviceRecords: deviceRecords,
        modemRecords: modemRecords,
        legs: legs
      ))
      report.checks.append(Self.leftoversCheck(modem: modemAddress, deviceRecords: deviceRecords, modemRecords: modemRecords))

    } else {

      for kind in [SelfTestCheckKind.modemLinks, .leftoverRecords] {

        report.checks.append(SelfTestCheck(kind: kind, outcome: .skipped, detail: "The device's ALL-Link database couldn't be read, so this wasn't checked."))

      }

    }

    // MARK: Operating flags

    let flags: SelfTestCheck = try await flagsCheck(description: description)

    report.checks.append(flags)

    // MARK: Beep

    if options.actuates {

      let beeped: SelfTestCheck = try await beepCheck(description: description)

      report.checks.append(beeped)

    }

    report.checklist = Self.checklist(modem: modemAddress, deviceRecords: deviceRecords ?? [], legs: legs)

    return report

  }

  // MARK: - Checks

  /// The checks after `kind`, skipped for a reason.
  static func skipped(after kind: SelfTestCheckKind, options: SelfTestOptions, because detail: String) -> [SelfTestCheck] {

    let all: [SelfTestCheckKind] = SelfTestCheckKind.allCases.filter { (kind: SelfTestCheckKind) -> Bool in options.actuates || kind != .beep }
    let later: ArraySlice<SelfTestCheckKind> = all.drop { (each: SelfTestCheckKind) -> Bool in each != kind }.dropFirst()

    return later.map { (each: SelfTestCheckKind) -> SelfTestCheck in SelfTestCheck(kind: each, outcome: .skipped, detail: detail) }

  }

  /// A check the device didn't answer or rejected, or the error rethrown when it's the modem's
  /// or the connection's.
  static func unanswered(_ kind: SelfTestCheckKind, _ error: any Error, outcome: SelfTestOutcome, what: String) throws -> SelfTestCheck {

    let problem: SelfTestProblem = try SelfTestProblem(error)

    if problem.isTimeout {

      return SelfTestCheck(kind: kind, outcome: outcome, detail: "The device didn't answer \(what).", fixes: [.readAgain, .checkSignal])

    }

    return SelfTestCheck(kind: kind, outcome: outcome, detail: "The device rejected \(what).", fixes: [.link])

  }

  /// Whether the catalog describes the identity the device reported.
  static func catalogCheck(identity: ReportedIdentity?, info: DeviceInfo?) -> SelfTestCheck {

    if let info, info.isInCatalog {

      return SelfTestCheck(kind: .catalog, outcome: .passed, detail: "The Insteon device catalog describes the device as \(info.displayName ?? "a product it lists").")

    }

    guard identity != nil else {

      return SelfTestCheck(
        kind: .catalog,
        outcome: .warning,
        detail: "The device didn't report its identity to ID Request, so the checks that need the Insteon device catalog are skipped.",
        fixes: [.readAgain, .checkSignal]
      )

    }

    return SelfTestCheck(
      kind: .catalog,
      outcome: .warning,
      detail: "The Insteon device catalog doesn't describe the identity the device reported, so the checks that need it are skipped.",
      fixes: [.updateCatalog]
    )

  }

  /// Whether a database read intact.
  static func databaseCheck(_ database: LinkDatabase) -> SelfTestCheck {

    let damaged: Int = database.records.filter { (record: LinkRecord) -> Bool in !record.hasIntactChecksum }.count

    if damaged > 0 {

      return SelfTestCheck(
        kind: .linkDatabase,
        outcome: .failed,
        detail: "\(damaged) of the database's records failed their checksum, so what they hold can't be trusted.",
        fixes: [.readAgain, .checkSignal]
      )

    }

    guard database.records.contains(where: \.isEndOfDatabase) else {

      return SelfTestCheck(
        kind: .linkDatabase,
        outcome: .warning,
        detail: "The database ended without the record that marks its end.",
        fixes: [.readAgain]
      )

    }

    let inUse: Int = database.records.filter(\.isInUse).count

    return SelfTestCheck(kind: .linkDatabase, outcome: .passed, detail: "\(inUse) \(inUse == 1 ? "record" : "records") in use, each with its checksum intact.")

  }

  /// One record a link needs.
  struct ExpectedRecord: Hashable {

    /// Whether the modem holds it, rather than the device.
    var isModems: Bool

    /// Whether it's a controller record.
    var isController: Bool

    /// The group it holds.
    var group: AllLinkGroupNumber

    /// Whether `records` holds it, naming `other`.
    func isIn(_ records: [LinkRecord], naming other: InsteonAddress) -> Bool {

      records.contains { (record: LinkRecord) -> Bool in

        record.isController == isController && record.group == group && record.address == other

      }

    }

    /// The record, in words.
    var text: String {

      "the \(isModems ? "modem's" : "device's") \(isController ? "controller" : "responder") record for group \(group.rawValue)"

    }

  }

  /// The two records of a link between the modem and the device.
  static func records(modemRole: ModemRole, modemGroup: AllLinkGroupNumber, deviceGroup: AllLinkGroupNumber) -> [ExpectedRecord] {

    switch modemRole {
    case .controller:
      // A responder's record holds its controller's group.
      [
        ExpectedRecord(isModems: true, isController: true, group: modemGroup),
        ExpectedRecord(isModems: false, isController: false, group: modemGroup)
      ]
    case .responder:
      [
        ExpectedRecord(isModems: false, isController: true, group: deviceGroup),
        ExpectedRecord(isModems: true, isController: false, group: modemGroup)
      ]
    }

  }

  /// Whether the device and the modem hold both records of each link between them: each of
  /// the catalog's legs, or, without them, the links their records show.
  static func linksCheck(
    device: InsteonAddress,
    modem: InsteonAddress,
    deviceRecords: [LinkRecord],
    modemRecords: [LinkRecord],
    legs: [HubLinkingLeg]?
  ) -> SelfTestCheck {

    var links: [[ExpectedRecord]] = []

    if let legs {

      links = legs.map { (leg: HubLinkingLeg) -> [ExpectedRecord] in

        records(modemRole: leg.modemRole, modemGroup: leg.modemGroup, deviceGroup: leg.deviceGroup)

      }

    } else {

      // Without the catalog's legs, each group either side has a record for is a link,
      // with the modem controlling the device at least.
      var modemControls: Set<AllLinkGroupNumber> = []
      var deviceControls: Set<AllLinkGroupNumber> = []

      for record in modemRecords where record.address == device {

        if record.isController {

          modemControls.insert(record.group)

        } else {

          deviceControls.insert(record.group)

        }

      }

      for record in deviceRecords where record.address == modem {

        if record.isController {

          deviceControls.insert(record.group)

        } else {

          modemControls.insert(record.group)

        }

      }

      links = modemControls.sorted { (first: AllLinkGroupNumber, second: AllLinkGroupNumber) -> Bool in first.rawValue < second.rawValue }.map { (group: AllLinkGroupNumber) -> [ExpectedRecord] in

        records(modemRole: .controller, modemGroup: group, deviceGroup: group)

      }
      links += deviceControls.sorted { (first: AllLinkGroupNumber, second: AllLinkGroupNumber) -> Bool in first.rawValue < second.rawValue }.map { (group: AllLinkGroupNumber) -> [ExpectedRecord] in

        records(modemRole: .responder, modemGroup: group, deviceGroup: group)

      }

    }

    guard !links.isEmpty else {

      return SelfTestCheck(kind: .modemLinks, outcome: .failed, detail: "Neither the device nor the modem holds a record of a link with the other.", fixes: [.link])

    }

    let missing: [ExpectedRecord] = links.joined().filter { (expected: ExpectedRecord) -> Bool in

      expected.isModems
        ? !expected.isIn(modemRecords, naming: device)
        : !expected.isIn(deviceRecords, naming: modem)

    }

    guard !missing.isEmpty else {

      let count: Int = links.count
      let source: String = legs == nil ? "" : " the Insteon device catalog gives"

      return SelfTestCheck(
        kind: .modemLinks,
        outcome: .passed,
        detail: "The device and the modem hold both records of the \(count == 1 ? "link" : "\(count) links")\(source)."
      )

    }

    let list: String = missing.map(\.text).joined(separator: ", ")
    let isUnlinked: Bool = missing.count == links.count * 2

    return SelfTestCheck(
      kind: .modemLinks,
      outcome: .failed,
      detail: isUnlinked
        ? "The device isn't linked to the modem: neither holds a record the link needs (\(list))."
        : "A link is missing a record, so it works one way only, or not at all: \(list).",
      fixes: [.link, .checkSignal]
    )

  }

  /// Whether every record of the device names the modem or a device the modem holds a
  /// record for.
  static func leftoversCheck(modem: InsteonAddress, deviceRecords: [LinkRecord], modemRecords: [LinkRecord]) -> SelfTestCheck {

    let known: Set<InsteonAddress> = Set(modemRecords.map(\.address)).union([modem])
    var others: [InsteonAddress] = []

    for record in deviceRecords where !known.contains(record.address) && !others.contains(record.address) {

      others.append(record.address)

    }

    guard !others.isEmpty else {

      return SelfTestCheck(kind: .leftoverRecords, outcome: .passed, detail: "Every record names the modem or a device the modem is linked to.")

    }

    let list: String = others.map { (other: InsteonAddress) -> String in "\(other)" }.joined(separator: ", ")

    return SelfTestCheck(
      kind: .leftoverRecords,
      outcome: .warning,
      detail: "Some records name devices the modem isn't linked to, which may be gone: \(list).",
      fixes: [.reviewRecords(others)]
    )

  }

  /// Whether an operating flag locks the device or cuts it off, from its flags the catalog
  /// describes.
  func flagsCheck(description: DeviceDescription?) async throws -> SelfTestCheck {

    guard description?.commandSet?.operatingFlags.isEmpty == false else {

      return SelfTestCheck(kind: .operatingFlags, outcome: .skipped, detail: "The Insteon device catalog describes no operating flags for the device.")

    }

    let reading: DeviceSettingsReading

    do {

      reading = try await readSettings(includingAdvanced: true)

    } catch is DeviceSettingError {

      return SelfTestCheck(kind: .operatingFlags, outcome: .skipped, detail: "The Insteon device catalog describes no settings for the device.")

    } catch {

      return try Self.unanswered(.operatingFlags, error, outcome: .warning, what: "Get Operating Flags")

    }

    return Self.flagsCheck(reading)

  }

  /// Whether a reading shows a flag set that locks the device or cuts it off.
  static func flagsCheck(_ reading: DeviceSettingsReading) -> SelfTestCheck {

    var reported: Int = 0
    var problems: [String] = []
    var fixes: [SelfTestFix] = []

    for item in reading.items {

      guard case let .flag(flag) = item.source, let raw = reading.raw(for: item) else {

        continue

      }

      reported += 1

      guard raw & flag.bit != 0 else {

        continue

      }

      let label: String = flag.label ?? flag.name.rawValue

      if flag.name == DeviceSettingSafety.programmingLock {

        problems.append("\(label) is on, so the device's buttons can't change its links or settings")
        fixes.append(.turnOffProgrammingLock)

      } else if DeviceSettingSafety.neverWritten.contains(flag.name) {

        problems.append("\(label) is on, which cuts the device off from the modem")

        if !fixes.contains(.factoryReset) {

          fixes.append(.factoryReset)

        }

      }

    }

    guard reported > 0 else {

      return SelfTestCheck(kind: .operatingFlags, outcome: .warning, detail: "The device reported none of its operating flags.", fixes: [.readAgain])

    }

    guard problems.isEmpty else {

      return SelfTestCheck(kind: .operatingFlags, outcome: .warning, detail: problems.joined(separator: "; ") + ".", fixes: fixes)

    }

    return SelfTestCheck(
      kind: .operatingFlags,
      outcome: .passed,
      detail: "\(reported) operating \(reported == 1 ? "flag" : "flags") read; none locks the device or cuts it off."
    )

  }

  /// Beep, sent only when the catalog lists a Beep that's sent to the device.
  func beepCheck(description: DeviceDescription?) async throws -> SelfTestCheck {

    guard let commands = description?.commandSet, Self.sendableBeep(in: commands) != nil else {

      return SelfTestCheck(
        kind: .beep,
        outcome: .skipped,
        detail: "The Insteon device catalog doesn't list a Beep that's sent to the device, so nothing was sent."
      )

    }

    do {

      try await beep()

    } catch {

      return try Self.unanswered(.beep, error, outcome: .failed, what: "Beep")

    }

    return SelfTestCheck(kind: .beep, outcome: .passed, detail: "The device acknowledged Beep.")

  }

  /// What only a person can check: pressing a button for each group the device controls the
  /// modem with, and cutting its power.
  static func checklist(modem: InsteonAddress, deviceRecords: [LinkRecord], legs: [HubLinkingLeg]?) -> [SelfTestChecklistItem] {

    var groups: [Int] = []

    if let legs {

      for leg in legs where leg.modemRole == .responder {

        groups.append(Int(leg.deviceGroup.rawValue))

      }

    } else {

      for record in deviceRecords where record.isController && record.address == modem {

        groups.append(Int(record.group.rawValue))

      }

    }

    var items: [SelfTestChecklistItem] = []

    for group in groups where !items.contains(.pressButton(group: group)) {

      items.append(.pressButton(group: group))

    }

    items.append(.powerCycle)

    return items

  }

}

/// What the device did when a check didn't go through.
struct SelfTestProblem {

  /// Whether the device didn't answer, rather than rejecting the request.
  var isTimeout: Bool

  /// The problem, or the error rethrown when it's the modem's or the connection's, or the
  /// task was canceled.
  init(_ error: any Error) throws {

    guard let modemError = error as? ModemError else {

      throw error

    }

    switch modemError {
    case .deviceTimedOut:
      isTimeout = true
    case .deviceRejected:
      isTimeout = false
    default:
      throw error
    }

  }

}
