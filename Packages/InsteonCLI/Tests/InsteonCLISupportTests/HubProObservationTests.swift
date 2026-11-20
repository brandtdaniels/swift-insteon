import Foundation
import Testing
import InsteonCLISupport
import InsteonCore
import InsteonDeviceCatalog
import InsteonHubPro
import InsteonNetworking
import InsteonProtocol
import InsteonTestSupport

/// What `insteon observe` records about a Hub Pro: its versions, the kinds of device it lists, and
/// what it reports about each device. Every request is a read, and the file names no address.
@Suite(.timeLimit(.minutes(1)))
struct HubProObservationTests {

  static let settings = #"{"time":"2026-10-28 05:00:00","network":{"address":"192.168.7.20","dns":"192.168.7.1","gateway":"192.168.7.1","mask":"255.255.255.0","mode":"dhcp","port":80},"version":{"config":{"version":"5.0.6","update":"","rollback":"5.0.5"},"server":{"version":"1.0.8.9-stage","update":"","rollback":""}}}"#

  static let list = #"[{"location":"Kitchen","name":"(PLM)","device":"AA.BB.CC","deviceType":"Hub Pro"},{"location":"Kitchen","name":"Sam's lamp 1A.2B.3C","device":"3A.4B.01","deviceType":"Example Dimmer"},{"location":"","name":"Door","device":"3A.4B.02","deviceType":"Example Bridge"}]"#

  static func unit() -> RoutedHTTPClient {

    RoutedHTTPClient([
      "GET /settings": answerJSON(settings),
      "GET /insteon/list": answerJSON(list),
      "GET /insteon/status": answerJSON(#"[{"OnLevel":0,"device":"3A.4B.01"},{"OnLevel":0,"device":"3A.4B.02"}]"#),
      "GET /insteon/describe?device=3A.4B.01": answerJSON(HubProUnit.describe(device: "3A.4B.01", category: 1, subcategory: 14, firmware: 59, commands: [("Beep", []), ("On", ["OnLevel"]), ("Off", []), ("StatusRequest", []), ("WriteLink", [])])),
      "GET /insteon/describe?device=3A.4B.02": answerJSON(HubProUnit.describe(device: "3A.4B.02", category: 16, subcategory: 3, firmware: 7, commands: [("StatusRequest", [])])),
    ])

  }

  static func findings(_ http: RoutedHTTPClient) async throws -> HubProFindings {

    let network = HubProNetwork(transport: HubProTransport(host: HubProUnit.host, httpClient: http), catalog: nil)

    return try await HubProObservationRun.observe(network, productName: { category, subcategory, _ in category == 1 ? "Example Dimmer 9101" : nil })

  }

  @Test func recordsTheVersionsTheKindsOfDeviceAndWhatEachDeviceReports() async throws {

    let findings = try await Self.findings(Self.unit())

    #expect(findings.configVersion == "5.0.6")
    #expect(findings.serverVersion == "1.0.8.9-stage")
    #expect(findings.deviceTypes == ["Example Bridge", "Example Dimmer", "Hub Pro"])
    #expect(findings.devices.count == 2)

    let dimmer = try #require(findings.devices.first { $0.category == "0x01" })

    #expect(dimmer.deviceType == "Example Dimmer")
    #expect(dimmer.subcategory == "0x0E")
    #expect(dimmer.firmware == "0x3B")
    #expect(dimmer.sku == "9101X1")
    #expect(dimmer.model == "Example Dimmer 9101")
    #expect(dimmer.commands == [
      HubProObservedCommand(name: "Beep", parameters: []),
      HubProObservedCommand(name: "On", parameters: ["OnLevel"]),
      HubProObservedCommand(name: "Off", parameters: []),
      HubProObservedCommand(name: "StatusRequest", parameters: []),
      HubProObservedCommand(name: "WriteLink", parameters: []),
    ])

  }

  @Test func asksOnlyReadsOneAtATime() async throws {

    let http = Self.unit()

    _ = try await Self.findings(http)

    #expect(await http.sent == [
      "GET /settings", "GET /insteon/list", "GET /insteon/describe?device=3A.4B.01", "GET /insteon/describe?device=3A.4B.02", "GET /insteon/status",
    ])

  }

  @Test func theFileHoldsNoAddressNameOrLocation() async throws {

    let observation = try HubProObservation(
      try await Self.findings(Self.unit()),
      tool: ObservationTool(name: "insteon", version: "0.1.0"),
      catalogVersion: "0.9.1",
      note: "Early unit",
      observedOn: Date(timeIntervalSince1970: 1_800_000_000)
    )
    let text = String(decoding: try observation.json(), as: UTF8.self)

    for forbidden in ["3A.4B", "AA.BB.CC", "3A4B", "192.168", "Sam", "lamp", "Kitchen", "Door", "(PLM)", "2026-10-28"] {

      #expect(!text.contains(forbidden), "\(forbidden)")

    }

    #expect(text.contains(#""format" : "insteon-hubpro-observation/1""#))
    #expect(text.contains(#""configVersion" : "5.0.6""#))
    #expect(text.contains(#""name" : "WriteLink""#))
    #expect(text.hasSuffix("\n"))

  }

  @Test func keepsOnlyVersionsThatLookLikeVersions() async throws {

    let http = Self.unit()
    await http.answer("GET /settings", with: answerJSON(Self.settings.replacingOccurrences(of: "5.0.6", with: "http://192.168.7.20/x")))

    let findings = try await Self.findings(http)

    #expect(findings.configVersion == ObservationRedaction.placeholder)

  }

  @Test func refusesANoteThatHoldsAnAddress() async throws {

    #expect(throws: ObservationError.noteHoldsAddress) {
      try HubProObservation(HubProFindings(configVersion: nil, serverVersion: nil, deviceTypes: [], devices: []), tool: ObservationTool(name: "insteon", version: "0.1.0"), catalogVersion: "0.9.1", note: "at 192.168.7.20", observedOn: Date())
    }

  }

  @Test func sortsDevicesSoTheirOrderOnTheUnitIsNotRecorded() async throws {

    let findings = try await Self.findings(Self.unit())

    #expect(findings.devices.map(\.category) == ["0x01", "0x10"])

  }

  @Test func writesExactlyTheKeysTheCheckedInSchemaListsAndTheExampleHolds() async throws {

    let schema = try loadJSON("Schemas/insteon-hubpro-observation-1.schema.json")
    let example = try loadJSON("Schemas/insteon-hubpro-observation-1.example.json")
    let properties = try #require(schema["properties"] as? [String: Any])
    let observation = try HubProObservation(
      try await Self.findings(Self.unit()),
      tool: ObservationTool(name: "insteon", version: "0.1.0"),
      catalogVersion: "0.9.1",
      note: "A note",
      observedOn: Date()
    )
    let written = try #require(try JSONSerialization.jsonObject(with: observation.json()) as? [String: Any])

    #expect(Set(written.keys) == Set(properties.keys))
    #expect(Set(example.keys) == Set(properties.keys))
    #expect(example["format"] as? String == HubProObservation.format)

    let deviceProperties = try #require((((properties["devices"] as? [String: Any])?["items"] as? [String: Any])?["properties"]) as? [String: Any])
    let device = try #require((written["devices"] as? [[String: Any]])?.first)
    let exampleDevice = try #require((example["devices"] as? [[String: Any]])?.first)

    #expect(Set(device.keys) == Set(deviceProperties.keys))
    #expect(Set(exampleDevice.keys) == Set(deviceProperties.keys))

    let unitProperties = try #require((properties["unit"] as? [String: Any])?["properties"] as? [String: Any])

    #expect(Set((written["unit"] as? [String: Any] ?? [:]).keys) == Set(unitProperties.keys))

  }

  private func loadJSON(_ path: String) throws -> [String: Any] {

    let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: package.appendingPathComponent(path))

    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

  }

  @Test func keepsASKUThatLooksLikeAnAddress() async throws {

    let http = Self.unit()
    await http.answer(
      "GET /insteon/describe?device=3A.4B.01",
      with: answerJSON(HubProUnit.describe(device: "3A.4B.01", category: 1, subcategory: 14, firmware: 59, commands: []).replacingOccurrences(of: "9101X1", with: "91A1D2"))
    )

    let findings = try await Self.findings(http)

    #expect(findings.devices.first { $0.category == "0x01" }?.sku == "91A1D2")

  }

  @Test func replacesASKUThatHoldsAnythingButAModelNumber() async throws {

    let http = Self.unit()
    await http.answer(
      "GET /insteon/describe?device=3A.4B.01",
      with: answerJSON(HubProUnit.describe(device: "3A.4B.01", category: 1, subcategory: 14, firmware: 59, commands: []).replacingOccurrences(of: "9101X1", with: "http://192.168.7.20/x"))
    )

    let findings = try await Self.findings(http)

    #expect(findings.devices.first { $0.category == "0x01" }?.sku == ObservationRedaction.placeholder)

  }

}
