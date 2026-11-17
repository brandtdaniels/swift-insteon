import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonCore
import InsteonHubClient
import InsteonModem
import InsteonNetworking
import Logging
import Testing
@testable import InsteonServerSupport

/// Drives the real Hub connection, modem and startup path with a scripted HTTP transport, so the
/// errors the server classifies are the ones the libraries really throw.
@Suite(.timeLimit(.minutes(1)))
struct HubTransportFailureTests {
  let gatewayPassword = String(repeating: "g", count: 40)

  /// - Parameter answers: Whether the Hub answers. A Hub that does not answer runs the libraries' real
  ///   timeouts on a virtual clock so nothing waits; one that answers fails at once, so a real clock never fires.
  private func start(_ transport: ScriptedTransport, answers: Bool = true) async throws -> ServerFailure? {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("insteon-server-tests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    do {
      try await ServerRunner.run(
        arguments: ["--hub", "192.168.1.20", "--port", "18080", "--state", directory.appendingPathComponent("state.json").path],
        environment: ["HOME": directory.path, "INSTEON_GATEWAY_PASSWORD": gatewayPassword, "INSTEON_HUB_USERNAME": "hub-user", "INSTEON_HUB_PASSWORD": "hub-secret-pass"],
        logger: Logger(label: "test") { _ in SwiftLogNoOpLogHandler() },
        openModem: { [clock = answers ? AnyClock(ContinuousClock()) : AnyClock(VirtualClock())] endpoint, _, snapshot, body in
          guard case let .hub(location, credentials) = endpoint else { return }
          let hub = Hub(endpoint: HubEndpoint(host: location.host, port: location.port), user: credentials.user, password: credentials.password, httpClient: transport, clock: clock)
          try await Modem.withConnection(HubConnection(hub: hub, clock: clock), clock: clock) { modem in
            try await body(DeviceNetwork(modem: modem, catalog: nil, snapshot: snapshot, hub: location))
          }
        }
      )
      return nil
    } catch {
      return ServerFailure(error)
    }
  }

  @Test(arguments: [401, 403]) func aHubThatRejectsTheCredentialsIsReportedAsRejected(_ status: Int) async throws {
    let result = try await start(ScriptedTransport(.status(status)))
    #expect(result?.code == .hubCredentialsRejected)
    #expect(result?.exitStatus == ServerFailure.configurationStatus)
    #expect(result?.message.contains("HTTP \(status)") == true)
    #expect(result?.message.contains("hub-secret-pass") == false)
  }

  @Test(arguments: [URLError.Code.timedOut, .cannotConnectToHost, .cannotFindHost, .notConnectedToInternet, .networkConnectionLost])
  func aHubThatDoesNotAnswerIsReportedAsUnreachable(_ code: URLError.Code) async throws {
    let result = try await start(ScriptedTransport(.fails(URLError(code))), answers: false)
    #expect(result?.code == .hubUnreachable)
    #expect(result?.exitStatus == ServerFailure.unavailableStatus)
    #expect(result?.message.contains("192.168.1.20:25105") == true)
  }

  @Test func aHubThatAnswersWithAServerErrorSaysSo() async throws {
    let result = try await start(ScriptedTransport(.status(500)))
    #expect(result?.code == .hubAnsweredWithError)
    #expect(result?.exitStatus == ServerFailure.unavailableStatus)
    #expect(result?.message == "The Hub answered with HTTP status 500. Check the Hub, then start the server again.")
  }

  @Test func aModemThatDoesNotAnswerOnASerialPortUsesTheLibrariesWording() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("insteon-server-tests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let connection = SilentConnection()
    let clock = VirtualClock()
    var failure: ServerFailure?
    do {
      try await ServerRunner.run(
        arguments: ["--serial", "/dev/example-modem", "--port", "18080", "--state", directory.appendingPathComponent("state.json").path],
        environment: ["HOME": directory.path, "INSTEON_GATEWAY_PASSWORD": gatewayPassword],
        logger: Logger(label: "test") { _ in SwiftLogNoOpLogHandler() },
        openModem: { _, _, snapshot, body in
          try await Modem.withConnection(connection, clock: clock) { modem in
            try await body(DeviceNetwork(modem: modem, catalog: nil, snapshot: snapshot))
          }
        }
      )
    } catch { failure = ServerFailure(error) }
    #expect(failure?.code == .hardwareError)
    #expect(failure?.message == InsteonErrorDescription.modemUnanswered(command: "Get IM Info"))
  }

  /// A Hub that rejects the credentials can also drop the connection, so the reader fails with its own
  /// error when the failed start cancels it, and that error replaces the rejection in the modem's scope.
  @Test func aRejectionIsReportedEvenWhenTheReadersOwnErrorReplacesIt() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("insteon-server-tests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let connection = RejectingConnection()
    var failure: ServerFailure?
    do {
      try await ServerRunner.run(
        arguments: ["--hub", "192.168.1.20", "--port", "18080", "--state", directory.appendingPathComponent("state.json").path],
        environment: ["HOME": directory.path, "INSTEON_GATEWAY_PASSWORD": gatewayPassword, "INSTEON_HUB_USERNAME": "hub-user", "INSTEON_HUB_PASSWORD": "hub-secret-pass"],
        logger: Logger(label: "test") { _ in SwiftLogNoOpLogHandler() },
        openModem: { _, _, snapshot, body in
          try await Modem.withConnection(connection) { modem in
            try await body(DeviceNetwork(modem: modem, catalog: nil, snapshot: snapshot))
          }
        }
      )
    } catch { failure = ServerFailure(error) }
    #expect(failure?.code == .hubCredentialsRejected)
    #expect(failure?.exitStatus == ServerFailure.configurationStatus)
  }

  @Test func theServingLineIsLoggedOnlyOnceTheListenerIsUp() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("insteon-server-tests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let capture = ServerLogCapture()
    let port = try FreePort.unused()
    let run = Task {
      try await ServerRunner.run(
        arguments: ["--hub", "192.168.1.20", "--port", String(port), "--state", directory.appendingPathComponent("state.json").path],
        environment: ["HOME": directory.path, "INSTEON_GATEWAY_PASSWORD": gatewayPassword, "INSTEON_HUB_USERNAME": "hub-user", "INSTEON_HUB_PASSWORD": "hub-secret-pass"],
        logger: capture.logger,
        openModem: { _, _, snapshot, body in
          try await ScriptedModem.open(ScriptedModem.connection(), catalog: nil, snapshot: snapshot, body: body)
        }
      )
    }
    for await message in capture.messages where message.hasPrefix("Serving") { break }
    run.cancel()
    _ = await run.result
    let messages = capture.records.map(\.message)
    let starting = try #require(messages.firstIndex { $0.hasPrefix("Starting") })
    let serving = try #require(messages.firstIndex { $0.hasPrefix("Serving") })
    #expect(starting < serving)
  }

  @Test func aFailedStartNeverLogsThatItIsServing() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("insteon-server-tests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let capture = ServerLogCapture()
    let transport = ScriptedTransport(.status(401))
    _ = try? await ServerRunner.run(
      arguments: ["--hub", "192.168.1.20", "--port", "18080", "--state", directory.appendingPathComponent("state.json").path],
      environment: ["HOME": directory.path, "INSTEON_GATEWAY_PASSWORD": gatewayPassword, "INSTEON_HUB_USERNAME": "hub-user", "INSTEON_HUB_PASSWORD": "hub-secret-pass"],
      logger: capture.logger,
      openModem: { endpoint, _, snapshot, body in
        guard case let .hub(location, credentials) = endpoint else { return }
        let hub = Hub(endpoint: HubEndpoint(host: location.host, port: location.port), user: credentials.user, password: credentials.password, httpClient: transport)
        try await Modem.withConnection(HubConnection(hub: hub)) { modem in
          try await body(DeviceNetwork(modem: modem, catalog: nil, snapshot: snapshot, hub: location))
        }
      }
    )
    let messages = capture.records.map(\.message)
    #expect(messages.contains { $0.hasPrefix("Starting") })
    #expect(!messages.contains { $0.hasPrefix("Serving") })
  }
}

/// An HTTP transport that answers every request the same way.
struct ScriptedTransport: HTTPClient {
  enum Behavior: Sendable {
    case status(Int)
    case fails(URLError)
  }
  let behavior: Behavior
  init(_ behavior: Behavior) { self.behavior = behavior }
  func send(_ request: URLRequest) async throws -> HTTPResponse {
    switch behavior {
    case let .status(code): HTTPResponse(statusCode: code)
    case let .fails(error): throw error
    }
  }
}

/// Lets a test choose between a real and a virtual clock for the same code.
struct AnyClock: Clock, Sendable {
  struct Instant: InstantProtocol {
    var offset: Duration
    func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
    func duration(to other: Instant) -> Duration { other.offset - offset }
    static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
  }
  private let nowOffset: @Sendable () -> Duration
  private let sleepUntil: @Sendable (Duration) async throws -> Void
  init<C: Clock>(_ clock: C) where C.Duration == Duration {
    let origin = clock.now
    nowOffset = { origin.duration(to: clock.now) }
    sleepUntil = { offset in try await clock.sleep(until: origin.advanced(by: offset), tolerance: nil) }
  }
  var now: Instant { Instant(offset: nowOffset()) }
  var minimumResolution: Duration { .nanoseconds(1) }
  func sleep(until deadline: Instant, tolerance: Duration?) async throws { try await sleepUntil(deadline.offset) }
}

/// A connection that accepts writes and never answers.
final class SilentConnection: ModemConnection, @unchecked Sendable {
  func write(_ bytes: [UInt8]) async throws {}
  func receive() -> AsyncThrowingStream<[UInt8], any Error> { AsyncThrowingStream<[UInt8], any Error>.makeStream().stream }
}

/// A connection whose writes are rejected with 401 and whose reader fails with a connection error
/// once it is canceled, as a dropped connection does.
final class RejectingConnection: ModemConnection, @unchecked Sendable {
  func write(_ bytes: [UInt8]) async throws { throw HubError.unexpectedStatus(401) }
  func receive() -> AsyncThrowingStream<[UInt8], any Error> {
    AsyncThrowingStream(unfolding: {
      for await _ in AsyncStream<Void>.makeStream().stream {}
      throw URLError(.networkConnectionLost)
    })
  }
}

/// A clock whose sleeps return at once and move its time forward, so the library's real retry and
/// timeout policies run without waiting.
final class VirtualClock: Clock, @unchecked Sendable {
  struct Instant: InstantProtocol {
    var offset: Duration
    func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
    func duration(to other: Instant) -> Duration { other.offset - offset }
    static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
  }
  private let lock = NSLock()
  private var elapsed = Duration.zero
  var now: Instant { lock.withLock { Instant(offset: elapsed) } }
  var minimumResolution: Duration { .nanoseconds(1) }
  func sleep(until deadline: Instant, tolerance: Duration?) async throws {
    try Task.checkCancellation()
    lock.withLock { if deadline.offset > elapsed { elapsed = deadline.offset } }
    await Task.yield()
  }
}
