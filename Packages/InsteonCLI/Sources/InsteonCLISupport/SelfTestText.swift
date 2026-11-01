import Foundation
import InsteonCore

/// What `insteon device ADDRESS selftest` prints.
public enum SelfTestText {

  /// The word for an outcome, as each check's line starts.
  ///
  /// - Parameter outcome: The outcome.
  /// - Returns: `"PASS"`, `"WARN"`, `"FAIL"` or `"SKIP"`.
  public static func label(_ outcome: SelfTestOutcome) -> String {

    switch outcome {
    case .passed:
      "PASS"
    case .warning:
      "WARN"
    case .failed:
      "FAIL"
    case .skipped:
      "SKIP"
    }

  }

  /// What to do about a fix, with the command that does it, when there's one.
  ///
  /// - Parameters:
  ///   - fix: The fix.
  ///   - device: The device tested.
  /// - Returns: A sentence.
  public static func fix(_ fix: SelfTestFix, device: InsteonAddress) -> String {

    switch fix {
    case .checkSignal:
      "Check the signal: try another outlet, one on the modem's circuit or nearer to it, away from "
        + "power strips and filtered outlets, and check that the home's two power phases are bridged, "
        + "by a dual-band device on each or a phase coupler."
    case .link:
      "Link the device to the modem: 'insteon link \(device)'."
    case .readAgain:
      "Run the test again: 'insteon device \(device) selftest'."
    case let .reviewRecords(others):
      "Look over the records for \(others.map { (other: InsteonAddress) -> String in "\(other)" }.joined(separator: ", ")) "
        + "with 'insteon device \(device) links'. Records for a device that's gone are cleared when this "
        + "device is reset to its factory settings."
    case .turnOffProgrammingLock:
      "Turn the programming lock off: 'insteon device \(device) set programmingLock off'."
    case .updateCatalog:
      "Download the latest compatible Insteon device catalog: 'insteon catalog update'."
    case .factoryReset:
      "As a last resort, reset the device to its factory settings, as its instructions say, then link it again."
    }

  }

  /// What a person does for a checklist item.
  ///
  /// - Parameters:
  ///   - item: The item.
  ///   - device: The device tested.
  /// - Returns: A sentence.
  public static func checklistItem(_ item: SelfTestChecklistItem, device: InsteonAddress) -> String {

    switch item {
    case let .pressButton(group):
      "With 'insteon watch' running, press the device's button for group \(group), and see that the modem hears it."
    case .powerCycle:
      "Unplug the device, or pull its air gap, for about ten seconds, then restore its power and run "
        + "'insteon device \(device) selftest' again: it should answer, with its links and settings as they were."
    }

  }

  /// The lines that list the checks, each with its outcome, title and finding, and the fixes
  /// of each check that didn't pass.
  ///
  /// - Parameter report: The report.
  /// - Returns: The lines.
  public static func checkLines(_ report: SelfTestReport) -> [String] {

    var lines: [String] = []
    let width: Int = report.checks.map { (check: SelfTestCheck) -> Int in check.title.count }.max() ?? 0

    for check in report.checks {

      let title: String = check.title.padding(toLength: width, withPad: " ", startingAt: 0)

      lines.append("\(label(check.outcome))  \(title)  \(check.detail)")

      for each in check.fixes {

        lines.append("      - \(fix(each, device: report.device))")

      }

    }

    return lines

  }

  /// The line that sums up the test.
  ///
  /// - Parameter report: The report.
  /// - Returns: The line.
  public static func summary(_ report: SelfTestReport) -> String {

    let failed: Int = report.checks.filter { (check: SelfTestCheck) -> Bool in check.outcome == .failed }.count
    let warnings: Int = report.checks.filter { (check: SelfTestCheck) -> Bool in check.outcome == .warning }.count

    switch report.outcome {
    case .failed:
      return "\(Wording.count(failed, "check")) failed"
        + (warnings > 0 ? ", with \(Wording.count(warnings, "warning"))." : ".")
    case .warning:
      return "Every check passed or was skipped, with \(Wording.count(warnings, "warning"))."
    case .passed, .skipped:
      return "Every check passed or was skipped."
    }

  }

  /// The lines of the checklist: a heading and one numbered line for each item.
  ///
  /// - Parameter report: The report.
  /// - Returns: The lines, or none when the checklist is empty.
  public static func checklistLines(_ report: SelfTestReport) -> [String] {

    guard !report.checklist.isEmpty else {

      return []

    }

    var lines: [String] = ["Checks only a person can do, if you want to:"]

    for (index, item) in report.checklist.enumerated() {

      lines.append("  \(index + 1). \(checklistItem(item, device: report.device))")

    }

    return lines

  }

  /// The test as `--json` prints it.
  public struct JSON: Encodable, Hashable, Sendable {

    /// One check.
    public struct Check: Encodable, Hashable, Sendable {

      /// The check's kind, such as `"modemLinks"`.
      public let id: String

      /// What the check is.
      public let title: String

      /// `"passed"`, `"warning"`, `"failed"` or `"skipped"`.
      public let outcome: String

      /// What the check found.
      public let detail: String

      /// What may put it right, as sentences.
      public let fixes: [String]

    }

    /// The device's address.
    public let address: String

    /// The test's outcome as a whole.
    public let outcome: String

    /// The checks, in order.
    public let checks: [Check]

    /// What only a person can check, as sentences.
    public let checklist: [String]

    /// Creates the JSON of a report.
    ///
    /// - Parameter report: The report.
    public init(_ report: SelfTestReport) {

      address = "\(report.device)"
      outcome = report.outcome.rawValue
      checks = report.checks.map { (check: SelfTestCheck) -> Check in

        Check(
          id: check.kind.rawValue,
          title: check.title,
          outcome: check.outcome.rawValue,
          detail: check.detail,
          fixes: check.fixes.map { (each: SelfTestFix) -> String in SelfTestText.fix(each, device: report.device) }
        )

      }
      checklist = report.checklist.map { (item: SelfTestChecklistItem) -> String in SelfTestText.checklistItem(item, device: report.device) }

    }

  }

}
