import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import InsteonCore
import InsteonLinking
import InsteonModem
import InsteonProtocol
import InsteonService
import Logging
import Testing
@testable import InsteonHTTP

/// What applying the example plan answers, built from the plan the plan routes' tests use.
enum SceneApplyExample {
  static func plan() async -> SceneMembershipPlan {
    await ScenePlanExample.plan(ScenePlanExample.addLamp())
  }

  static func application(_ plan: SceneMembershipPlan, outcomes: [DatabaseLinkStepOutcome]? = nil, mismatches: [SceneMembershipResult.Mismatch] = [], interruption: SceneMembershipApplication.Interruption? = nil, isCacheReloaded: Bool = true, expectedUnreadable: [InsteonAddress] = []) -> SceneMembershipApplication {
    let outcomes = outcomes ?? plan.steps.map { _ in .written }
    let result = SceneMembershipResult(
      plan: plan,
      steps: zip(plan.steps, outcomes).map { SceneMembershipResult.StepResult(step: $0, outcome: $1) },
      mismatches: mismatches,
      deviceChecks: [ScenePlanExample.lamp: .checked],
      isModemChecked: true
    )
    return SceneMembershipApplication(scene: plan.scene, planId: plan.id, result: result, interruption: interruption, persistence: .saved, isCacheReloaded: isCacheReloaded, expectedUnreadable: expectedUnreadable)
  }
}

/// `POST /api/v1/scenes/{number}/plans/{id}/apply`: writes a plan's ALL-Link records with consent that
/// names the plan, answers each step's outcome, and never repeats a step.
@Suite(.timeLimit(.minutes(1)))
struct SceneMembershipApplyRoutesTests {
  let password = String(repeating: "p", count: 40)
  private var basic: String { "Basic " + Data(("insteon:" + password).utf8).base64EncodedString() }

  private struct Setup {
    let service: FakeService
    let clients: ClientStore
    let plan: SceneMembershipPlan
    let app: Application<RouterResponder<BasicRequestContext>>
  }

  private func setup(outcomes: [DatabaseLinkStepOutcome]? = nil, mismatches: [SceneMembershipResult.Mismatch] = [], interruption: SceneMembershipApplication.Interruption? = nil, isCacheReloaded: Bool = true, expectedUnreadable: [InsteonAddress] = [], failure: (any Error)? = nil, logger: Logger? = nil) async throws -> Setup {
    let plan = await SceneApplyExample.plan()
    let service = FakeService()
    await service.scriptApply(answer: failure == nil ? SceneApplyExample.application(plan, outcomes: outcomes, mismatches: mismatches, interruption: interruption, isCacheReloaded: isCacheReloaded, expectedUnreadable: expectedUnreadable) : nil, failure: failure)
    let clients = ClientStore(persistence: InMemoryClientPersistence())
    let app = Application(responder: makeInsteonRouter(service: service, authentication: try HTTPAuthentication(password: password), clients: clients, logger: logger ?? Logger(label: "test")).buildResponder())
    return Setup(service: service, clients: clients, plan: plan, app: app)
  }

  private func token(_ setup: Setup, scope: ClientScope) async throws -> String {
    "Bearer " + (try await setup.clients.issue(name: "Client", scope: scope)).token
  }

  private func object(_ response: TestResponse) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
  }

  private func consent(_ plan: SceneMembershipPlan, writeLinkRecords: Bool = true) -> String {
    #"{"consent":{"writeLinkRecords":\#(writeLinkRecords),"readFingerprint":"\#(plan.fingerprint)"}}"#
  }

  private func apply(_ setup: Setup, number: String = "4", planId: String? = nil, body: String? = nil, authorization: String?, marker: Bool = true, contentType: String = "application/json", key: String? = nil) async throws -> TestResponse {
    var fields: HTTPFields = authorization.map { [.authorization: $0] } ?? [:]
    fields[.contentType] = contentType
    if marker { fields[HTTPField.Name("X-Insteon-Request")!] = "1" }
    if let key { fields[.idempotencyKey] = key }
    let headers = fields
    let id = planId ?? setup.plan.id
    let payload = body ?? consent(setup.plan)
    return try await setup.app.test(.router) { client in
      try await client.execute(uri: "/api/v1/scenes/\(number)/plans/\(id)/apply", method: .post, headers: headers, body: ByteBuffer(string: payload))
    }
  }

  // MARK: The answer

  @Test func answersEachStepWithItsOutcomeAndThatTheScenesRecordsReadBackAsPlanned() async throws {
    let setup = try await setup()
    let response = try await apply(setup, authorization: basic)
    let body = try object(response)
    let steps = try #require(body["steps"] as? [[String: Any]])

    #expect(response.status == .ok)
    #expect(response.headers[.contentType] == "application/json")
    #expect(body["version"] as? Int == 1)
    #expect(body["scene"] as? Int == 4)
    #expect(body["planId"] as? String == setup.plan.id)
    #expect(body["outcome"] as? String == "applied")
    #expect(body["isComplete"] as? Bool == true)
    #expect(body["persistence"] as? String == "saved")
    #expect(steps.map { $0["order"] as? Int } == [1, 2])
    #expect(steps.map { $0["kind"] as? String } == ["addDeviceRecord", "addModemRecord"])
    #expect(steps.map { $0["target"] as? String } == ["1A.2B.3C", "modem"])
    #expect(steps.map { $0["outcome"] as? String } == ["written", "written"])
    #expect((body["mismatches"] as? [Any])?.isEmpty == true)
    #expect(body["modemChecked"] as? Bool == true)
    let checks = try #require(body["deviceChecks"] as? [[String: Any]])
    #expect(checks.map { $0["device"] as? String } == ["1A.2B.3C"])
    #expect(checks.map { $0["check"] as? String } == ["checked"])
  }

  @Test func handsTheServiceTheSceneThePlanAndTheConsentExactlyAsGiven() async throws {
    let setup = try await setup()
    _ = try await apply(setup, authorization: basic)

    #expect(await setup.service.applyRequests == [FakeService.ApplyRequest(scene: 4, planId: setup.plan.id, consent: DatabaseLinkConsent(writeLinkRecords: true, readFingerprint: setup.plan.fingerprint))])
  }

  @Test func saysEachStepThatReadBackDifferentlyOnceAndWasWrittenAgainWasWrittenOnRetry() async throws {
    let setup = try await setup(outcomes: [.writtenOnRetry, .written])
    let body = try object(try await apply(setup, authorization: basic))
    let steps = try #require(body["steps"] as? [[String: Any]])

    #expect(steps.map { $0["outcome"] as? String } == ["writtenOnRetry", "written"])
    #expect(body["isComplete"] as? Bool == true)
  }

  // MARK: What a client and the log are told

  @Test func saysWhetherTheServiceReadTheChangedDatabasesIntoItsCache() async throws {
    let reloaded = try object(try await apply(try await setup(), authorization: basic))
    let notReloaded = try object(try await apply(try await setup(isCacheReloaded: false), authorization: basic))

    #expect(reloaded["cacheReload"] as? String == "reloaded")
    #expect(notReloaded["cacheReload"] as? String == "failed")
  }

  @Test func listsADeviceThatRejectsTheModemAsExpectedAndStillSaysReloaded() async throws {
    let body = try object(try await apply(try await setup(expectedUnreadable: [ScenePlanExample.lamp]), authorization: basic))

    #expect(body["cacheReload"] as? String == "reloaded")
    #expect(body["expectedUnreadable"] as? [String] == ["1A.2B.3C"])
    #expect((try object(try await apply(try await setup(), authorization: basic))["expectedUnreadable"] as? [String])?.isEmpty == true)
  }

  @Test func logsAnIncompleteApplyAtWarningWithTheCountsAndNoAddress() async throws {
    let capture = LogCapture()
    let setup = try await setup(outcomes: [.written, .notWritten], logger: capture.logger)
    _ = try await apply(setup, authorization: basic)

    let line = try #require(capture.records.first { $0.message == "scene membership apply incomplete" })
    #expect(line.level == .warning)
    #expect(line.metadata["scene"] == "4")
    #expect(line.metadata["written"] == "1")
    #expect(line.metadata["notWritten"] == "1")
    #expect(!"\(line.metadata)".contains("1A.2B.3C"))
    #expect(capture.records.contains { $0.message == "scene membership applied" } == false)
  }

  @Test func logsACompleteApplyAtInfo() async throws {
    let capture = LogCapture()
    _ = try await apply(try await setup(logger: capture.logger), authorization: basic)

    let line = try #require(capture.records.first { $0.message == "scene membership applied" })
    #expect(line.level == .info)
  }

  @Test func logsAWarningWhenTheCacheWasNotReloaded() async throws {
    let capture = LogCapture()
    _ = try await apply(try await setup(isCacheReloaded: false, logger: capture.logger), authorization: basic)

    let line = try #require(capture.records.first { $0.message == "scene membership apply left the cache stale" })
    #expect(line.level == .warning)
    #expect(line.metadata["scene"] == "4")
  }

  // MARK: The documented failures

  /// Every failure the route can answer besides the credential's, each produced by a request below.
  private static let answeredCodes: Set<String> = [
    "invalidScene", "invalidCommand", "invalidBody", "invalidIdempotencyKey", "apiMarkerMissing", "unsupportedMediaType", "bodyTooLarge",
    "consentRequired", "consentMismatch", "unknownPlan", "planExpired", "planAlreadyApplied", "planNotApplicable", "planStale",
    "idempotencyKeyReused", "busy", "modemUnavailable", "databasesUnavailable", "deviceNotAnswering", "deviceRejected", "notLinked", "modemRejected",
    "canceled", "outcomeUnknown"
  ]

  @Test func documentsExactlyTheCodesTheRouteAnswers() async throws {
    let documented = Set(APIOperation.applySceneMembership.errorCodes.map(\.rawValue)).subtracting(["authenticationRequired", "authenticationFailed", "forbidden"])

    #expect(documented == Self.answeredCodes)
  }

  @Test func answersEachDocumentedCodeFromARequest() async throws {
    var produced: Set<String> = []
    let failures: [any Error] = [
      ServiceControlError.unknownPlan, ServiceControlError.planExpired, ServiceControlError.planAlreadyApplied, ServiceControlError.planNotApplicable,
      ServiceControlError.planStale, ServiceControlError.consentMismatch, ServiceControlError.deviceNotAnswering, ServiceControlError.busy, ServiceControlError.modemUnavailable(.connecting),
      ServiceControlError.databasesUnavailable, ModemError.deviceTimedOut(ScenePlanExample.lamp), ModemError.deviceRejected(ScenePlanExample.lamp, NAKReason(rawValue: 0xFD)),
      ModemError.deviceRejected(ScenePlanExample.lamp, .notLinked), ModemError.rejected(.getModemInfo), CancellationError()
    ]
    for failure in failures {
      let setup = try await setup(failure: failure)
      let response = try await apply(setup, authorization: basic)
      produced.insert(try #require(try object(response)["code"] as? String))
      #expect(try object(response)["sent"] as? Bool == false)
    }
    let setup = try await setup(outcomes: [.written, .unanswered])
    produced.insert(try #require(try object(try await apply(setup, authorization: basic))["code"] as? String))
    let requests: [(String?, String, Bool, String)] = [("0", consent(setup.plan), true, "application/json"), ("4", "{}", true, "application/json"), ("4", "[1]", true, "application/json"),
      ("4", #"{"consent":"x"}"#, true, "application/json"), ("4", consent(setup.plan), false, "application/json"), ("4", consent(setup.plan), true, "text/plain"),
      ("4", String(repeating: " ", count: 8193), true, "application/json")]
    for (number, body, marker, type) in requests {
      let response = try await apply(setup, number: number ?? "4", body: body, authorization: basic, marker: marker, contentType: type)
      produced.insert(try #require(try object(response)["code"] as? String))
    }
    produced.insert(try #require(try object(try await apply(setup, authorization: basic, key: "bad key!"))["code"] as? String))
    _ = try await apply(setup, authorization: basic, key: "k1")
    produced.insert(try #require(try object(try await apply(setup, planId: "sha256:" + String(repeating: "a", count: 64), authorization: basic, key: "k1"))["code"] as? String))

    #expect(produced == Self.answeredCodes)
  }

  // MARK: A step that fails

  @Test func answersOutcomeUnknownWithEveryStepsOutcomeWhenAStepFailsAndTheLaterOnesWereNotReached() async throws {
    let setup = try await setup(outcomes: [.written, .notReached])
    let response = try await apply(setup, authorization: basic)
    let body = try object(response)
    let steps = try #require(body["steps"] as? [[String: Any]])

    #expect(response.status == .badGateway)
    #expect(body["code"] as? String == "outcomeUnknown")
    #expect(body["sent"] as? Bool == true)
    #expect(body["outcome"] as? String == "incomplete")
    #expect(body["isComplete"] as? Bool == false)
    #expect(steps.map { $0["outcome"] as? String } == ["written", "notReached"])
    #expect(body["written"] as? Int == 1)
    #expect(body["notWritten"] as? Int == 1)
    #expect((body["message"] as? String)?.contains("plan again") == true)
  }

  @Test func answersTheFailedStepAsNotWrittenWhenItReadBackDifferentlyTwice() async throws {
    let setup = try await setup(outcomes: [.notWritten, .notReached])
    let response = try await apply(setup, authorization: basic)
    let steps = try #require(try object(response)["steps"] as? [[String: Any]])

    #expect(response.status == .badGateway)
    #expect(steps.map { $0["outcome"] as? String } == ["notWritten", "notReached"])
  }

  @Test func answersIncompleteWhenEveryStepWasMadeButTheFinalReadFoundADifferentRecord() async throws {
    let record = SceneMembershipResult.Mismatch(device: ScenePlanExample.lamp, mismatch: DatabaseMismatch(isDevice: true, memoryAddress: 0x0FF7, expected: LinkRecord(isController: false, isInUse: true, group: 4, address: ScenePlanExample.modem, data: [255, 31, 1], memoryAddress: 0x0FF7), found: nil))
    let setup = try await setup(mismatches: [record])
    let response = try await apply(setup, authorization: basic)
    let body = try object(response)
    let mismatches = try #require(body["mismatches"] as? [[String: Any]])

    #expect(response.status == .badGateway)
    #expect(body["outcome"] as? String == "incomplete")
    #expect(mismatches.count == 1)
    #expect(mismatches[0]["target"] as? String == "1A.2B.3C")
    #expect(mismatches[0]["memoryAddress"] as? String == "0x0FF7")
    #expect(mismatches[0]["found"] is NSNull)
  }

  @Test func saysTheRequestWasCanceledBetweenStepsAndWhichStepsWereMade() async throws {
    let setup = try await setup(outcomes: [.written, .notReached], interruption: .canceled)
    let response = try await apply(setup, authorization: basic)
    let body = try object(response)

    #expect(response.status == .badGateway)
    #expect(body["interruption"] as? String == "canceled")
    #expect(body["written"] as? Int == 1)
  }

  @Test func saysTheModemFailedAndNamesNoAddress() async throws {
    let setup = try await setup(outcomes: [.unanswered, .notReached], interruption: .failed("The modem stopped answering."))
    let body = try object(try await apply(setup, authorization: basic))

    #expect(body["interruption"] as? String == "failed")
    #expect(body["interruptionDetail"] as? String == "The modem stopped answering.")
  }

  // MARK: Consent

  @Test(arguments: [
    "{}",
    #"{"consent":null}"#,
    #"{"consent":{}}"#,
    #"{"consent":{"writeLinkRecords":false,"readFingerprint":"sha256:x"}}"#,
    #"{"consent":{"readFingerprint":"sha256:x"}}"#,
    #"{"consent":{"writeLinkRecords":true}}"#,
    #"{"consent":{"writeLinkRecords":true,"readFingerprint":""}}"#
  ])
  func writesNothingWithoutConsentThatAgrees(_ body: String) async throws {
    let setup = try await setup()
    let response = try await apply(setup, body: body, authorization: basic)
    let answer = try object(response)

    #expect(Int(response.status.code) == 422)
    #expect(answer["code"] as? String == "consentRequired")
    #expect(answer["sent"] as? Bool == false)
    #expect(await setup.service.applyRequests.isEmpty)
  }

  @Test func neverTakesAnAdminCredentialAsConsent() async throws {
    let setup = try await setup()
    let response = try await apply(setup, body: "{}", authorization: basic)

    #expect(try object(response)["code"] as? String == "consentRequired")
    #expect(await setup.service.applyRequests.isEmpty)
  }

  @Test func refusesConsentThatNamesAnotherPlanBecauseTheServiceSaysSo() async throws {
    let setup = try await setup()
    await setup.service.scriptApply(failure: ServiceControlError.consentMismatch)
    let response = try await apply(setup, body: #"{"consent":{"writeLinkRecords":true,"readFingerprint":"sha256:\#(String(repeating: "0", count: 64))"}}"#, authorization: basic)
    let body = try object(response)

    #expect(Int(response.status.code) == 422)
    #expect(body["code"] as? String == "consentMismatch")
    #expect(body["sent"] as? Bool == false)
  }

  @Test(arguments: [
    #"{"consent":{"writeLinkRecords":true,"readFingerprint":"sha256:x"},"force":true}"#,
    #"{"consent":{"writeLinkRecords":true,"readFingerprint":"sha256:x","force":true}}"#,
    #"{"consent":{"writeLinkRecords":true,"readFingerprint":"sha256:x"},"extra":1}"#,
    "not json",
    "[]"
  ])
  func takesNoForceFieldAndNoOtherFieldBecauseNothingDestructiveIsSent(_ body: String) async throws {
    let setup = try await setup()
    let response = try await apply(setup, body: body, authorization: basic)

    #expect(response.status == .badRequest)
    #expect(try object(response)["code"] as? String == "invalidCommand")
    #expect(await setup.service.applyRequests.isEmpty)
  }

  @Test(arguments: [
    #"{"consent":{"writeLinkRecords":"yes","readFingerprint":"sha256:x"}}"#,
    #"{"consent":{"writeLinkRecords":1,"readFingerprint":"sha256:x"}}"#,
    #"{"consent":{"writeLinkRecords":true,"readFingerprint":5}}"#,
    #"{"consent":{"writeLinkRecords":null,"readFingerprint":["sha256:x"]}}"#,
    #"{"consent":"yes"}"#,
    #"{"consent":[true]}"#,
    #"{"consent":7}"#
  ])
  func refusesAConsentOfTheWrongTypeAsAnInvalidBodyAndNotAsMissingConsent(_ body: String) async throws {
    let setup = try await setup()
    let response = try await apply(setup, body: body, authorization: basic)
    let answer = try object(response)

    #expect(response.status == .badRequest)
    #expect(answer["code"] as? String == "invalidBody")
    #expect(answer["sent"] as? Bool == false)
    #expect(await setup.service.applyRequests.isEmpty)
  }

  // MARK: The plan

  @Test(arguments: [
    (ServiceControlError.unknownPlan as any Error, 404, "unknownPlan"),
    (ServiceControlError.planExpired as any Error, 410, "planExpired"),
    (ServiceControlError.planAlreadyApplied as any Error, 409, "planAlreadyApplied"),
    (ServiceControlError.planNotApplicable as any Error, 422, "planNotApplicable"),
    (ServiceControlError.planStale as any Error, 409, "planStale"),
    (ServiceControlError.unknownScene as any Error, 404, "unknownScene"),
    (ServiceControlError.busy as any Error, 409, "busy"),
    (ServiceControlError.databasesUnavailable as any Error, 422, "databasesUnavailable"),
    (ServiceControlError.modemUnavailable(.connecting) as any Error, 503, "modemUnavailable")
  ])
  func answersEachRefusalWithOneCodeAndSaysNothingWasSent(_ failure: any Error, _ status: Int, _ code: String) async throws {
    let setup = try await setup(failure: failure)
    let response = try await apply(setup, authorization: basic)
    let body = try object(response)

    #expect(Int(response.status.code) == status)
    #expect(body["code"] as? String == code)
    #expect(body["sent"] as? Bool == false)
    #expect(await setup.service.applyRequests.count == 1)
  }

  @Test func answersAnUnreadablePlanIdAsUnknownWithoutAskingTheService() async throws {
    let setup = try await setup()
    let response = try await apply(setup, planId: "not-a-plan", authorization: basic)

    #expect(response.status == .notFound)
    #expect(try object(response)["code"] as? String == "unknownPlan")
    #expect(await setup.service.applyRequests.isEmpty)
  }

  @Test(arguments: ["0", "255", "256", "abc", "005", "-1"])
  func refusesANumberThatIsNotAGroupFrom1Through254(_ number: String) async throws {
    let setup = try await setup()
    let response = try await apply(setup, number: number, authorization: basic)

    #expect(response.status == .badRequest)
    #expect(try object(response)["code"] as? String == "invalidScene")
    #expect(await setup.service.applyRequests.isEmpty)
  }

  // MARK: Scope, marker and media type

  @Test func refusesAControlClientBecauseAnApplyNeedsTheAdminScope() async throws {
    let setup = try await setup()
    let response = try await apply(setup, authorization: try await token(setup, scope: .control))

    #expect(response.status == .forbidden)
    #expect(try object(response)["code"] as? String == "forbidden")
    #expect(await setup.service.applyRequests.isEmpty)
  }

  @Test func acceptsAnAdminClient() async throws {
    let setup = try await setup()
    let response = try await apply(setup, authorization: try await token(setup, scope: .admin))

    #expect(response.status == .ok)
  }

  @Test func refusesACallWithNoCredential() async throws {
    let setup = try await setup()

    #expect(try await apply(setup, authorization: nil).status == .unauthorized)
    #expect(await setup.service.applyRequests.isEmpty)
  }

  @Test func refusesARequestWithoutTheExplicitRequestMarker() async throws {
    let setup = try await setup()
    let response = try await apply(setup, authorization: basic, marker: false)

    #expect(response.status == .forbidden)
    #expect(try object(response)["code"] as? String == "apiMarkerMissing")
    #expect(await setup.service.applyRequests.isEmpty)
  }

  @Test func refusesABodyThatIsNotJSON() async throws {
    let setup = try await setup()
    let response = try await apply(setup, authorization: basic, contentType: "text/plain")

    #expect(response.status == .unsupportedMediaType)
    #expect(await setup.service.applyRequests.isEmpty)
  }

  // MARK: Idempotency

  @Test func answersARepeatWithTheRecordedAnswerAndWritesOnce() async throws {
    let setup = try await setup()
    let first = try await apply(setup, authorization: basic, key: "apply-1")
    let second = try await apply(setup, authorization: basic, key: "apply-1")

    #expect(first.status == .ok)
    #expect(second.status == .ok)
    #expect(second.headers[.idempotentReplay] == "true")
    #expect(first.headers[.idempotentReplay] == nil)
    #expect(Array(first.body.readableBytesView) == Array(second.body.readableBytesView))
    #expect(await setup.service.applyRequests.count == 1)
  }

  @Test func recordsAnIncompleteAnswerAndRepeatsItWithoutWritingAgain() async throws {
    let setup = try await setup(outcomes: [.written, .unanswered])
    let first = try await apply(setup, authorization: basic, key: "apply-2")
    let second = try await apply(setup, authorization: basic, key: "apply-2")

    #expect(first.status == .badGateway)
    #expect(second.status == .badGateway)
    #expect(second.headers[.idempotentReplay] == "true")
    #expect(Array(first.body.readableBytesView).count == Array(second.body.readableBytesView).count)
    #expect(try object(second)["steps"] as? [[String: Any]] != nil)
    #expect(await setup.service.applyRequests.count == 1)
  }

  @Test func doesNotRecordARefusalThatWroteNothingSoTheRepeatMaySucceed() async throws {
    let setup = try await setup(failure: ServiceControlError.busy)
    _ = try await apply(setup, authorization: basic, key: "apply-3")
    _ = try await apply(setup, authorization: basic, key: "apply-3")

    #expect(await setup.service.applyRequests.count == 2)
  }

  @Test func refusesAKeyUsedForADifferentPlanOrConsent() async throws {
    let setup = try await setup()
    _ = try await apply(setup, authorization: basic, key: "apply-4")
    let other = try await apply(setup, planId: "sha256:\(String(repeating: "a", count: 64))", authorization: basic, key: "apply-4")
    let otherConsent = try await apply(setup, body: #"{"consent":{"writeLinkRecords":true,"readFingerprint":"sha256:\#(String(repeating: "b", count: 64))"}}"#, authorization: basic, key: "apply-4")

    #expect(try object(other)["code"] as? String == "idempotencyKeyReused")
    #expect(try object(otherConsent)["code"] as? String == "idempotencyKeyReused")
    #expect(await setup.service.applyRequests.count == 1)
  }

  @Test func refusesAMalformedIdempotencyKey() async throws {
    let setup = try await setup()
    let response = try await apply(setup, authorization: basic, key: "bad key!")

    #expect(try object(response)["code"] as? String == "invalidIdempotencyKey")
    #expect(await setup.service.applyRequests.isEmpty)
  }
}

/// The `scene` event of kind membership changed: published after a plan is applied, in whole or in part.
@Suite(.timeLimit(.minutes(1)))
struct SceneMembershipChangedEventTests {
  private func wire(_ event: ServiceEvent) throws -> [String: Any] {
    let frame = EventDTO(event, at: EventCursor(runID: "run1", sequence: 7))
    return try #require(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(frame)) as? [String: Any])
  }

  @Test func carriesTheSceneTheSourceAndWhetherEveryStepWasMade() throws {
    let moment = Date(timeIntervalSince1970: 1_800_000_000)
    let whole = try wire(.sceneChanged(SceneChanged(number: 4, source: .api, isComplete: true, firedAt: moment)))
    let partial = try wire(.sceneChanged(SceneChanged(number: 4, source: .api, isComplete: false, firedAt: moment)))

    #expect(whole["kind"] as? String == "scene")
    #expect(whole["change"] as? String == "membership")
    #expect(whole["scene"] as? Int == 4)
    #expect(whole["source"] as? String == "api")
    #expect(whole["isComplete"] as? Bool == true)
    #expect(partial["isComplete"] as? Bool == false)
    #expect(whole["firedAt"] as? String == ISO8601DateFormatter().string(from: moment))
    #expect(whole["sequence"] as? Int == 7)
  }

  @Test func carriesNoRunFieldsAndNoAddressSoNoClientReadsItAsARun() throws {
    let frame = try wire(.sceneChanged(SceneChanged(number: 4, source: .api, isComplete: true, firedAt: Date(timeIntervalSince1970: 1_800_000_000))))

    #expect(frame["action"] == nil)
    #expect(frame["acknowledged"] == nil)
    #expect(frame["unacknowledged"] == nil)
    #expect(frame["address"] == nil)
    #expect(frame["name"] == nil)
  }

  @Test func aRunKeepsItsShapeAndSaysNothingOfMembership() throws {
    let address = InsteonAddress(0x1A, 0x2B, 0x3C)
    let receipt = SceneReceipt(scene: 3, action: .on, acknowledged: [address], unacknowledged: [], isComplete: true, responderCount: 1, persistence: .saved)
    let frame = try wire(.scene(SceneRun(number: 3, name: nil, source: .api, action: .on, receipt: receipt, firedAt: Date(timeIntervalSince1970: 1_800_000_000))))

    #expect(frame["kind"] as? String == "scene")
    #expect(frame["change"] == nil)
    #expect(frame["action"] as? String == "on")
    #expect(frame["acknowledged"] as? [String] == ["1A.2B.3C"])
  }
}
