import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonCLISupport
import InsteonCore
import InsteonNetworking
import InsteonProtocol
import InsteonService
import Testing
@testable import InsteonServerSupport

/// A Hub Pro is served by the real server, router and service over a scripted unit: the same API,
/// the same errors, and the unit polled with a clock the test controls.
@Suite(.timeLimit(.minutes(1)))
struct HubProServeTests: ServingTests {
  let gatewayPassword = String(repeating: "g", count: 40)
  let device = InsteonAddress(0x3A, 0x4B, 0x01)
  let host = "192.168.7.20"

  static let describe = #"{"commands":[{"name":"On","parameters":["OnLevel"]},{"name":"Off"},{"name":"StatusRequest"}],"devCat":1,"device":"3A.4B.01","deviceType":"Example Dimmer","firmwareVersion":69,"location":"","name":"Example Dimmer","sku":"9101X1","subCat":125}"#

  /// A Hub Pro that answers the way the one observed does, records what it was asked, and can
  /// lose power.
  actor Unit: HTTPClient {
    private(set) var sent: [String] = []
    private var routes: [String: String] = [
      "GET /settings": #"{"time":"2026-10-28 05:00:00","network":{"address":"192.0.2.10"},"version":{"config":{"version":"5.0.6"},"server":{"version":"1.0.8.9"}}}"#,
      "GET /insteon/list": #"[{"location":"","name":"(PLM)","device":"AA.BB.CC","deviceType":"Hub Pro"},{"location":"","name":"Example Dimmer","device":"3A.4B.01","deviceType":"Example Dimmer"}]"#,
      "GET /insteon/status": #"[{"OnLevel":0,"device":"3A.4B.01"}]"#,
      "GET /insteon/describe?device=3A.4B.01": HubProServeTests.describe,
      "GET /insteon/command?device=3A.4B.01&key=Off": #"{"command":"Off","device":"3A.4B.01","result":"successful"}"#,
    ]
    private var isOn: Bool

    init(isOn: Bool = true) { self.isOn = isOn }

    func answer(_ route: String, with body: String) { routes[route] = body }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
      guard isOn else { throw URLError(.cannotConnectToHost) }
      let key = "\(request.httpMethod ?? "GET") \(request.url?.path ?? "")" + (request.url?.query.map { "?" + $0 } ?? "")
      sent.append(key)
      return HTTPResponse(statusCode: routes[key] == nil ? 404 : 200, body: Data((routes[key] ?? "").utf8))
    }
  }

  private func environment(_ directory: URL) -> [String: String] {
    // No Hub user name or password: a Hub Pro has none.
    ["HOME": directory.path, "INSTEON_GATEWAY_PASSWORD": gatewayPassword]
  }

  private func serve(_ unit: Unit, clock: any Clock<Duration> = ContinuousClock(), extra: [String] = []) async throws -> RunningServer {
    let directory = try scratch()
    let access = ServerRunner.HubProAccess(recognize: { _, _ in 80 }, httpClient: unit, clock: clock)
    return try await start(directory, extra: ["--hub", host] + extra, environment: environment(directory), hubPro: access, openModem: { _, _, _, _, _ in throw CancellationError() })
  }

  @Test func listsTheUnitsDevicesWithTheirLevels() async throws {
    let server = try await serve(Unit())
    _ = await server.code("modem_connected")
    let devices = try await server.request("/api/v1/devices", password: gatewayPassword)
    #expect(devices.status == 200)
    let listed = devices.json["devices"] as? [[String: Any]] ?? []
    #expect(listed.compactMap { $0["address"] as? String } == ["3A.4B.01"])
    await server.stop()
  }

  @Test func turnsADeviceOffThroughTheUnit() async throws {
    let unit = Unit()
    let server = try await serve(unit)
    _ = await server.code("modem_connected")
    let result = try await server.request("/api/v1/devices/3A.4B.01/commands", method: "POST", body: #"{"action":"off"}"#, password: gatewayPassword)
    #expect(result.status == 200)
    #expect(await unit.sent.last == "GET /insteon/command?device=3A.4B.01&key=Off")
    await server.stop()
  }

  @Test func aCommandTheUnitDoesNotConfirmMayHaveReachedTheDevice() async throws {
    let unit = Unit()
    await unit.answer("GET /insteon/command?device=3A.4B.01&key=Off", with: #"{"result":"failed"}"#)
    let server = try await serve(unit)
    _ = await server.code("modem_connected")
    let result = try await server.request("/api/v1/devices/3A.4B.01/commands", method: "POST", body: #"{"action":"off"}"#, password: gatewayPassword)
    #expect(result.status == 502)
    #expect(result.json["code"] as? String == "outcomeUnknown")
    #expect(result.json["sent"] as? Bool == true)
    await server.stop()
  }

  @Test func aUnitThatIsAwayIsReportedAsTheHubNotAnswering() async throws {
    let server = try await serve(Unit(isOn: false))
    _ = await server.code("hub_unreachable")
    let result = try await server.request("/api/v1/devices/3A.4B.01/commands", method: "POST", body: #"{"action":"off"}"#, password: gatewayPassword)
    #expect(result.status == 503)
    #expect(result.json["code"] as? String == "modemUnavailable")
    #expect(result.json["sent"] as? Bool == false)
    await server.stop()
  }

  @Test func pollsTheUnitAtTheIntervalTheOptionGives() async throws {
    let clock = IntervalClock()
    let server = try await serve(Unit(), clock: clock, extra: ["--poll-interval", "7"])
    _ = await server.code("modem_connected")
    var waits = clock.requested.makeAsyncIterator()
    #expect(await waits.next() == .seconds(7))
    await server.stop()
  }

  @Test func aHostThatIsNotAHubProWithoutCredentialsStillNeedsThem() async throws {
    let directory = try scratch()
    let access = ServerRunner.HubProAccess(recognize: { _, _ in nil }, httpClient: Unit())

    await #expect(throws: ConfigurationError.missingCredentials) {
      try await ServerRunner.run(arguments: ["--state", directory.appendingPathComponent("state.json").path, "--hub", host], environment: environment(directory), logger: .init(label: "test"), openModem: { _, _, _, _, _ in throw CancellationError() }, timing: .init(), hubPro: access)
    }
  }
}

/// A clock that never moves: it says how long each sleep was asked for, and waits to be canceled.
final class IntervalClock: Clock, Sendable {
  typealias Instant = ContinuousClock.Instant
  private let start = ContinuousClock.now
  let requested: AsyncStream<Duration>
  private let continuation: AsyncStream<Duration>.Continuation
  private let never: AsyncStream<Void>

  init() {
    (requested, continuation) = AsyncStream.makeStream()
    never = AsyncStream { _ in }
  }

  var now: Instant { start }
  var minimumResolution: Duration { .zero }

  func sleep(until deadline: Instant, tolerance: Duration?) async throws {
    continuation.yield(start.duration(to: deadline))
    for await _ in never {}
    throw CancellationError()
  }
}
