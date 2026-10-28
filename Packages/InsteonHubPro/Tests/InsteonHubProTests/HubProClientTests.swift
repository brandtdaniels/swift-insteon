import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import InsteonHubPro
import InsteonNetworking
import InsteonProtocol
import InsteonTestSupport

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

  @Test func reportsSettingsItCantRead() async {

    let http = answering(#"{"time":"2026-10-28 05:00:00"}"#)

    await #expect(throws: HubProError.malformedResponse) {
      try await HubProClient(host: "192.168.1.20", httpClient: http).settings()
    }

  }

  @Test func startsAnUpdate() async throws {

    let http = answering("{}")

    try await HubProClient(host: "192.168.1.20", httpClient: http).startUpdate()

    #expect(await http.requests.first?.url?.absoluteString == "http://192.168.1.20:80/update")

  }

}
