import Foundation
import Testing
import InsteonCLISupport
import InsteonCore
import InsteonDeviceCatalog
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

  @Test func suggestsTurningANeverSetFlagOffWithSet() {

    #expect(SelfTestText.fix(.turnOff(setting: "lockout", label: "Lockout"), device: lamp) == "Turn Lockout off: 'insteon device 1A.2B.3C set lockout off'.")
    #expect(SelfTestText.id(.turnOff(setting: "lockout", label: "Lockout")) == "turnOff")

  }

  @Test func printsTheTurnOffFixWithItsSetting() throws {

    let locked = SelfTestReport(
      device: lamp,
      checks: [SelfTestCheck(kind: .operatingFlags, outcome: .warning, detail: "", fixes: [.turnOff(setting: "lockout", label: "Lockout")])]
    )

    let data: Data = try JSONEncoder().encode(SelfTestText.JSON(locked))
    let object: [String: Any] = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let checks: [[String: Any]] = try #require(object["checks"] as? [[String: Any]])
    let fix: [String: Any] = try #require((checks.first?["fixes"] as? [[String: Any]])?.first)

    #expect(fix["id"] as? String == "turnOff")
    #expect(fix["setting"] as? String == "lockout")
    #expect(fix["text"] as? String == "Turn Lockout off: 'insteon device 1A.2B.3C set lockout off'.")

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

    // A report without product keys leaves their keys out, and a check without a group its group.
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

  @Test func printsTheProductKeyCheckAndBothKeys() throws {

    var keyed = SelfTestReport(
      device: lamp,
      checks: [
        SelfTestCheck(
          kind: .productKey,
          outcome: .warning,
          detail: "The device reported product key 0x00ABCE, but the Insteon device catalog gives 0x00ABCD for this product.",
          fixes: [.updateCatalog]
        )
      ]
    )
    keyed.productKey = ProductKey(0x00, 0xAB, 0xCE)
    keyed.expectedProductKey = .key(ProductKey(0x00, 0xAB, 0xCD))

    let lines: [String] = SelfTestText.checkLines(keyed)
    let data: Data = try JSONEncoder().encode(SelfTestText.JSON(keyed))
    let object: [String: Any] = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let checks: [[String: Any]] = try #require(object["checks"] as? [[String: Any]])

    #expect(lines.first == "WARN  Product key  The device reported product key 0x00ABCE, but the Insteon device catalog gives 0x00ABCD for this product.")
    #expect(object["productKey"] as? String == "0x00ABCE")
    #expect(object["catalogProductKey"] as? String == "0x00ABCD")
    #expect(checks.first?["id"] as? String == "productKey")
    #expect(checks.first?["title"] as? String == "Product key")

    keyed.productKey = nil
    keyed.expectedProductKey = .notReported

    let unkeyed: Data = try JSONEncoder().encode(SelfTestText.JSON(keyed))
    let unkeyedObject: [String: Any] = try #require(try JSONSerialization.jsonObject(with: unkeyed) as? [String: Any])

    #expect(unkeyedObject["productKey"] == nil)
    #expect(unkeyedObject["catalogProductKey"] as? String == "none")

  }

  @Test func namesTheGroupOfAGroupsLinkCheck() throws {

    let grouped = SelfTestReport(
      device: lamp,
      checks: [
        SelfTestCheck(kind: .modemLinks, outcome: .passed, detail: "The device and the modem hold both records of group 1.", group: SelfTestGroup(number: 1, name: "Open")),
        SelfTestCheck(kind: .modemLinks, outcome: .warning, detail: "Group 2 isn't linked.", group: SelfTestGroup(number: 2, name: "Shut")),
        SelfTestCheck(kind: .modemLinks, outcome: .passed, detail: "Linked.", group: SelfTestGroup(number: 4, name: nil))
      ]
    )

    let lines: [String] = SelfTestText.checkLines(grouped)
    let data: Data = try JSONEncoder().encode(SelfTestText.JSON(grouped))
    let object: [String: Any] = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let checks: [[String: Any]] = try #require(object["checks"] as? [[String: Any]])

    #expect(lines == [
      "PASS  Links with the modem, group 1 (Open)  The device and the modem hold both records of group 1.",
      "WARN  Links with the modem, group 2 (Shut)  Group 2 isn't linked.",
      "PASS  Links with the modem, group 4         Linked."
    ])
    #expect(checks.map { (check: [String: Any]) -> String? in check["id"] as? String } == ["modemLinks", "modemLinks", "modemLinks"])
    #expect(checks[1]["title"] as? String == "Links with the modem, group 2 (Shut)")
    #expect(checks[1]["group"] as? Int == 2)
    #expect(checks[1]["groupName"] as? String == "Shut")
    #expect(checks[2]["group"] as? Int == 4)
    #expect(checks[2]["groupName"] == nil)

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
