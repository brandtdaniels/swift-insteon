import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import InsteonCore
import InsteonService
import Testing
@testable import InsteonHTTP

/// What clients see while the Hub or modem is away: guided 503 responses, a health report and
/// device lists marked stale.
@Suite(.timeLimit(.minutes(1)))
struct AvailabilityTests {
  let password = String(repeating: "p", count: 40)
  let address = InsteonAddress(0x1A, 0x2B, 0x3C)
  let checkedAt = Date(timeIntervalSince1970: 1_800_000_000)

  private var authorization: HTTPFields { [.authorization: "Basic " + Data(("insteon:" + password).utf8).base64EncodedString()] }
  private var jsonHeaders: HTTPFields {
    var fields = authorization
    fields[.contentType] = "application/json"
    fields[HTTPField.Name("X-Insteon-Request")!] = "1"
    return fields
  }

  private func app(_ service: FakeService) throws -> some ApplicationProtocol {
    Application(responder: makeInsteonRouter(service: service, authentication: try HTTPAuthentication(password: password)).buildResponder())
  }

  private func health(_ readiness: ServiceHealth.Readiness, _ modem: ModemConnectionState, exchange: TimeInterval? = nil, poll: TimeInterval? = nil, updated: TimeInterval? = nil) -> ServiceHealth {
    ServiceHealth(readiness: readiness, modem: modem, lastHardwareExchange: exchange.map { checkedAt.addingTimeInterval(-$0) }, lastPoll: poll.map { checkedAt.addingTimeInterval(-$0) }, deviceInformationUpdated: updated.map { checkedAt.addingTimeInterval(-$0) }, persistence: .saved, checkedAt: checkedAt)
  }

  private func object(_ response: TestResponse) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
  }

  @Test(arguments: [
    (ModemUnavailability.hubUnreachable, "hubUnreachable", "not answering"),
    (.credentialsRejected, "credentialsRejected", "INSTEON_HUB_PASSWORD"),
    (.hubErrorStatus(503), "hubErrorStatus", "error"),
    (.modemUnreachable, "modemUnreachable", "modem"),
    (.connectionLost, "connectionLost", "lost"),
    (.connecting, "connecting", "connecting")
  ])
  func commandsGetAStable503WithAGuidedMessageWhenTheModemIsAway(_ cause: ModemUnavailability, _ code: String, _ hint: String) async throws {
    let service = FakeService(refusal: .modemUnavailable(cause))
    try await app(service).test(.router) { client in
      try await client.execute(uri: "/api/v1/devices/1A.2B.3C/commands", method: .post, headers: jsonHeaders, body: ByteBuffer(string: #"{"action":"on"}"#)) { response in
        #expect(response.status == .serviceUnavailable)
        #expect(response.headers[.contentType] == "application/json")
        let body = try object(response)
        #expect(body["version"] as? Int == 1)
        #expect(body["code"] as? String == "modemUnavailable")
        #expect(body["sent"] as? Bool == false)
        #expect(body["cause"] as? String == code)
        let message = try #require(body["message"] as? String)
        #expect(message.contains("nothing was sent"))
        #expect(message.contains(hint))
      }
    }
  }

  @Test func theBrowserFormShowsTheSameGuidanceOnTheCardWith503() async throws {
    let service = FakeService(refusal: .modemUnavailable(.hubUnreachable))
    let page = try app(service)
    try await page.test(.router) { client in
      let index = try await client.execute(uri: "/", method: .get, headers: authorization)
      let key = try #require(String(buffer: index.body).firstMatch(of: /name="formKey" value="([^"]+)"/)?.1)
      var headers = authorization
      headers[.contentType] = "application/x-www-form-urlencoded"
      headers[HTTPField.Name("X-Insteon-Fragment")!] = "device"
      let response = try await client.execute(uri: "/devices/1A.2B.3C", method: .post, headers: headers, body: ByteBuffer(string: "formKey=\(key)&action=on"))
      #expect(response.status == .serviceUnavailable)
      let html = String(buffer: response.body)
      #expect(html.contains("The Hub is not answering"))
      #expect(html.contains("nothing was sent"))
    }
  }

  @Test func healthRequiresAuthenticationAndTouchesNeitherHardwareNorTheDeviceCache() async throws {
    let service = FakeService()
    try await app(service).test(.router) { client in
      try await client.execute(uri: "/api/v1/health", method: .get) { response in
        #expect(response.status == .unauthorized)
      }
      #expect(await service.reads == 0)
      #expect(await service.commands.isEmpty)
    }
  }

  @Test func healthReportsReadinessModemAndAgesWithoutRevealingTheHousehold() async throws {
    let service = FakeService()
    await service.setHealth(health(.starting, .unavailable(.hubUnreachable), exchange: nil, updated: 3_600))
    try await app(service).test(.router) { client in
      try await client.execute(uri: "/api/v1/health", method: .get, headers: authorization) { response in
        #expect(response.status == .ok)
        #expect(response.headers[.cacheControl] == "no-store")
        let body = try object(response)
        #expect(Set(body.keys) == ["version", "status", "modem", "lastExchangeAgeSeconds", "lastPollAgeSeconds", "snapshotAgeSeconds", "persistence", "notes", "tuning"])
        #expect(body["version"] as? Int == 1)
        #expect(body["status"] as? String == "starting")
        let modem = try #require(body["modem"] as? [String: Any])
        #expect(modem["connected"] as? Bool == false)
        #expect(modem["cause"] as? String == "hubUnreachable")
        #expect(body["lastExchangeAgeSeconds"] is NSNull)
        #expect(body["lastPollAgeSeconds"] is NSNull)
        #expect(body["snapshotAgeSeconds"] as? Int == 3_600)
        #expect(body["persistence"] as? String == "saved")
        let text = String(buffer: response.body)
        #expect(!text.contains(address.description))
      }
      await service.setHealth(health(.ready, .connected, exchange: 12, poll: 2, updated: 30))
      try await client.execute(uri: "/api/v1/health", method: .get, headers: authorization) { response in
        let body = try object(response)
        #expect(body["status"] as? String == "ready")
        let modem = try #require(body["modem"] as? [String: Any])
        #expect(modem["connected"] as? Bool == true)
        #expect(modem["cause"] is NSNull)
        #expect(body["lastExchangeAgeSeconds"] as? Int == 12)
        #expect(body["lastPollAgeSeconds"] as? Int == 2)
      }
    }
  }

  @Test func theDeviceListIsMarkedStaleWhileTheModemIsAway() async throws {
    let service = FakeService()
    try await app(service).test(.router) { client in
      try await client.execute(uri: "/api/v1/devices", method: .get, headers: authorization) { response in
        let body = try object(response)
        #expect(body["stale"] as? Bool == false)
        #expect(body["cause"] is NSNull)
      }
      await service.setHealth(health(.degraded, .unavailable(.hubUnreachable), updated: 90))
      try await client.execute(uri: "/api/v1/devices", method: .get, headers: authorization) { response in
        let body = try object(response)
        #expect(body["stale"] as? Bool == true)
        #expect(body["cause"] as? String == "hubUnreachable")
        #expect((body["devices"] as? [Any])?.count == 1)
      }
      try await client.execute(uri: "/", method: .get, headers: authorization) { response in
        let html = String(buffer: response.body)
        #expect(html.contains("id=\"hub-status\""))
        #expect(html.contains("The Hub is unreachable"))
        #expect(html.contains("saved device information"))
      }
    }
  }

  @Test func eventsSayWhenTheModemIsAwayAndWhenItIsBack() async throws {
    let events = AsyncStream<ServiceEvent> { continuation in
      continuation.yield(.modemUnavailable(.hubUnreachable))
      continuation.yield(.modemReconnected)
      continuation.finish()
    }
    let service = FakeService(eventStream: events)
    try await app(service).test(.router) { client in
      let response = try await client.execute(uri: "/api/v1/events", method: .get, headers: authorization)
      let frames = try String(buffer: response.body).split(separator: "\n").filter { $0.hasPrefix("data: ") }.map {
        try #require(try JSONSerialization.jsonObject(with: Data($0.dropFirst(6).utf8)) as? [String: Any])
      }
      #expect(frames.count == 2)
      #expect(frames[0]["kind"] as? String == "modemUnavailable")
      #expect(frames[0]["cause"] as? String == "hubUnreachable")
      #expect((frames[0]["message"] as? String)?.contains("retrying") == true)
      #expect(frames[0]["address"] == nil)
      #expect(frames[1]["kind"] as? String == "reconnected")
      #expect(frames[1]["version"] as? Int == 1)
    }
  }

  @Test func theBrowserHelperShowsTheHubStateAndRefreshesEverythingWhenItReturns() {
    #expect(BrowserControls.source.contains("'modemUnavailable'"))
    #expect(BrowserControls.source.contains("'reconnected'"))
    #expect(BrowserControls.source.contains("hub-status"))
  }
}
