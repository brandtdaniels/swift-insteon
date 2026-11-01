import Foundation
import InsteonCore

/// What `insteon link --database` and `insteon unlink --database` print: the plan, the
/// question before writing, and what became of each write.
public enum DatabaseLinkText {

  // MARK: - The plan

  /// The plan, a line each: what it does, each write in order, the links already in place,
  /// and the device's records that name a device the modem doesn't know.
  ///
  /// - Parameter plan: The plan.
  /// - Returns: The lines.
  public static func plan(_ plan: DatabaseLinkPlan) -> [String] {

    let device: String = label(plan)
    var lines: [String] = []

    if plan.isEmpty {

      switch plan.direction {
      case .link:
        lines.append("\(device) and the modem hold every record of the links the Insteon device catalog gives. Nothing to write.")
      case .unlink:
        lines.append("Neither \(device) nor the modem holds a record of a link with the other. Nothing to write.")
      }

    } else {

      let count: Int = plan.steps.count
      let verb: String = plan.direction == .link ? "Linking" : "Unlinking"

      lines.append("\(verb) \(device) by writing ALL-Link records directly, \(count) \(count == 1 ? "write" : "writes"):")

      for (index, step) in plan.steps.enumerated() {

        lines.append("  \(index + 1). \(Self.step(step))")

      }

    }

    if !plan.linksInPlace.isEmpty {

      lines.append("Already in place:")

      for record in plan.linksInPlace {

        lines.append("  \(Self.owner(of: record)) \(Self.record(record)).")

      }

    }

    if !plan.orphans.isEmpty {

      lines.append(plan.removesOrphans
        ? "The device's records that name a device the modem has no record of, removed first. Such a record can be a working link with another device that was never linked to the modem, such as a 3-way switch or a keypad button; clearing it breaks that link:"
        : "The device's records that name a device the modem has no record of, left as they are. Such a record can be a working link with another device that was never linked to the modem, such as a 3-way switch or a keypad button; pass --orphans to clear them anyway:")

      for record in plan.orphans {

        lines.append("  \(Self.record(record)).")

      }

    }

    if plan.rejectsModemOnceUnlinked {

      lines.append("Once its last record of the modem is removed, the device rejects the modem until it's linked again, so that write can't be read back.")

    }

    return lines

  }

  /// One write, in words.
  ///
  /// - Parameter step: The write.
  /// - Returns: Such as `"Write the device's responder record for group 0 at 0x0FF7: 11.22.33, data FF 1C 01."`.
  public static func step(_ step: DatabaseLinkStep) -> String {

    let record: LinkRecord = step.record
    let address: String = record.memoryAddress.map(Hex.address) ?? ""

    switch step.kind {
    case .addDeviceRecord:
      return "Write the device's \(role(record)) record for group \(record.group.rawValue) at \(address): \(record.address), data \(Hex.pairs(record.data))."
    case .markEndOfDatabase:
      return "Mark the end of the device's database at \(address), so it keeps an end."
    case .removeDeviceRecord:
      return "Clear the device's \(role(record)) record for group \(record.group.rawValue) at \(address), naming \(record.address)."
    case .removeOrphanRecord:
      return "Clear the device's \(role(record)) record for group \(record.group.rawValue) at \(address), naming \(record.address), a device the modem has no record of."
    case .addModemRecord:
      return "Add the modem's \(role(record)) record for group \(record.group.rawValue), naming the device."
    case .removeModemRecord:
      return "Delete the modem's \(role(record)) record for group \(record.group.rawValue), naming the device."
    }

  }

  /// The question asked before writing.
  ///
  /// - Parameter plan: The plan.
  /// - Returns: The question, ending with `[y/N]`.
  public static func question(_ plan: DatabaseLinkPlan) -> String {

    let count: Int = plan.steps.count

    return "Make \(count == 1 ? "this write" : "these \(count) writes") to the ALL-Link databases of \(label(plan)) and the modem? [y/N]"

  }

  /// What's printed when the person doesn't confirm.
  public static let declined: String = "Nothing was written."

  /// What's printed after a dry run's plan.
  public static let dryRun: String = "Dry run: nothing was written."

  // MARK: - The result

  /// What became of the writes, a line each for those that didn't go as planned, and for each
  /// record that didn't read back as expected.
  ///
  /// - Parameter result: The result.
  /// - Returns: The lines.
  public static func result(_ result: DatabaseLinkResult) -> [String] {

    var lines: [String] = []
    let done: Int = result.steps.filter(\.outcome.isDone).count
    let readBack: Int = result.steps.filter { (step: DatabaseLinkResult.StepResult) -> Bool in step.outcome == .written || step.outcome == .writtenOnRetry }.count
    let total: Int = result.steps.count

    lines.append("Made \(done) of \(total) \(total == 1 ? "write" : "writes"); \(readBack) read back as written.")

    // When something didn't go as planned, every write is listed, so it's clear which records
    // were written; otherwise only those that need a word.
    for (index, stepResult) in result.steps.enumerated() where !result.isComplete || stepResult.outcome != .written {

      lines.append("  \(index + 1). \(outcome(stepResult.outcome))")

    }

    for mismatch in result.mismatches {

      lines.append("  \(Self.mismatch(mismatch))")

    }

    switch result.deviceCheck {
    case .checked:
      break
    case .rejectsModemAfterUnlinking:
      lines.append("The device rejects the modem without a record of it, as an i2CS device does, so its database wasn't read again.")
    case .unanswered:
      lines.append("The device didn't answer when its database was read again, so it wasn't checked.")
    }

    lines.append(result.isComplete
      ? (result.plan.direction == .link ? "Linked." : "Unlinked.")
      : "Not every write went as planned; read the databases with 'insteon device \(result.plan.device) links' and 'insteon links'.")

    return lines

  }

  /// A step's outcome, in words.
  ///
  /// - Parameter outcome: The outcome.
  /// - Returns: The sentence.
  public static func outcome(_ outcome: DatabaseLinkStepOutcome) -> String {

    switch outcome {
    case .written:
      "Written."
    case .writtenOnRetry:
      "Read back differently once, written again, then read back as written."
    case .notWritten:
      "Read back differently after it was written twice; the writes after it weren't made."
    case .unanswered:
      "The device or the modem didn't answer, so it isn't known whether it was written; the writes after it weren't made."
    case .rejected:
      "Rejected each time it was sent, as a modem whose database is full rejects an add; the writes after it weren't made."
    case .unverifiable:
      "Written; the device rejects the modem from then on, as an i2CS device unlinked from it does, so it wasn't read back."
    case .notReached:
      "Not made."
    }

  }

  /// A record that didn't read back as expected, in words.
  ///
  /// - Parameter mismatch: The mismatch.
  /// - Returns: The sentence.
  public static func mismatch(_ mismatch: DatabaseMismatch) -> String {

    let whose: String = mismatch.isDevice ? "The device's record" : "The modem's record"
    let place: String = mismatch.memoryAddress.map { (address: UInt16) -> String in " at \(Hex.address(address))" } ?? ""
    let expected: String = mismatch.expected.map { (record: LinkRecord) -> String in Self.record(record) } ?? "none"
    let found: String = mismatch.found.map { (record: LinkRecord) -> String in Self.record(record) } ?? "none"

    return "\(whose)\(place) isn't as expected: expected \(expected), found \(found)."

  }

  // MARK: - Words

  private static func label(_ plan: DatabaseLinkPlan) -> String {

    if let name = plan.info?.displayName {

      return "\(plan.device) (\(name))"

    }

    return "\(plan.device)"

  }

  private static func role(_ record: LinkRecord) -> String {

    record.isController ? "controller" : "responder"

  }

  private static func owner(of record: LinkRecord) -> String {

    record.memoryAddress == nil ? "The modem's" : "The device's"

  }

  /// A record: its role, group, the device it names, its data and where it is.
  static func record(_ record: LinkRecord) -> String {

    if record.isEndOfDatabase {

      return "the record that marks the end of the database" + (record.memoryAddress.map { (address: UInt16) -> String in " at \(Hex.address(address))" } ?? "")

    }

    let place: String = record.memoryAddress.map { (address: UInt16) -> String in " at \(Hex.address(address))" } ?? ""
    let use: String = record.isInUse ? "" : ", not in use"

    return "\(role(record)) record for group \(record.group.rawValue)\(place) naming \(record.address), data \(Hex.pairs(record.data))\(use)"

  }

  // MARK: - JSON

  /// A write, as `--json` prints it.
  public struct Step: Encodable, Hashable, Sendable {

    /// What the write does, such as `"addDeviceRecord"`.
    public var kind: String

    /// The record as the write leaves it.
    public var record: Record

    /// What became of it, or `nil` in a plan.
    public var outcome: String?

  }

  /// A record, as `--json` prints it.
  public struct Record: Encodable, Hashable, Sendable {

    /// Whose database holds it: `"device"` or `"modem"`.
    public var holder: String

    /// Where it is in the device's database, such as `"0x0FF7"`, or `nil` for the modem's.
    public var recordAddress: String?

    /// `"controller"` or `"responder"`.
    public var role: String

    /// The group.
    public var group: UInt8

    /// The device the record names.
    public var address: String

    /// Data 1 through Data 3, such as `"FF 1C 01"`.
    public var data: String

    /// Whether the record holds a link.
    public var inUse: Bool

    /// Whether the record marks the end of the device's database.
    public var endOfDatabase: Bool

  }

  /// A record not as expected, as `--json` prints it.
  public struct Mismatch: Encodable, Hashable, Sendable {

    /// The record expected, or `nil`.
    public var expected: Record?

    /// The record found, or `nil`.
    public var found: Record?

  }

  /// A plan, and what became of it once carried out, as `--json` prints them.
  public struct Report: Encodable, Hashable, Sendable {

    /// `"link"` or `"unlink"`.
    public var direction: String

    /// The device's address.
    public var device: String

    /// The modem's address.
    public var modem: String

    /// The device's engine, such as `"i2CS"`.
    public var engine: String

    /// The product's name, when the catalog describes the device.
    public var product: String?

    /// Whether the plan was only shown, as `--dry-run` asks.
    public var dryRun: Bool

    /// The writes, in order, with their outcomes once carried out.
    public var steps: [Step]

    /// The records of the links already in place.
    public var inPlace: [Record]

    /// The device's records that name a device the modem doesn't know.
    public var orphans: [Record]

    /// The records not as expected afterward, or `nil` when the plan wasn't carried out.
    public var mismatches: [Mismatch]?

    /// What reading the device's database again found: `"checked"`,
    /// `"rejectsModemAfterUnlinking"` or `"unanswered"`, or `nil` when the plan wasn't
    /// carried out.
    public var deviceCheck: String?

    /// Whether every write was made and read back as expected, or `nil` when the plan wasn't
    /// carried out.
    public var complete: Bool?

  }

  /// A plan as `--json` prints it, before or without carrying it out.
  ///
  /// - Parameters:
  ///   - plan: The plan.
  ///   - isDryRun: Whether it was only shown.
  /// - Returns: The report.
  public static func report(_ plan: DatabaseLinkPlan, isDryRun: Bool) -> Report {

    Report(
      direction: plan.direction.rawValue,
      device: "\(plan.device)",
      modem: "\(plan.modem)",
      engine: plan.engine.name,
      product: plan.info?.displayName,
      dryRun: isDryRun,
      steps: plan.steps.map { (step: DatabaseLinkStep) -> Step in Step(kind: step.kind.rawValue, record: json(step.record, isDevice: step.isDeviceStep), outcome: nil) },
      inPlace: plan.linksInPlace.map { (record: LinkRecord) -> Record in json(record, isDevice: record.memoryAddress != nil) },
      orphans: plan.orphans.map { (record: LinkRecord) -> Record in json(record, isDevice: true) },
      mismatches: nil,
      deviceCheck: nil,
      complete: nil
    )

  }

  /// A plan carried out, as `--json` prints it.
  ///
  /// - Parameter result: The result.
  /// - Returns: The report.
  public static func report(_ result: DatabaseLinkResult) -> Report {

    var report: Report = report(result.plan, isDryRun: false)

    report.steps = result.steps.map { (stepResult: DatabaseLinkResult.StepResult) -> Step in

      Step(kind: stepResult.step.kind.rawValue, record: json(stepResult.step.record, isDevice: stepResult.step.isDeviceStep), outcome: stepResult.outcome.rawValue)

    }
    report.mismatches = result.mismatches.map { (mismatch: DatabaseMismatch) -> Mismatch in

      Mismatch(
        expected: mismatch.expected.map { (record: LinkRecord) -> Record in json(record, isDevice: mismatch.isDevice) },
        found: mismatch.found.map { (record: LinkRecord) -> Record in json(record, isDevice: mismatch.isDevice) }
      )

    }
    report.deviceCheck = result.deviceCheck.rawValue
    report.complete = result.isComplete

    return report

  }

  private static func json(_ record: LinkRecord, isDevice: Bool) -> Record {

    Record(
      holder: isDevice ? "device" : "modem",
      recordAddress: record.memoryAddress.map(Hex.address),
      role: role(record),
      group: record.group.rawValue,
      address: "\(record.address)",
      data: Hex.pairs(record.data),
      inUse: record.isInUse,
      endOfDatabase: record.isEndOfDatabase
    )

  }

}
