import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonCore
import InsteonHTTP
import InsteonHubClient
import InsteonLinking
import InsteonModem
import InsteonProtocol
import InsteonService
import Testing
@testable import InsteonServerSupport

/// The real service behind the real listener, with a modem that goes away and comes back. Every
/// wait is on a signal: the listener opening, an event the service published, or a retry delay
/// the test releases.
@Suite(.timeLimit(.minutes(1)))
struct ServeTests {
  let password = String(repeating: "p", count: 40)
  let device = InsteonAddress(0x1A, 0x2B, 0x3C)

  private func request(_ port: Int, _ path: String, method: String = "GET", body: String? = nil) async throws -> (status: Int, json: [String: Any]) {
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
    request.httpMethod = method
    request.setValue("Basic " + Data(("insteon:" + password).utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
    if let body {
      request.httpBody = Data(body.utf8)
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue("1", forHTTPHeaderField: "X-Insteon-Request")
    }
    let (data, response) = try await URLSession.shared.data(for: request)
    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    return ((response as! HTTPURLResponse).statusCode, json)
  }

  @Test func theServerStaysUpWhileTheHubIsAwayAndRecoversWithoutARestart() async throws {
    let first = HubLink()
    let second = HubLink()
    let opener = ScriptedHubOpener([.fail(HubStoppedAnswering(underlyingError: URLError(.timedOut))), .connect(first), .connect(second)])
    let clock = ReleasableClock()
    let snapshot = NetworkSnapshot(
      registry: DeviceRegistrySnapshot(identities: [device: ReportedIdentity(category: 1, subcategory: 125, firmwareVersion: 69)]),
      devices: [device: NetworkDeviceState(level: 77, lastSeen: Date(timeIntervalSince1970: 1_800_000_000))]
    )
    let (ports, listening) = AsyncStream<Int>.makeStream()
    let (events, observed) = AsyncStream<ServiceEvent>.makeStream()
    let server = Task {
      try await ServerRunner.serve(
        network: DeviceNetwork.offline(catalog: nil, snapshot: snapshot, hub: nil),
        opener: opener,
        snapshotSavedAt: Date(timeIntervalSince1970: 1_799_999_000),
        persistence: NoSnapshots(),
        listen: "127.0.0.1",
        port: 0,
        authentication: try HTTPAuthentication(password: password),
        clock: clock,
        jitter: { 0 },
        onListening: { listening.yield($0) },
        onEvent: { observed.yield($0) }
      )
    }
    var portIterator = ports.makeAsyncIterator()
    let port = try #require(await portIterator.next())
    var seen = events.makeAsyncIterator()

    // Hub away at start: the listener is up, the list is the saved one and marked stale.
    #expect(await seen.next() == .modemUnavailable(.hubUnreachable))
    let health = try await request(port, "/api/v1/health")
    #expect(health.status == 200)
    #expect(health.json["status"] as? String == "starting")
    #expect((health.json["modem"] as? [String: Any])?["cause"] as? String == "hubUnreachable")
    let list = try await request(port, "/api/v1/devices")
    #expect(list.json["stale"] as? Bool == true)
    #expect((list.json["devices"] as? [[String: Any]])?.first?["value"] as? Int == 77)
    let refused = try await request(port, "/api/v1/devices/1A.2B.3C/commands", method: "POST", body: #"{"action":"on"}"#)
    #expect(refused.status == 503)
    #expect(refused.json["code"] as? String == "modemUnavailable")
    #expect(refused.json["sent"] as? Bool == false)

    // The Hub returns on the next attempt: commands work, clients are told to refresh.
    clock.release()
    #expect(await seen.next() == .modemReconnected)
    let ready = try await request(port, "/api/v1/health")
    #expect(ready.json["status"] as? String == "ready")
    let accepted = try await request(port, "/api/v1/devices/1A.2B.3C/commands", method: "POST", body: #"{"action":"on"}"#)
    #expect(accepted.status == 200)
    #expect(await first.modem.levels[device] == 0xFF)
    #expect(await seen.next() != nil)

    // The connection fails mid-run: HTTP stays up, commands are refused, nothing is replayed.
    first.drop(with: HubStoppedAnswering(underlyingError: URLError(.timedOut)))
    #expect(await seen.next() == .modemUnavailable(.hubUnreachable))
    let degraded = try await request(port, "/api/v1/health")
    #expect(degraded.json["status"] as? String == "degraded")
    #expect((try await request(port, "/api/v1/devices/1A.2B.3C/commands", method: "POST", body: #"{"action":"off"}"#)).status == 503)
    clock.release()
    #expect(await seen.next() == .modemReconnected)
    #expect(await second.modem.levels.isEmpty)
    #expect((try await request(port, "/api/v1/devices/1A.2B.3C/commands", method: "POST", body: #"{"action":"off"}"#)).status == 200)
    #expect(await second.modem.levels[device] == 0)

    server.cancel()
    _ = try? await server.value
  }
}
