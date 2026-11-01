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

  /// A fix's stable name, as `--json` prints it.
  ///
  /// - Parameter fix: The fix.
  /// - Returns: Such as `"link"` or `"turnOffProgrammingLock"`.
  public static func id(_ fix: SelfTestFix) -> String {

    switch fix {
    case .checkSignal:
      "checkSignal"
    case .link:
      "link"
    case .readAgain:
      "readAgain"
    case .reviewRecords:
      "reviewRecords"
    case .turnOffProgrammingLock:
      "turnOffProgrammingLock"
    case .updateCatalog:
      "updateCatalog"
    case .factoryReset:
      "factoryReset"
    }

  }

  /// A checklist item's stable name, as `--json` prints it.
  ///
  /// - Parameter item: The item.
  /// - Returns: `"pressButton"` or `"powerCycle"`.
  public static func id(_ item: SelfTestChecklistItem) -> String {

    switch item {
    case .pressButton:
      "pressButton"
    case .powerCycle:
      "powerCycle"
    }

  }

  /// The `insteon link` command that makes a link: as the catalog says without a role or
  /// group, and otherwise with the options for them.
  ///
  /// - Parameters:
  ///   - device: The device.
  ///   - modemRole: The modem's role, or `nil` to link as the catalog says.
  ///   - group: The modem's group, or `nil` for the default.
  /// - Returns: The command.
  public static func linkCommand(_ device: InsteonAddress, modemRole: ModemRole?, group: Int?) -> String {

    switch modemRole {
    case .responder?:
      // With an address, the modem joins the group the device's link back uses.
      "insteon link \(device) --responder"
    case .controller?:
      group.map { (number: Int) -> String in number == 0 ? "insteon link \(device)" : "insteon link \(device) --group \(number)" }
        ?? "insteon link \(device)"
    case nil:
      "insteon link \(device)"
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
    case let .link(modemRole, group):
      "Link the device to the modem: '\(linkCommand(device, modemRole: modemRole, group: group))'."
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

    /// What may put a check right.
    public struct Fix: Encodable, Hashable, Sendable {

      /// The fix's stable name, such as `"link"`.
      public let id: String

      /// What to do, as a sentence.
      public let text: String

      /// For `link`, `"controller"` or `"responder"`, or `nil` to link as the catalog says.
      public let modemRole: String?

      /// For `link`, the modem's group, or `nil` for the default.
      public let group: Int?

      /// For `reviewRecords`, the devices the records name.
      public let addresses: [String]?

    }

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

      /// What may put it right.
      public let fixes: [Fix]

    }

    /// Something only a person can check.
    public struct ChecklistItem: Encodable, Hashable, Sendable {

      /// The item's stable name, `"pressButton"` or `"powerCycle"`.
      public let id: String

      /// For `pressButton`, the group.
      public let group: Int?

      /// What to do, as a sentence.
      public let text: String

    }

    /// The device's address.
    public let address: String

    /// The engine the device reported, or `"unknown"`.
    public let engine: String

    /// The category the device reported, or `nil` if it reported no identity.
    public let category: String?

    /// The subcategory the device reported.
    public let subcategory: String?

    /// The firmware version the device reported.
    public let firmwareVersion: String?

    /// The product the Insteon device catalog has for the device.
    public let product: String?

    /// The test's outcome as a whole.
    public let outcome: String

    /// The checks, in order.
    public let checks: [Check]

    /// What only a person can check.
    public let checklist: [ChecklistItem]

    /// Creates the JSON of a report.
    ///
    /// - Parameter report: The report.
    public init(_ report: SelfTestReport) {

      let device: InsteonAddress = report.device

      address = "\(device)"
      engine = report.engine?.name ?? "unknown"
      category = report.identity.map { (identity: ReportedIdentity) -> String in "\(identity.category)" }
      subcategory = report.identity.map { (identity: ReportedIdentity) -> String in "\(identity.subcategory)" }
      firmwareVersion = report.identity?.firmwareVersion.map { (version: FirmwareVersion) -> String in "\(version)" }
      product = report.productName
      outcome = report.outcome.rawValue
      checks = report.checks.map { (check: SelfTestCheck) -> Check in

        Check(
          id: check.kind.rawValue,
          title: check.title,
          outcome: check.outcome.rawValue,
          detail: check.detail,
          fixes: check.fixes.map { (each: SelfTestFix) -> Fix in Self.fix(each, device: device) }
        )

      }
      checklist = report.checklist.map { (item: SelfTestChecklistItem) -> ChecklistItem in

        var group: Int?

        if case let .pressButton(number) = item {

          group = number

        }

        return ChecklistItem(id: SelfTestText.id(item), group: group, text: SelfTestText.checklistItem(item, device: device))

      }

    }

    /// A fix as JSON.
    private static func fix(_ fix: SelfTestFix, device: InsteonAddress) -> Fix {

      var modemRole: String?
      var group: Int?
      var addresses: [String]?

      switch fix {
      case let .link(role, number):
        modemRole = role.map { (role: ModemRole) -> String in role == .controller ? "controller" : "responder" }
        group = number
      case let .reviewRecords(others):
        addresses = others.map { (other: InsteonAddress) -> String in "\(other)" }
      default:
        break
      }

      return Fix(
        id: SelfTestText.id(fix),
        text: SelfTestText.fix(fix, device: device),
        modemRole: modemRole,
        group: group,
        addresses: addresses
      )

    }

  }

}
