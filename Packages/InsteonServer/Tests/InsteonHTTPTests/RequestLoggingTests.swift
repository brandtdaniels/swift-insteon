import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import InsteonCore
import InsteonModem
import InsteonService
import Logging
import Testing
@testable import InsteonHTTP

@Suite(.timeLimit(.minutes(1)))
struct RequestLoggingTests {
  let password = String(repeating: "p", count: 40)
  let address = InsteonAddress(0x1A, 0x2B, 0x3C)

  private var authorization: String { "Basic " + Data(("insteon:" + password).utf8).base64EncodedString() }
  private var commandHeaders: HTTPFields {
    [.authorization: authorization, .contentType: "application/json", HTTPField.Name("X-Insteon-Request")!: "1"]
  }

  private func router(_ service: some InsteonServiceAPI, _ capture: LogCapture) throws -> Router<BasicRequestContext> {
    makeInsteonRouter(service: service, authentication: try HTTPAuthentication(password: password), logger: capture.logger)
  }

  @Test func aCompletedRequestLogsItsMethodRouteStatusAndDuration() async throws {
    let capture = LogCapture()
    let app = Application(responder: try router(ScriptedService(), capture).buildResponder())
    try await app.test(.router) { client in
      try await client.execute(uri: "/api/v1/devices", method: .get, headers: [.authorization: authorization]) { response in
        #expect(response.status == .ok)
      }
    }
    let record = try #require(capture.records.first)
    #expect(capture.records.count == 1)
    #expect(record.level == .info)
    #expect(record.message == "request")
    #expect(record.metadata["method"] == "GET")
    #expect(record.metadata["route"] == "/api/v1/devices")
    #expect(record.metadata["status"] == "200")
    #expect(record.metadata["code"] == "ok")
    #expect(record.metadata["duration_ms"] != nil)
    #expect(record.metadata["request_id"] != nil)
    #expect(record.metadata["cause"] == nil)
  }

  @Test func aCommandThatTimesOutLogsTheCauseAndTheRouteTemplateNotTheAddressInThePath() async throws {
    let capture = LogCapture()
    let service = ScriptedService(failure: ModemError.deviceTimedOut(address))
    let app = Application(responder: try router(service, capture).buildResponder())
    try await app.test(.router) { client in
      try await client.execute(uri: "/api/v1/devices/1A.2B.3C/commands", method: .post, headers: commandHeaders, body: ByteBuffer(string: #"{"action":"on"}"#)) { response in
        #expect(response.status == .badGateway)
        #expect(!String(buffer: response.body).contains("1A.2B.3C"))
      }
    }
    let record = try #require(capture.records.first)
    #expect(capture.records.count == 1)
    #expect(record.level == .error)
    #expect(record.metadata["method"] == "POST")
    #expect(record.metadata["route"] == "/api/v1/devices/{address}/commands")
    #expect(record.metadata["status"] == "502")
    #expect(record.metadata["code"] == "outcomeUnknown")
    let expected = try #require(InsteonErrorDescription.message(for: ModemError.deviceTimedOut(address)))
    #expect(record.metadata["cause"] == .string(expected))
    #expect(!record.rendered.contains("1A.2B.3C/commands"))
  }

  @Test func anUnclassifiedFailureLogsOnlyItsTypeNeverItsDescription() async throws {
    let capture = LogCapture()
    let app = Application(responder: try router(ScriptedService(failure: SecretCarryingError()), capture).buildResponder())
    try await app.test(.router) { client in
      try await client.execute(uri: "/api/v1/devices/1A.2B.3C/commands", method: .post, headers: commandHeaders, body: ByteBuffer(string: #"{"action":"on"}"#)) { response in
        #expect(response.status == .badGateway)
      }
    }
    let record = try #require(capture.records.first)
    #expect(record.metadata["code"] == "outcomeUnknown")
    #expect(record.metadata["cause"] == "unclassified SecretCarryingError")
    #expect(!record.rendered.contains("hunter2"))
  }

  @Test(arguments: [
    (ServiceControlError.busy, "busy", 409),
    (ServiceControlError.unknownDevice, "unknownDevice", 404),
    (ServiceControlError.invalidLevel, "invalidLevel", 400),
    (ServiceControlError.unsupportedControl, "unsupportedControl", 422)
  ])
  func refusedCommandsLogAStableCode(_ refusal: ServiceControlError, _ code: String, _ status: Int) async throws {
    let capture = LogCapture()
    let app = Application(responder: try router(ScriptedService(failure: refusal), capture).buildResponder())
    try await app.test(.router) { client in
      try await client.execute(uri: "/api/v1/devices/1A.2B.3C/commands", method: .post, headers: commandHeaders, body: ByteBuffer(string: #"{"action":"on"}"#)) { response in
        #expect(Int(response.status.code) == status)
      }
    }
    let record = try #require(capture.records.first)
    #expect(record.level == .warning)
    #expect(record.metadata["code"] == .string(code))
    #expect(record.metadata["status"] == .string(String(status)))
    #expect(record.metadata["cause"] == nil)
  }

  @Test func aRejectedPasswordLogsAWarningWithoutTheHeaderOrAnyClientText() async throws {
    let capture = LogCapture()
    let service = ScriptedService()
    let app = Application(responder: try router(service, capture).buildResponder())
    let attempt = "Basic " + Data("insteon:hunter2-guess".utf8).base64EncodedString()
    try await app.test(.router) { client in
      try await client.execute(uri: "/api/v1/devices?token=hunter2-guess", method: .get, headers: [.authorization: attempt]) { response in
        #expect(response.status == .unauthorized)
      }
    }
    let record = try #require(capture.records.first)
    #expect(capture.records.count == 1)
    #expect(record.level == .warning)
    #expect(record.metadata["status"] == "401")
    #expect(record.metadata["code"] == "authenticationFailed")
    #expect(record.metadata["route"] == "/api/v1/devices")
    for secret in ["hunter2-guess", attempt, Data("insteon:hunter2-guess".utf8).base64EncodedString(), password] {
      #expect(!record.rendered.contains(secret))
    }
    #expect(await service.reads == 0)
  }

  @Test func aRequestWithoutCredentialsLogsTheChallengeAsInformation() async throws {
    let capture = LogCapture()
    let app = Application(responder: try router(ScriptedService(), capture).buildResponder())
    try await app.test(.router) { client in
      try await client.execute(uri: "/", method: .get) { response in
        #expect(response.status == .unauthorized)
        #expect(response.headers[.wwwAuthenticate] != nil)
        #expect(response.headers[.cacheControl] == "no-store")
        #expect(String(buffer: response.body) == "Authentication required.")
      }
    }
    let record = try #require(capture.records.first)
    #expect(record.level == .info)
    #expect(record.metadata["code"] == "authenticationRequired")
  }

  @Test func anUnmatchedRouteLogsAFixedRouteNameInsteadOfTheClientsPath() async throws {
    let capture = LogCapture()
    let app = Application(responder: try router(ScriptedService(), capture).buildResponder())
    let hostile = "/%1B%5B31mowned%0Aforged-line"
    try await app.test(.router) { client in
      try await client.execute(uri: hostile, method: .get, headers: [.authorization: authorization]) { response in
        #expect(response.status == .notFound)
      }
    }
    let record = try #require(capture.records.first)
    #expect(record.metadata["route"] == "unmatched")
    #expect(record.metadata["code"] == "routeNotFound")
    #expect(!record.rendered.contains("owned"))
    #expect(!record.rendered.contains("forged"))
  }
}

private struct SecretCarryingError: Error, CustomStringConvertible, LocalizedError {
  var description: String { "password hunter2" }
  var errorDescription: String? { "password hunter2" }
}

private actor ScriptedService: InsteonServiceAPI {
  var reads = 0
  let failure: (any Error)?
  init(failure: (any Error)? = nil) { self.failure = failure }
  func devices() async throws -> [ServiceDevice] {
    reads += 1
    return []
  }
  func execute(_ command: ServiceCommand) async throws -> CommandReceipt {
    if let failure { throw failure }
    return CommandReceipt(address: command.address, outcome: .acknowledged, status: nil, persistence: .saved)
  }
  func events() async -> AsyncStream<ServiceEvent> { AsyncStream { $0.finish() } }
  func sequencedEvents(after cursor: EventCursor?) async -> SequencedEvents { SequencedEvents(AsyncThrowingStream { $0.finish() }) }
  func notificationRules() async throws -> [ServiceNotificationRule] { [] }
  func putNotificationRule(_ rule: ServiceNotificationRule) async throws {}
  func removeNotificationRule(id: String) async throws {}
  func scenes() async -> SceneListing { SceneListing(scenes: []) }
  func refreshScenes() async throws -> SceneListing { SceneListing(scenes: []) }
  func runScene(_ command: SceneCommand) async throws -> SceneReceipt { SceneReceipt(scene: command.number, action: command.action, acknowledged: [], unacknowledged: [], isComplete: true, responderCount: 0, persistence: .notConfigured) }
  func meaning(ofMemberData data: [UInt8], of device: InsteonAddress, group: UInt8) async -> LinkDataMeaning? { nil }
  func networkBackup() async -> NetworkBackup { NetworkBackup(createdAt: Date(timeIntervalSince1970: 1_800_000_000), source: .service, modem: nil, devices: []) }
  func schedules() async throws -> [ScheduleEntry] { [] }
  func putSchedule(_ schedule: ServiceSchedule) async throws -> ScheduleEntry { ScheduleEntry(schedule: schedule, nextRun: nil) }
  func removeSchedule(id: String) async throws {}
  func timers() async throws -> [TimerEntry] { [] }
  func putTimer(_ timer: ServiceTimer) async throws -> TimerEntry { TimerEntry(timer: timer, dueAt: Date(timeIntervalSince1970: 0), remainingSeconds: timer.delaySeconds) }
  func removeTimer(id: String) async throws {}
  func health() async -> ServiceHealth {
    ServiceHealth(readiness: .ready, modem: .connected, lastHardwareExchange: nil, deviceInformationUpdated: nil, persistence: .saved, checkedAt: Date(timeIntervalSince1970: 1_800_000_000))
  }
}

/// Collects what a logger receives, so a test reads the records without a log file.
final class LogCapture: @unchecked Sendable {
  struct Record {
    let level: Logger.Level
    let message: String
    let metadata: Logger.Metadata
    /// Everything a person reading the log could see.
    var rendered: String { "\(level) \(message) \(metadata)" }
  }
  private let lock = NSLock()
  private var stored: [Record] = []
  var records: [Record] { lock.withLock { stored } }
  var logger: Logger { Logger(label: "test") { _ in Handler(capture: self) } }
  fileprivate func append(_ record: Record) { lock.withLock { stored.append(record) } }

  private struct Handler: LogHandler {
    let capture: LogCapture
    var metadata: Logger.Metadata = [:]
    var logLevel: Logger.Level = .trace
    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
      get { metadata[key] }
      set { metadata[key] = newValue }
    }
    func log(event: LogEvent) {
      capture.append(Record(level: event.level, message: event.message.description, metadata: metadata.merging(event.metadata ?? [:]) { $1 }))
    }
  }
}
