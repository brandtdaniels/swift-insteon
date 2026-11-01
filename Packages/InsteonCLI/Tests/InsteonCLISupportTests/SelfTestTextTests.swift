import Foundation
import Testing
import InsteonCLISupport
import InsteonCore
import InsteonLinking
import InsteonProtocol

struct SelfTestTextTests {

  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)

  let gone = InsteonAddress(0x0E, 0x0E, 0x0E)

  /// A report with a check of each outcome.
  var report: SelfTestReport {

    SelfTestReport(
      device: lamp,
      checks: [
        SelfTestCheck(kind: .answers, outcome: .passed, detail: "The device answered and accepts the modem."),
        SelfTestCheck(kind: .status, outcome: .skipped, detail: "Not read."),
        SelfTestCheck(kind: .modemLinks, outcome: .failed, detail: "A link is missing a record.", fixes: [.link(modemRole: nil, group: nil), .checkSignal]),
        SelfTestCheck(kind: .leftoverRecords, outcome: .warning, detail: "A record names a device that's gone.", fixes: [.reviewRecords([gone])])
      ],
      checklist: [.pressButton(group: 1), .powerCycle]
    )

  }

  @Test func listsEachCheckWithItsOutcomeAndFixes() {

    let lines: [String] = SelfTestText.checkLines(report)

    #expect(lines.count == 7)
    #expect(lines[0].hasPrefix("PASS  Answers the modem "))
    #expect(lines[1].hasPrefix("SKIP  Reports its state "))
    #expect(lines[2].hasPrefix("FAIL  Links with the modem "))
    #expect(lines[3] == "      - Link the device to the modem: 'insteon link 1A.2B.3C'.")
    #expect(lines[4].hasPrefix("      - Check the signal"))
    #expect(lines[5].hasPrefix("WARN  Leftover records "))
    #expect(lines[6].contains("0E.0E.0E"))
    #expect(lines[6].contains("'insteon device 1A.2B.3C links'"))

  }

  @Test func sumsUpTheTest() {

    #expect(SelfTestText.summary(report) == "1 check failed, with 1 warning.")
    #expect(SelfTestText.summary(SelfTestReport(device: lamp, checks: [])) == "Every check passed or was skipped.")

    let warned = SelfTestReport(device: lamp, checks: [SelfTestCheck(kind: .catalog, outcome: .warning, detail: "")])

    #expect(SelfTestText.summary(warned) == "Every check passed or was skipped, with 1 warning.")

  }

  @Test func listsTheChecklistOnceNumbered() {

    let lines: [String] = SelfTestText.checklistLines(report)

    #expect(lines.count == 3)
    #expect(lines[0] == "Checks only a person can do, if you want to:")
    #expect(lines[1].hasPrefix("  1. With 'insteon watch' running, press the device's button for group 1"))
    #expect(lines[2].hasPrefix("  2. Unplug the device"))
    #expect(SelfTestText.checklistLines(SelfTestReport(device: lamp, checks: [])).isEmpty)

  }

  @Test func suggestsTurningTheProgrammingLockOffWithSet() {

    #expect(
      SelfTestText.fix(.turnOffProgrammingLock, device: lamp)
        == "Turn the programming lock off: 'insteon device 1A.2B.3C set programmingLock off'."
    )

  }

  @Test func suggestsTheLinkCommandForTheRoleAndGroup() {

    #expect(SelfTestText.linkCommand(lamp, modemRole: nil, group: nil) == "insteon link 1A.2B.3C")
    #expect(SelfTestText.linkCommand(lamp, modemRole: .controller, group: 0) == "insteon link 1A.2B.3C")
    #expect(SelfTestText.linkCommand(lamp, modemRole: .controller, group: 3) == "insteon link 1A.2B.3C --group 3")
    #expect(SelfTestText.linkCommand(lamp, modemRole: .responder, group: 1) == "insteon link 1A.2B.3C --responder")

    // Each command parses as the link it names.
    #expect(throws: Never.self) {

      _ = try Invocation.parse(["link", "1A.2B.3C", "--group", "3"])
      _ = try Invocation.parse(["link", "1A.2B.3C", "--responder"])

    }

  }

  @Test func printsJSONWithEveryCheckTheIdentityAndTheChecklist() throws {

    var described: SelfTestReport = report
    described.engine = .i2cs
    described.identity = ReportedIdentity(category: 0x02, subcategory: 0x2A, firmwareVersion: 0x45)
    described.productName = "Example Plug"

    let data: Data = try JSONEncoder().encode(SelfTestText.JSON(described))
    let parsed: Any = try JSONSerialization.jsonObject(with: data)
    let object: [String: Any] = try #require(parsed as? [String: Any])
    let checks: [[String: Any]] = try #require(object["checks"] as? [[String: Any]])
    let checklist: [[String: Any]] = try #require(object["checklist"] as? [[String: Any]])
    let linkFixes: [[String: Any]] = try #require(checks[2]["fixes"] as? [[String: Any]])
    let reviewFixes: [[String: Any]] = try #require(checks[3]["fixes"] as? [[String: Any]])

    #expect(object.keys.sorted() == ["address", "category", "checklist", "checks", "engine", "firmwareVersion", "outcome", "product", "subcategory"])
    #expect(object["address"] as? String == "1A.2B.3C")
    #expect(object["engine"] as? String == "i2CS")
    #expect(object["product"] as? String == "Example Plug")
    #expect(object["outcome"] as? String == "failed")
    #expect(checks.map { (check: [String: Any]) -> String? in check["id"] as? String } == ["answers", "status", "modemLinks", "leftoverRecords"])
    #expect(checks[0].keys.sorted() == ["detail", "fixes", "id", "outcome", "title"])
    #expect(checks[0]["outcome"] as? String == "passed")
    #expect((checks[0]["fixes"] as? [Any])?.isEmpty == true)
    #expect(linkFixes.map { (fix: [String: Any]) -> String? in fix["id"] as? String } == ["link", "checkSignal"])
    #expect(linkFixes[0]["text"] as? String == "Link the device to the modem: 'insteon link 1A.2B.3C'.")
    #expect(reviewFixes.first?["id"] as? String == "reviewRecords")
    #expect(reviewFixes.first?["addresses"] as? [String] == ["0E.0E.0E"])
    #expect(checklist.map { (item: [String: Any]) -> String? in item["id"] as? String } == ["pressButton", "powerCycle"])
    #expect(checklist.first?["group"] as? Int == 1)
    #expect(checklist.last?["group"] == nil)

  }

  @Test func printsTheLinkFixWithItsRoleAndGroup() throws {

    let linking = SelfTestReport(
      device: lamp,
      checks: [SelfTestCheck(kind: .modemLinks, outcome: .failed, detail: "", fixes: [.link(modemRole: .controller, group: 3)])]
    )

    let data: Data = try JSONEncoder().encode(SelfTestText.JSON(linking))
    let parsed: Any = try JSONSerialization.jsonObject(with: data)
    let object: [String: Any] = try #require(parsed as? [String: Any])
    let checks: [[String: Any]] = try #require(object["checks"] as? [[String: Any]])
    let fixes: [[String: Any]] = try #require(checks.first?["fixes"] as? [[String: Any]])

    #expect(object["engine"] as? String == "unknown")
    #expect(object["category"] == nil)
    #expect(fixes.first?["modemRole"] as? String == "controller")
    #expect(fixes.first?["group"] as? Int == 3)
    #expect(fixes.first?["text"] as? String == "Link the device to the modem: 'insteon link 1A.2B.3C --group 3'.")

  }

}
