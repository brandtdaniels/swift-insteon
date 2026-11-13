import Foundation
import Testing
import InsteonCLISupport

/// A Gregorian calendar in UTC, so the date a test builds doesn't depend on where it runs.
let observationCalendar: Calendar = {

  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

  return calendar

}()

/// The file `insteon observe` writes, built from what the checks found.
struct ObservationTests {

  let tool = ObservationTool(name: "insteon", version: "1.2.3")

  let day: Date = {

    var parts = DateComponents()
    parts.year = 2026
    parts.month = 3
    parts.day = 9
    parts.hour = 23
    parts.minute = 30

    return observationCalendar.date(from: parts) ?? Date(timeIntervalSince1970: 0)

  }()

  private func findings(
    checks: [ObservationCheckResult] = [ObservationCheckResult(name: "ID Request", outcome: .answered, detail: "Reported its identity.")],
    productKey: String? = "0x00001A",
    operatingFlags: [UInt8]? = [0x2A, 0x00]
  ) -> ObservationFindings {

    ObservationFindings(
      engine: "i2CS",
      category: "0x01",
      subcategory: "0x2D",
      firmware: "0x41",
      model: "Example Invented Product",
      productKey: productKey,
      operatingFlags: operatingFlags,
      checks: checks
    )

  }

  private func json(_ observation: Observation) throws -> [String: Any] {

    let object = try JSONSerialization.jsonObject(with: observation.json())

    return try #require(object as? [String: Any])

  }

  private func build(_ findings: ObservationFindings, note: String? = nil) throws -> Observation {

    try Observation(findings, tool: tool, catalogVersion: "0.9.1", note: note, observedOn: day, calendar: observationCalendar)

  }

  // MARK: - What the file holds

  @Test func holdsTheFormatToolCatalogAndDevice() throws {

    let object = try json(build(findings()))

    #expect(object["format"] as? String == "insteon-observation/1")
    #expect(object["tool"] as? [String: String] == ["name": "insteon", "version": "1.2.3"])
    #expect(object["catalog"] as? [String: String] == ["version": "0.9.1"])

    let device = try #require(object["device"] as? [String: String])

    #expect(device == ["category": "0x01", "subcategory": "0x2D", "firmware": "0x41", "engine": "i2CS", "model": "Example Invented Product"])

  }

  @Test func keepsTheChecksInOrder() throws {

    let checks = [
      ObservationCheckResult(name: "Get Insteon Engine Version", outcome: .answered, detail: "Reported an engine."),
      ObservationCheckResult(name: "ID Request", outcome: .refused, detail: "Refused."),
      ObservationCheckResult(name: "Product Data Request", outcome: .answered, detail: "Answered.")
    ]

    let object = try json(build(findings(checks: checks)))
    let written = try #require(object["checks"] as? [[String: String]])

    #expect(written.map { $0["name"] } == ["Get Insteon Engine Version", "ID Request", "Product Data Request"])
    #expect(written.map { $0["outcome"] } == ["answered", "refused", "answered"])

  }

  @Test func writesTheProductKeyAndTheOperatingFlagsAsHex() throws {

    let object = try json(build(findings()))

    #expect(object["productKey"] as? String == "0x00001A")
    #expect(object["operatingFlags"] as? [String: String] == ["raw": "2A 00"])

  }

  @Test func leavesOutTheProductKeyWhenTheDeviceGaveNoAnswer() throws {

    #expect(try json(build(findings(productKey: nil)))["productKey"] == nil)

  }

  @Test func writesNoneForAProductKeyTheDeviceAnsweredWithoutGiving() throws {

    #expect(try json(build(findings(productKey: "none")))["productKey"] as? String == "none")

  }

  @Test func leavesOutTheOperatingFlagsWhenNoneWereRead() throws {

    #expect(try json(build(findings(operatingFlags: nil)))["operatingFlags"] == nil)
    #expect(try json(build(findings(operatingFlags: [])))["operatingFlags"] == nil)

  }

  @Test func writesNullForADeviceFieldThatIsUnknown() throws {

    let unknown = ObservationFindings(engine: nil, category: nil, subcategory: nil, firmware: nil, model: nil, productKey: nil, operatingFlags: nil, checks: [])
    let device = try #require(json(build(unknown))["device"] as? [String: Any])

    #expect(device.count == 5)
    #expect(device.values.allSatisfy { $0 is NSNull })

  }

  @Test func recordsTheNoteWhenGiven() throws {

    #expect(try json(build(findings(), note: "Battery sensor, fresh battery"))["note"] as? String == "Battery sensor, fresh battery")
    #expect(try json(build(findings()))["note"] == nil)

  }

  @Test func recordsTheLocalDateOnly() throws {

    #expect(try json(build(findings()))["observedOn"] as? String == "2026-03-09")

  }

  // MARK: - Nothing about the home

  @Test func stripsAddressesFromCheckDetails() throws {

    let leaky = [
      "Reported by 1A.2B.3C.",
      "Heard 1a:2b:3c and 1A2B3C and 1a-2b-3c.",
      "Asked the Hub at 192.168.1.20:25105 and hub.example.com and http://192.168.1.20/ for it.",
      "Mail someone@example.com about 00:11:22:33:44:55."
    ]
    let checks = leaky.map { ObservationCheckResult(name: "ID Request", outcome: .answered, detail: $0) }

    let text = try String(decoding: build(findings(checks: checks)).json(), as: UTF8.self)

    for fragment in ["1A.2B.3C", "1a:2b:3c", "1A2B3C", "1a-2b-3c", "192.168", "25105", "example.com", "00:11:22", "someone"] {

      #expect(!text.contains(fragment), "kept \(fragment)")

    }

  }

  @Test func keepsTheDetailsWordsAroundAStrippedAddress() throws {

    let checks = [ObservationCheckResult(name: "ID Request", outcome: .answered, detail: "Device 1A.2B.3C answered.")]
    let written = try #require(json(build(findings(checks: checks)))["checks"] as? [[String: String]])

    #expect(written.first?["detail"] == "Device [removed] answered.")

  }

  @Test func keepsAProductKeyAndFlagBytesInADetail() throws {

    let checks = [ObservationCheckResult(name: "Product Data Request", outcome: .answered, detail: "Reported key 0x00001A and flags 2A 00.")]
    let written = try #require(json(build(findings(checks: checks)))["checks"] as? [[String: String]])

    #expect(written.first?["detail"] == "Reported key 0x00001A and flags 2A 00.")

  }

  @Test func refusesANoteThatHoldsAnAddress() {

    #expect(throws: ObservationError.noteHoldsAddress) {

      try build(findings(), note: "It is 1A.2B.3C on my Hub 192.168.1.20")

    }

  }

  // MARK: - Silence

  @Test func saysASilentCheckMayNeedToBeAwakeAndNeverStatesItAsAFact() throws {

    let checks = [
      ObservationCheckResult(name: "Product Data Request", outcome: .silent, detail: "No answer."),
      ObservationCheckResult(name: "Get Operating Flags", outcome: .silent, detail: "No answer. It may need to be awake.")
    ]

    let written = try #require(json(build(findings(checks: checks)))["checks"] as? [[String: String]])

    #expect(written.map { $0["outcome"] } == ["silent", "silent"])
    #expect(written[0]["detail"] == "No answer. It may need to be awake.")
    #expect(written[1]["detail"] == "No answer. It may need to be awake.")

  }

  // MARK: - The schema

  @Test func writesExactlyTheKeysTheCheckedInSchemaListsAndTheExampleHolds() throws {

    let schema = try loadJSON("Schemas/insteon-observation-1.schema.json")
    let example = try loadJSON("Schemas/insteon-observation-1.example.json")
    let properties = try #require(schema["properties"] as? [String: Any])
    let required = Set(try #require(schema["required"] as? [String]))

    let written = try json(build(findings(), note: "A note"))

    #expect(Set(written.keys) == Set(properties.keys))
    #expect(required.isSubset(of: Set(written.keys)))
    #expect(!required.contains("productKey"))
    #expect(Set(example.keys) == Set(properties.keys))
    #expect(example["format"] as? String == Observation.format)

    let device = try #require((properties["device"] as? [String: Any])?["properties"] as? [String: Any])

    #expect(Set((written["device"] as? [String: Any] ?? [:]).keys) == Set(device.keys))

  }

  private func loadJSON(_ path: String) throws -> [String: Any] {

    let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: package.appendingPathComponent(path))

    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

  }

}
