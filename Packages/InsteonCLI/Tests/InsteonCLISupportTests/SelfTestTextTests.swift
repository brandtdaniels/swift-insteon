import Foundation
import Testing
import InsteonCLISupport
import InsteonCore
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
        SelfTestCheck(kind: .modemLinks, outcome: .failed, detail: "A link is missing a record.", fixes: [.link, .checkSignal]),
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

  @Test func printsJSONWithEveryCheckAndTheChecklist() throws {

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    let data: Data = try encoder.encode(SelfTestText.JSON(report))
    let parsed: Any = try JSONSerialization.jsonObject(with: data)
    let object: [String: Any] = try #require(parsed as? [String: Any])
    let checks: [[String: Any]] = try #require(object["checks"] as? [[String: Any]])
    let first: [String: Any] = try #require(checks.first)
    let links: [String: Any] = checks[2]
    let checklist: [String] = try #require(object["checklist"] as? [String])

    #expect(object.keys.sorted() == ["address", "checklist", "checks", "outcome"])
    #expect(object["address"] as? String == "1A.2B.3C")
    #expect(object["outcome"] as? String == "failed")
    #expect(checks.count == 4)
    #expect(first.keys.sorted() == ["detail", "fixes", "id", "outcome", "title"])
    #expect(first["id"] as? String == "answers")
    #expect(first["outcome"] as? String == "passed")
    #expect((first["fixes"] as? [String])?.isEmpty == true)
    #expect(links["id"] as? String == "modemLinks")
    #expect((links["fixes"] as? [String])?.count == 2)
    #expect(checklist.count == 2)

  }

}
