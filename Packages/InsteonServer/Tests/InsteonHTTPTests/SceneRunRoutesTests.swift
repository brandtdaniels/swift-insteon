import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import InsteonCore
import InsteonModem
import InsteonProtocol
import InsteonService
import Testing
@testable import InsteonHTTP

/// `POST /api/v1/scenes/{number}/commands`: run a scene of the modem, on or off.
@Suite(.timeLimit(.minutes(1)))
struct SceneRunRoutesTests {
  let password = String(repeating: "p", count: 40)
  private var basic: String { "Basic " + Data(("insteon:" + password).utf8).base64EncodedString() }

  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)
  let keypad = InsteonAddress(0x4D, 0x5E, 0x6F)

  private struct Setup {
    let service: FakeService
    let clients: ClientStore
    let app: Application<RouterResponder<BasicRequestContext>>
    init(password: String, service: FakeService) throws {
      let clients = ClientStore(persistence: InMemoryClientPersistence())
      self.service = service
      self.clients = clients
      app = Application(responder: makeInsteonRouter(service: service, authentication: try HTTPAuthentication(password: password), clients: clients).buildResponder())
    }
  }

  private func token(_ setup: Setup, scope: ClientScope) async throws -> String {
    "Bearer " + (try await setup.clients.issue(name: "Client", scope: scope)).token
  }

  private func object(_ response: TestResponse) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
  }

  private func run(_ setup: Setup, number: String = "3", body: String = #"{"action":"on"}"#, authorization: String?, marker: Bool = true, key: String? = nil, contentType: String = "application/json") async throws -> TestResponse {
    var fields: HTTPFields = authorization.map { [.authorization: $0] } ?? [:]
    fields[.contentType] = contentType
    if marker { fields[HTTPField.Name("X-Insteon-Request")!] = "1" }
    if let key { fields[.idempotencyKey] = key }
    let headers = fields
    return try await setup.app.test(.router) { client in
      try await client.execute(uri: "/api/v1/scenes/\(number)/commands", method: .post, headers: headers, body: ByteBuffer(string: body))
    }
  }

  private var service: FakeService {
    FakeService(sceneReceipt: SceneReceipt(scene: 3, action: .on, acknowledged: [lamp], unacknowledged: [keypad], isComplete: true, responderCount: 2, persistence: .saved))
  }

  // MARK: Running

  @Test func runsTheSceneAndAnswersTheReceiptWithEachMembersCleanup() async throws {
    let setup = try Setup(password: password, service: service)
    let response = try await run(setup, authorization: try await token(setup, scope: .control))
    let body = try object(response)

    #expect(response.status == .ok)
    #expect(response.headers[.contentType] == "application/json")
    #expect(body["version"] as? Int == 1)
    #expect(body["scene"] as? Int == 3)
    #expect(body["action"] as? String == "on")
    #expect(body["outcome"] as? String == "acknowledged")
    #expect(body["acknowledged"] as? [String] == ["1A.2B.3C"])
    #expect(body["unacknowledged"] as? [String] == ["4D.5E.6F"])
    #expect(body["isComplete"] as? Bool == true)
    #expect(body["responderCount"] as? Int == 2)
    #expect(body["persistence"] as? String == "saved")
    #expect(await setup.service.sceneCommands == [SceneCommand(number: 3, action: .on)])
  }

  @Test func turnsASceneOffAndSendsNoDeviceCommand() async throws {
    let setup = try Setup(password: password, service: service)
    _ = try await run(setup, body: #"{"action":"off"}"#, authorization: basic)

    #expect(await setup.service.sceneCommands == [SceneCommand(number: 3, action: .off)])
    #expect(await setup.service.commands.isEmpty)
  }

  @Test func answersAnEmptyAcknowledgedListWhenTheModemReportsNoneAndCarriesItsReportInIsComplete() async throws {
    let silent = FakeService(sceneReceipt: SceneReceipt(scene: 3, action: .on, acknowledged: [], unacknowledged: [], isComplete: false, responderCount: 2, persistence: .notConfigured))
    let setup = try Setup(password: password, service: silent)
    let body = try object(try await run(setup, authorization: basic))

    #expect(body["acknowledged"] as? [String] == [])
    #expect(body["isComplete"] as? Bool == false)
    #expect(body["persistence"] as? String == "notConfigured")
  }

  // MARK: Scope, marker and input

  @Test func refusesAReadClientBeforeTheServiceIsAsked() async throws {
    let setup = try Setup(password: password, service: service)
    let response = try await run(setup, authorization: try await token(setup, scope: .read))

    #expect(response.status == .forbidden)
    #expect(try object(response)["code"] as? String == "forbidden")
    #expect(await setup.service.sceneCommands.isEmpty)
  }

  @Test func refusesACallWithNoCredential() async throws {
    let setup = try Setup(password: password, service: service)
    let response = try await run(setup, authorization: nil)

    #expect(response.status == .unauthorized)
    #expect(await setup.service.sceneCommands.isEmpty)
  }

  @Test func refusesARunWithoutTheExplicitRequestMarker() async throws {
    let setup = try Setup(password: password, service: service)
    let response = try await run(setup, authorization: basic, marker: false)

    #expect(response.status == .forbidden)
    #expect(try object(response)["code"] as? String == "apiMarkerMissing")
    #expect(await setup.service.sceneCommands.isEmpty)
  }

  @Test func refusesABodyThatIsNotJSON() async throws {
    let setup = try Setup(password: password, service: service)
    let response = try await run(setup, authorization: basic, contentType: "text/plain")

    #expect(response.status == .unsupportedMediaType)
    #expect(try object(response)["code"] as? String == "unsupportedMediaType")
    #expect(await setup.service.sceneCommands.isEmpty)
  }

  @Test(arguments: [
    #"{"action":"on","levelPercent":50}"#,
    #"{"action":"status"}"#,
    #"{"action":"identify"}"#,
    #"{"action":"dim"}"#,
    #"{}"#,
    #"{"action":"on","extra":1}"#,
    "not json"
  ])
  func refusesACommandThatIsNotOnOrOffAndCarriesNothingElse(_ body: String) async throws {
    let setup = try Setup(password: password, service: service)
    let response = try await run(setup, body: body, authorization: basic)

    #expect(response.status == .badRequest)
    #expect(try object(response)["code"] as? String == "invalidCommand")
    #expect(try object(response)["sent"] as? Bool == false)
    #expect(await setup.service.sceneCommands.isEmpty)
  }

  @Test(arguments: ["0", "255", "256", "-1", "abc", "1.5", "03x", "005", "+5", "00", "0254", "03", "1234", "٣"])
  func refusesANumberThatIsNotAGroupFrom1Through254(_ number: String) async throws {
    let setup = try Setup(password: password, service: service)
    let response = try await run(setup, number: number, authorization: basic)

    #expect(response.status == .badRequest)
    #expect(try object(response)["code"] as? String == "invalidScene")
    #expect(try object(response)["sent"] as? Bool == false)
    #expect(await setup.service.sceneCommands.isEmpty)
  }

  @Test(arguments: ["1", "254"])
  func acceptsTheLowestAndHighestScene(_ number: String) async throws {
    let setup = try Setup(password: password, service: service)

    #expect(try await run(setup, number: number, authorization: basic).status == .ok)
    #expect(await setup.service.sceneCommands.map { String($0.number) } == [number])
  }

  // MARK: Failures

  @Test(arguments: [
    (ServiceControlError.unknownScene as any Error, 404, "unknownScene", false),
    (ServiceControlError.sceneEmpty as any Error, 422, "sceneEmpty", false),
    (ServiceControlError.busy as any Error, 409, "busy", false),
    (ServiceControlError.modemUnavailable(.hubUnreachable) as any Error, 503, "modemUnavailable", false),
    (ModemError.rejected(.sendAllLinkCommand) as any Error, 503, "modemRejected", false),
    (ModemError.timedOut(.sendAllLinkCommand) as any Error, 502, "outcomeUnknown", true),
    (ModemError.connectionClosed as any Error, 502, "outcomeUnknown", true),
    (CancellationError() as any Error, 503, "canceled", true)
  ])
  func answersEachFailureWithOneCodeAndSaysWhetherTheCommandMayHaveReachedTheMembers(_ failure: any Error, _ status: Int, _ code: String, _ sent: Bool) async throws {
    let setup = try Setup(password: password, service: FakeService(sceneFailure: failure))
    let response = try await run(setup, authorization: basic)
    let body = try object(response)

    #expect(Int(response.status.code) == status)
    #expect(body["code"] as? String == code)
    #expect(body["sent"] as? Bool == sent)
    #expect(await setup.service.sceneCommands.count == 1)
  }

  @Test func saysAHubProCannotRunScenesWhenTheServiceRefusesTheGroupCommand() async throws {
    let setup = try Setup(password: password, service: FakeService(sceneFailure: ServiceControlError.databasesUnavailable))
    let body = try object(try await run(setup, authorization: basic))

    #expect(body["code"] as? String == "databasesUnavailable")
    #expect(body["sent"] as? Bool == false)
  }

  // MARK: Idempotency

  @Test func answersARepeatWithTheRecordedReceiptAndRunsTheSceneOnce() async throws {
    let setup = try Setup(password: password, service: service)
    let first = try await run(setup, authorization: basic, key: "run-1")
    let second = try await run(setup, authorization: basic, key: "run-1")

    #expect(first.status == .ok)
    #expect(second.status == .ok)
    #expect(second.headers[.idempotentReplay] == "true")
    #expect(first.headers[.idempotentReplay] == nil)
    #expect(Array(first.body.readableBytesView) == Array(second.body.readableBytesView))
    #expect(await setup.service.sceneCommands.count == 1)
  }

  @Test func refusesAKeyUsedForADifferentSceneOrAction() async throws {
    let setup = try Setup(password: password, service: service)
    _ = try await run(setup, authorization: basic, key: "run-1")
    let otherAction = try await run(setup, body: #"{"action":"off"}"#, authorization: basic, key: "run-1")
    let otherScene = try await run(setup, number: "4", authorization: basic, key: "run-1")

    #expect(try object(otherAction)["code"] as? String == "idempotencyKeyReused")
    #expect(try object(otherScene)["code"] as? String == "idempotencyKeyReused")
    #expect(await setup.service.sceneCommands.count == 1)
  }

  @Test func recordsAnOutcomeThatMayHaveReachedTheMembersAndRepeatsItWithoutSendingAgain() async throws {
    let setup = try Setup(password: password, service: FakeService(sceneFailure: ModemError.timedOut(.sendAllLinkCommand)))
    let first = try await run(setup, authorization: basic, key: "run-2")
    let second = try await run(setup, authorization: basic, key: "run-2")

    #expect(try object(first)["code"] as? String == "outcomeUnknown")
    #expect(try object(second)["code"] as? String == "outcomeUnknown")
    #expect(second.headers[.idempotentReplay] == "true")
    #expect(await setup.service.sceneCommands.count == 1)
  }

  @Test func doesNotRecordARefusalThatSentNothingSoTheRepeatMaySucceed() async throws {
    let setup = try Setup(password: password, service: FakeService(sceneFailure: ServiceControlError.busy))
    _ = try await run(setup, authorization: basic, key: "run-3")
    _ = try await run(setup, authorization: basic, key: "run-3")

    #expect(await setup.service.sceneCommands.count == 2)
  }

  @Test func refusesAMalformedIdempotencyKey() async throws {
    let setup = try Setup(password: password, service: service)
    let response = try await run(setup, authorization: basic, key: "bad key!")

    #expect(try object(response)["code"] as? String == "invalidIdempotencyKey")
    #expect(await setup.service.sceneCommands.isEmpty)
  }

  // MARK: Timing

  @Test func logsHowLongARunTookAtDebugLevelWithNoAddress() async throws {
    let capture = LogCapture()
    let app = Application(responder: makeInsteonRouter(service: service, authentication: try HTTPAuthentication(password: password), logger: capture.logger).buildResponder())
    try await app.test(.router) { client in
      let response = try await client.execute(uri: "/api/v1/scenes/3/commands", method: .post, headers: [.authorization: basic, .contentType: "application/json", HTTPField.Name("X-Insteon-Request")!: "1"], body: ByteBuffer(string: #"{"action":"on"}"#))
      #expect(response.status == .ok)
    }

    let line = try #require(capture.records.first { $0.message == "scene run finished" })
    #expect(line.level == .debug)
    #expect(line.metadata["scene"] == "3")
    #expect(line.metadata["action"] == "on")
    #expect(line.metadata["isComplete"] == "true")
    #expect(line.metadata["acknowledged"] == "1")
    #expect(line.metadata["unacknowledged"] == "1")
    #expect(line.metadata["seconds"] != nil)
    #expect(!"\(line.metadata)".contains("1A.2B.3C"))
  }

  @Test func logsHowLongAfterTheEchoTheStatusAndFailureReportsCameWhenTheReceiptSaysSo() async throws {
    let timed = FakeService(sceneReceipt: SceneReceipt(scene: 3, action: .on, acknowledged: [], unacknowledged: [], isComplete: true, responderCount: 2, persistence: .saved, statusReportAfter: .milliseconds(24_500), failureReportedAfter: .seconds(12)))
    let capture = LogCapture()
    let app = Application(responder: makeInsteonRouter(service: timed, authentication: try HTTPAuthentication(password: password), logger: capture.logger).buildResponder())
    try await app.test(.router) { client in
      _ = try await client.execute(uri: "/api/v1/scenes/3/commands", method: .post, headers: [.authorization: basic, .contentType: "application/json", HTTPField.Name("X-Insteon-Request")!: "1"], body: ByteBuffer(string: #"{"action":"on"}"#))
    }

    let line = try #require(capture.records.first { $0.message == "scene run finished" })
    #expect(line.metadata["statusReportSeconds"] == "24.5")
    #expect(line.metadata["failureReportSeconds"] == "12.0")
  }

  @Test func logsNoReportTimesWhenTheModemSentNone() async throws {
    let capture = LogCapture()
    let app = Application(responder: makeInsteonRouter(service: service, authentication: try HTTPAuthentication(password: password), logger: capture.logger).buildResponder())
    try await app.test(.router) { client in
      _ = try await client.execute(uri: "/api/v1/scenes/3/commands", method: .post, headers: [.authorization: basic, .contentType: "application/json", HTTPField.Name("X-Insteon-Request")!: "1"], body: ByteBuffer(string: #"{"action":"on"}"#))
    }

    let line = try #require(capture.records.first { $0.message == "scene run finished" })
    #expect(line.metadata["statusReportSeconds"] == "none")
    #expect(line.metadata["failureReportSeconds"] == "none")
  }

  // MARK: Health shows the tuning

  @Test func healthListsEveryTuningValueWithItsSource() async throws {
    let entries = [TuningEntry(name: "scenes.echoWaitMs", milliseconds: 8_000, source: .flag), TuningEntry(name: "scenes.cleanupQuietMs", milliseconds: 15_000, source: .default)]
    let fake = FakeService()
    await fake.setHealth(ServiceHealth(readiness: .ready, modem: .connected, lastHardwareExchange: nil, deviceInformationUpdated: nil, persistence: .saved, checkedAt: Date(timeIntervalSince1970: 1_800_000_000), tuning: entries))
    let setup = try Setup(password: password, service: fake)
    let response = try await setup.app.test(.router) { client in
      try await client.execute(uri: "/api/v1/health", method: .get, headers: [.authorization: basic])
    }
    let tuning = try #require(try object(response)["tuning"] as? [[String: Any]])

    #expect(tuning.count == 2)
    #expect(tuning[0]["name"] as? String == "scenes.echoWaitMs")
    #expect(tuning[0]["value"] as? Int == 8_000)
    #expect(tuning[0]["unit"] as? String == "ms")
    #expect(tuning[0]["source"] as? String == "flag")
    #expect(tuning[1]["source"] as? String == "default")
  }

  // MARK: Description

  @Test func declaresTheControlScopeAPostWithAJSONBodyAndTheErrorsARunCanAnswer() {
    let operation = APIOperation.runScene
    #expect(operation.requiredScope == .control)
    #expect(operation.method == .post)
    #expect(operation.path == "/api/v1/scenes/{number}/commands")
    #expect(operation.requestBody?.contentType == "application/json")
    #expect(operation.parameters.contains { $0.name == "Idempotency-Key" })
    #expect(operation.parameters.contains { $0.name == "X-Insteon-Request" && $0.required })
    for code in [APIErrorCode.forbidden, .invalidScene, .invalidCommand, .unknownScene, .sceneEmpty, .busy, .modemUnavailable, .modemRejected, .outcomeUnknown, .canceled, .idempotencyKeyReused, .invalidIdempotencyKey, .apiMarkerMissing, .databasesUnavailable] {
      #expect(operation.errorCodes.contains(code), "\(code)")
    }
  }

  @Test func givesTheNewErrorsTheirStatusAndNeverSaysAnythingWasSentForThem() {
    #expect(APIErrorCode.invalidScene.status == .badRequest)
    #expect(APIErrorCode.unknownScene.status == .notFound)
    #expect(APIErrorCode.sceneEmpty.status == .unprocessableContent)
    #expect([APIErrorCode.invalidScene, .unknownScene, .sceneEmpty].allSatisfy { !$0.sent })
  }
}
