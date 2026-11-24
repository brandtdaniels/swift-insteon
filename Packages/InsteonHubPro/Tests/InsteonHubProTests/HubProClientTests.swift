import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import InsteonHubPro
import InsteonNetworking
import InsteonProtocol
import InsteonTestSupport

@Suite(.timeLimit(.minutes(1)))
struct HubProClientTests {

  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)

  static let settingsJSON = """
    {"time":"2026-10-28 05:00:00",
     "network":{"address":"192.168.1.20","dns":"192.168.1.1","gateway":"192.168.1.1","mask":"255.255.255.0","mode":"dhcp","port":80},
     "version":{"config":{"version":"1.2","update":"","rollback":"1.1"},
                "server":{"version":"3.4","update":"3.5","rollback":"3.3"}}}
    """

  func answering(_ body: String, status: Int = 200) -> StubHTTPClient {

    StubHTTPClient(response: HTTPResponse(statusCode: status, body: Data(body.utf8)))

  }

  @Test func addsADeviceByItsAddress() async throws {

    let http = answering("{}")

    try await HubProClient(host: "192.168.1.20", httpClient: http).addDevice(lamp)

    let request = try #require(await http.requests.first)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.absoluteString == "http://192.168.1.20:80/insteon/add?sync=true&device=1A2B3C")
    #expect(request.timeoutInterval == 90)

  }

  @Test func removesADeviceByItsAddress() async throws {

    let http = answering("{}")

    try await HubProClient(host: "192.168.1.20", httpClient: http).removeDevice(lamp)

    #expect(await http.requests.first?.url?.absoluteString == "http://192.168.1.20:80/insteon/remove?sync=true&device=1A2B3C")

  }

  @Test func reportsADeviceThatDidntAnswer() async {

    let http = answering(#"{"error":"Key 'FromAddress' not found."}"#)

    await #expect(throws: HubProError.deviceNotResponding) {
      try await HubProClient(host: "192.168.1.20", httpClient: http).addDevice(lamp)
    }

  }

  @Test func reportsTheHubProsOtherErrors() async {

    let http = answering(#"{"error":"Busy"}"#)

    await #expect(throws: HubProError.rejected("Busy")) {
      try await HubProClient(host: "192.168.1.20", httpClient: http).removeDevice(lamp)
    }

  }

  @Test func reportsAnUnexpectedStatus() async {

    let http = answering("", status: 404)

    await #expect(throws: HubProError.unexpectedStatus(404)) {
      try await HubProClient(host: "192.168.1.20", httpClient: http).startUpdate()
    }

  }

  @Test func readsTheSettings() async throws {

    let http = answering(Self.settingsJSON)

    let settings = try await HubProClient(host: "192.168.1.20", httpClient: http).settings()

    #expect(settings.network == HubProSettings.Network(
      address: "192.168.1.20", dns: "192.168.1.1", gateway: "192.168.1.1", mask: "255.255.255.0", mode: "dhcp", port: 80
    ))
    #expect(settings.version.server == HubProSettings.SoftwareVersion(version: "3.4", update: "3.5", rollback: "3.3"))
    #expect(!settings.version.config.isUpdateAvailable)
    #expect(settings.isUpdateAvailable)
    #expect(await http.requests.first?.url?.path == "/settings")

  }

  @Test func readsTheSettingsWithAGetWithoutABody() async throws {

    let http = MethodScriptedHTTPClient(["GET": HTTPResponse(statusCode: 200, body: Data(Self.settingsJSON.utf8))])

    _ = try await HubProClient(host: "192.168.1.20", httpClient: http).settings()

    #expect(await http.sent == ["GET http://192.168.1.20:80/settings"])
    #expect(await http.bodies == [nil])

  }

  @Test(arguments: [404, 405])
  func readsTheSettingsWithAPostWhenTheGetIsNotAllowed(status: Int) async throws {

    let http = MethodScriptedHTTPClient([
      "GET": HTTPResponse(statusCode: status),
      "POST": HTTPResponse(statusCode: 200, body: Data(Self.settingsJSON.utf8)),
    ])

    let settings = try await HubProClient(host: "192.168.1.20", httpClient: http).settings()

    #expect(settings.network.address == "192.168.1.20")
    #expect(await http.sent == ["GET http://192.168.1.20:80/settings", "POST http://192.168.1.20:80/settings"])

  }

  @Test func doesNotFallBackToAPostForAnotherStatusOrAnUnreadableAnswer() async {

    let refused = MethodScriptedHTTPClient(["GET": HTTPResponse(statusCode: 500), "POST": HTTPResponse(statusCode: 200)])

    await #expect(throws: HubProError.unexpectedStatus(500)) {
      try await HubProClient(host: "192.168.1.20", httpClient: refused).settings()
    }
    #expect(await refused.sent == ["GET http://192.168.1.20:80/settings"])

    let unreadable = MethodScriptedHTTPClient(["GET": HTTPResponse(statusCode: 200, body: Data(#"{"error":"Busy"}"#.utf8)), "POST": HTTPResponse(statusCode: 200)])

    await #expect(throws: HubProError.rejected("Busy")) {
      try await HubProClient(host: "192.168.1.20", httpClient: unreadable).settings()
    }
    #expect(await unreadable.sent == ["GET http://192.168.1.20:80/settings"])

  }

  @Test func sendsEveryOtherRequestAsAPostAsBefore() async throws {

    let http = MethodScriptedHTTPClient(["POST": HTTPResponse(statusCode: 200, body: Data("{}".utf8))])
    let hubPro = HubProClient(host: "192.168.1.20", httpClient: http)

    try await hubPro.addDevice(lamp)
    try await hubPro.removeDevice(lamp)
    try await hubPro.startUpdate()

    #expect(await http.sent == [
      "POST http://192.168.1.20:80/insteon/add?sync=true&device=1A2B3C",
      "POST http://192.168.1.20:80/insteon/remove?sync=true&device=1A2B3C",
      "POST http://192.168.1.20:80/update",
    ])

  }

  @Test func reportsSettingsItCantRead() async {

    let http = answering(#"{"time":"2026-10-28 05:00:00"}"#)

    await #expect(throws: HubProError.malformedResponse) {
      try await HubProClient(host: "192.168.1.20", httpClient: http).settings()
    }

  }

  @Test func startsAnUpdateWhateverTheBody() async throws {

    let http = answering("")

    try await HubProClient(host: "192.168.1.20", httpClient: http).startUpdate()

    #expect(await http.requests.first?.url?.absoluteString == "http://192.168.1.20:80/update")

  }

  @Test func treatsANullOrEmptyErrorAsSuccess() async throws {

    try await HubProClient(host: "192.168.1.20", httpClient: answering(#"{"error":null}"#)).addDevice(lamp)
    try await HubProClient(host: "192.168.1.20", httpClient: answering(#"{"error":""}"#)).removeDevice(lamp)

  }

  @Test func refusesAHostOrPortItCantUse() async {

    await #expect(throws: HubProError.invalidEndpoint) {
      try await HubProClient(host: "", httpClient: answering("{}")).settings()
    }
    await #expect(throws: HubProError.invalidEndpoint) {
      try await HubProClient(host: "192.168.1.20", port: -1, httpClient: answering("{}")).settings()
    }

  }

}

/// Answers each request by its method and records what was sent.
actor MethodScriptedHTTPClient: HTTPClient {

  private(set) var sent: [String] = []

  private(set) var bodies: [Data?] = []

  private let responses: [String: HTTPResponse]

  init(_ responses: [String: HTTPResponse]) {

    self.responses = responses

  }

  func send(_ request: URLRequest) async throws -> HTTPResponse {

    let method = request.httpMethod ?? "GET"

    sent.append("\(method) \(request.url?.absoluteString ?? "")")
    bodies.append(request.httpBody)

    return responses[method] ?? HTTPResponse(statusCode: 404)

  }

}
