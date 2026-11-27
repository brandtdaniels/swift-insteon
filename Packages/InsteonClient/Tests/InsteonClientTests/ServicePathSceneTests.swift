import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonClient
import InsteonNetworking
import InsteonProtocol
import InsteonService
import Testing

/// What `GET /api/v1/scenes` answers for a modem with one scene it controls, one that a device
/// controls, a device the catalog does not describe, a device that was not read, a device with no
/// list to read and a record whose other half is missing. The keys are sorted as the route writes them.
private let sceneListing = json(
  #"""
  {"looseHalfLinks":[{"address":"11.22.33","data":[255,31,1],"endpoint":"0A.0B.0C","group":9,"role":"controller"}],"modemUnread":false,"scenes":[\#
  {"controller":"modem","halfLinks":[{"address":"11.22.33","data":[128,28,0],"endpoint":"4D.5E.6F","group":3,"role":"responder"}],"members":[\#
  {"address":"1A.2B.3C","bytes":[\#
  {"label":"On-level","name":"onLevel","perGroup":false,"position":1,"value":255,"valueName":"On","verification":"observed"},\#
  {"label":"Ramp rate","name":"rampRate","perGroup":false,"position":2,"value":31,"verification":"documented"},\#
  {"name":"group","perGroup":true,"position":3,"value":1,"verification":"inferred"}],"data":[255,31,1],"described":true},\#
  {"address":"7E.00.20","bytes":[],"data":[0,0,0],"described":false}],"number":3,"writable":true},\#
  {"controller":"4D.5E.6F","halfLinks":[],"members":[],"number":2,"writable":false}],\#
  "undescribedMembers":["7E.00.20"],"unlisted":["0A.0B.0C"],"unreadable":[{"address":"4D.5E.6F","reason":"rejectedModem"}],"version":1,"whole":false}
  """#)

private let wholeEmpty = json(#"{"looseHalfLinks":[],"modemUnread":false,"scenes":[],"undescribedMembers":[],"unlisted":[],"unreadable":[],"version":1,"whole":true}"#)

private let sceneReceipt = json(#"{"acknowledged":["1A.2B.3C"],"action":"on","isComplete":true,"outcome":"acknowledged","persistence":"saved","responderCount":2,"scene":3,"unacknowledged":["4D.5E.6F"],"version":1}"#)

private let token = "tok-3f9a0c-invented"
private let healthy = json(#"{"version":1,"status":"ready","modem":{"connected":true,"cause":null}}"#)

/// What the service answers a refused request with: its full error shape.
private func refusal(_ code: String, sent: Bool, cause: String? = nil, status: Int) -> HTTPResponse {
  let cause = cause.map { ",\"cause\":\"\($0)\"" } ?? ""
  return json(#"{"version":1,"code":"\#(code)","message":"Refused.","sent":\#(sent),"requestId":"r-1"\#(cause)}"#, status: status)
}

private func calls(_ http: FakeHTTPClient) async throws -> any ConnectionCalls {
  try await ServicePath(name: "lan", baseURL: URL(string: "http://192.0.2.20:8080")!, token: token, http: http).open()
}

/// A client whose health answer is `healthy` and whose other answers come from `answer`.
private func calls(_ answer: HTTPResponse) async throws -> (any ConnectionCalls, FakeHTTPClient) {
  let http = FakeHTTPClient { request in request.url?.path == "/api/v1/health" ? healthy : answer }
  return (try await calls(http), http)
}

@Suite("ServicePath reads and runs scenes", .timeLimit(.minutes(1)))
struct ServicePathSceneTests {

  // MARK: Listing

  @Test func theListingIsReadFromTheScenesRouteWithNoBodyAndNoMarker() async throws {
    let (c, http) = try await calls(wholeEmpty)

    _ = try await c.scenes()

    let request = try #require(await http.requests.last)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.path == "/api/v1/scenes")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer " + token)
    #expect(request.value(forHTTPHeaderField: "X-Insteon-Request") == nil)
    #expect(request.httpBody == nil)
  }

  @Test func aNetworkWithNoScenesIsAnEmptyWholeList() async throws {
    let (c, _) = try await calls(wholeEmpty)

    let list = try await c.scenes()

    #expect(list.scenes.isEmpty)
    #expect(list.isWhole)
    #expect(list.unreadable.isEmpty && list.unlisted.isEmpty && list.looseHalfLinks.isEmpty && list.undescribedMembers.isEmpty)
    #expect(!list.isModemUnread)
  }

  @Test func eachSceneCarriesItsNumberSourceWritableFlagAndMembers() async throws {
    let (c, _) = try await calls(sceneListing)

    let list = try await c.scenes()

    #expect(list.scenes.map(\.number) == [3, 2])
    #expect(list.scenes.map(\.source) == [.modem, .device(InsteonAddress(0x4D, 0x5E, 0x6F))])
    #expect(list.scenes.map(\.isWritable) == [true, false])
    #expect(list.scenes[0].members.map(\.address) == [lampAddress, InsteonAddress(0x7E, 0x00, 0x20)])
    #expect(list.scenes[1].members.isEmpty)
  }

  @Test func aDescribedMemberCarriesItsDataBytesAndWhatTheCatalogSaysEachMeans() async throws {
    let (c, _) = try await calls(sceneListing)

    let member = try #require(try await c.scenes().scenes.first?.members.first)

    #expect(member.data == [0xFF, 0x1F, 0x01])
    #expect(member.isDescribed)
    #expect(member.bytes.count == 3)
    #expect(member.bytes[0] == SceneList.Byte(position: 1, name: "onLevel", label: "On-level", value: 0xFF, valueName: "On", isPerGroup: false, verification: .observed))
    #expect(member.bytes[1] == SceneList.Byte(position: 2, name: "rampRate", label: "Ramp rate", value: 0x1F, valueName: nil, isPerGroup: false, verification: .documented))
    #expect(member.bytes[2] == SceneList.Byte(position: 3, name: "group", label: nil, value: 0x01, valueName: nil, isPerGroup: true, verification: .inferred))
  }

  @Test func anUndescribedMemberKeepsItsRawBytesWithNoMeaning() async throws {
    let (c, _) = try await calls(sceneListing)

    let list = try await c.scenes()
    let member = try #require(list.scenes.first?.members.last)

    #expect(member.data == [0, 0, 0])
    #expect(!member.isDescribed)
    #expect(member.bytes.isEmpty)
    #expect(list.undescribedMembers == [InsteonAddress(0x7E, 0x00, 0x20)])
  }

  @Test func whatCouldNotBeReadAndHalfLinksSayTheListIsNotWhole() async throws {
    let (c, _) = try await calls(sceneListing)

    let list = try await c.scenes()

    #expect(!list.isWhole)
    #expect(list.unreadable == [SceneList.UnreadableDevice(address: InsteonAddress(0x4D, 0x5E, 0x6F), reason: .rejectedModem)])
    #expect(list.unlisted == [InsteonAddress(0x0A, 0x0B, 0x0C)])
    #expect(list.scenes[0].halfLinks == [SceneList.HalfLink(endpoint: .device(InsteonAddress(0x4D, 0x5E, 0x6F)), group: 3, address: InsteonAddress(0x11, 0x22, 0x33), role: .responder, data: [128, 28, 0])])
    #expect(list.looseHalfLinks == [SceneList.HalfLink(endpoint: .device(InsteonAddress(0x0A, 0x0B, 0x0C)), group: 9, address: InsteonAddress(0x11, 0x22, 0x33), role: .controller, data: [255, 31, 1])])
  }

  @Test func everyReasonTheServiceGivesIsTypedAndOneItDoesNotKnowIsKeptByName() async throws {
    let table: [(String, SceneList.UnreadableReason)] = [
      ("noAnswer", .noAnswer), ("rejectedModem", .rejectedModem), ("damagedRecords", .damagedRecords), ("notCached", .notCached),
      ("unavailableFromSource", .unavailableFromSource), ("modemStoppedEchoing", .modemStoppedEchoing),
      ("hubStoppedAnswering", .hubStoppedAnswering), ("failed", .failed), ("incomplete", .incomplete), ("laterReason", .other("laterReason"))
    ]
    for (name, reason) in table {
      let body = #"{"looseHalfLinks":[],"modemUnread":true,"scenes":[],"undescribedMembers":[],"unlisted":[],"unreadable":[{"address":"1A.2B.3C","reason":"\#(name)"}],"version":1,"whole":false}"#
      let (c, _) = try await calls(json(body))

      let list = try await c.scenes()

      #expect(list.unreadable.map(\.reason) == [reason], "\(name)")
      #expect(list.isModemUnread)
    }
  }

  @Test func aVerificationTheClientDoesNotKnowIsKeptByName() async throws {
    let body = #"{"looseHalfLinks":[],"modemUnread":false,"scenes":[{"controller":"modem","halfLinks":[],"members":[{"address":"1A.2B.3C","bytes":[{"name":"onLevel","perGroup":false,"position":1,"value":255,"verification":"conflicting"},{"name":"x","perGroup":false,"position":2,"value":1,"verification":"later"}],"data":[255,1,1],"described":true}],"number":3,"writable":true}],"undescribedMembers":[],"unlisted":[],"unreadable":[],"version":1,"whole":true}"#
    let (c, _) = try await calls(json(body))

    let bytes = try #require(try await c.scenes().scenes.first?.members.first?.bytes)

    #expect(bytes.map(\.verification) == [.conflicting, .other("later")])
  }

  @Test func aListingThatBreaksTheContractIsABadResponseAndOneBadEntryFailsTheWholeList() async throws {
    let bodies = [
      "not json", "{}",
      #"{"looseHalfLinks":[],"modemUnread":false,"scenes":[{"controller":"nonsense","halfLinks":[],"members":[],"number":3,"writable":true}],"undescribedMembers":[],"unlisted":[],"unreadable":[],"version":1,"whole":true}"#,
      #"{"looseHalfLinks":[],"modemUnread":false,"scenes":[{"controller":"modem","halfLinks":[],"members":[{"address":"nonsense","bytes":[],"data":[0,0,0],"described":false}],"number":3,"writable":true}],"undescribedMembers":[],"unlisted":[],"unreadable":[],"version":1,"whole":true}"#,
      #"{"looseHalfLinks":[],"modemUnread":false,"scenes":[{"controller":"modem","halfLinks":[],"members":[{"address":"1A.2B.3C","bytes":[],"data":[0,0,300],"described":false}],"number":3,"writable":true}],"undescribedMembers":[],"unlisted":[],"unreadable":[],"version":1,"whole":true}"#,
      #"{"looseHalfLinks":[],"modemUnread":false,"scenes":[],"undescribedMembers":[],"unlisted":["nonsense"],"unreadable":[],"version":1,"whole":true}"#,
      #"{"looseHalfLinks":[{"address":"11.22.33","data":[1,2,3],"endpoint":"modem","group":9,"role":"sideways"}],"modemUnread":false,"scenes":[],"undescribedMembers":[],"unlisted":[],"unreadable":[],"version":1,"whole":true}"#
    ]
    for body in bodies {
      let (c, _) = try await calls(json(body))

      await #expect(throws: ConnectionPathError.badResponse, "\(body)") { _ = try await c.scenes() }
    }
  }

  @Test func aLostConnectionDuringTheListingIsInterruptedAndAnAnswerThatIsNotTheServiceIsABadResponse() async throws {
    let lost = try await calls(FakeHTTPClient { request in
      if request.url?.path == "/api/v1/health" { return healthy }
      throw Unplugged()
    })
    await #expect(throws: ConnectionPathError.interrupted) { _ = try await lost.scenes() }

    let (other, _) = try await calls(HTTPResponse(statusCode: 404, body: Data("<html>no</html>".utf8)))
    await #expect(throws: ConnectionPathError.badResponse) { _ = try await other.scenes() }
  }

  // MARK: Refreshing

  @Test func aRefreshIsPostedWithTheMarkerAndNoBodyAndAnswersTheListing() async throws {
    let (c, http) = try await calls(sceneListing)

    let list = try await c.refreshScenes()

    let request = try #require(await http.requests.last)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/api/v1/scenes/refresh")
    #expect(request.value(forHTTPHeaderField: "X-Insteon-Request") == "1")
    #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == nil)
    #expect(request.httpBody == nil)
    #expect(list.scenes.map(\.number) == [3, 2])
  }

  @Test func aRefreshLostInFlightIsInterruptedAndOneThatCannotBeReadIsABadResponse() async throws {
    let lost = try await calls(FakeHTTPClient { request in
      if request.url?.path == "/api/v1/health" { return healthy }
      throw Unplugged()
    })
    await #expect(throws: ConnectionPathError.interrupted) { _ = try await lost.refreshScenes() }

    let (garbled, _) = try await calls(json("{}"))
    await #expect(throws: ConnectionPathError.badResponse) { _ = try await garbled.refreshScenes() }
  }

  // MARK: Running

  @Test func aRunIsPostedAsJSONWithTheMarkerTheKeyAndTheAction() async throws {
    let (c, http) = try await calls(sceneReceipt)

    _ = try await c.runScene(3, action: .on, idempotencyKey: "run-1")

    let request = try #require(await http.requests.last)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/api/v1/scenes/3/commands")
    #expect(request.value(forHTTPHeaderField: "X-Insteon-Request") == "1")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == "run-1")
    #expect(request.httpBody.map { String(decoding: $0, as: UTF8.self) } == #"{"action":"on"}"#)
  }

  @Test func offIsSentAsOffAndTheNumberNamesTheScenesPath() async throws {
    let (c, http) = try await calls(sceneReceipt)

    _ = try await c.runScene(254, action: .off, idempotencyKey: "run-2")

    let request = try #require(await http.requests.last)
    #expect(request.url?.path == "/api/v1/scenes/254/commands")
    #expect(request.httpBody.map { String(decoding: $0, as: UTF8.self) } == #"{"action":"off"}"#)
  }

  @Test func theReceiptSaysWhoAcknowledgedWhoDidNotAndWhetherTheModemReachedThemAll() async throws {
    let (c, _) = try await calls(sceneReceipt)

    let receipt = try await c.runScene(3, action: .on, idempotencyKey: "run-1")

    #expect(receipt == SceneRunReceipt(
      scene: 3, action: .on, acknowledged: [lampAddress], unacknowledged: [InsteonAddress(0x4D, 0x5E, 0x6F)],
      isComplete: true, responderCount: 2, persistence: .saved))
  }

  @Test func aModemThatPassesNoPerMemberAcknowledgmentUpGivesAnEmptyListAndItsOwnReport() async throws {
    let silent = json(#"{"acknowledged":[],"action":"off","isComplete":false,"outcome":"acknowledged","persistence":"notConfigured","responderCount":2,"scene":3,"unacknowledged":[],"version":1}"#)
    let (c, _) = try await calls(silent)

    let receipt = try await c.runScene(3, action: .off, idempotencyKey: "run-1")

    #expect(receipt.acknowledged.isEmpty && receipt.unacknowledged.isEmpty)
    #expect(!receipt.isComplete)
    #expect(receipt.persistence == .notConfigured)
  }

  @Test func aRunLostAfterItWasSentIsInterruptedNeverNotReached() async throws {
    let c = try await calls(FakeHTTPClient { request in
      if request.url?.path == "/api/v1/health" { return healthy }
      throw Unplugged()
    })

    await #expect(throws: ConnectionPathError.interrupted) { _ = try await c.runScene(3, action: .on, idempotencyKey: "run-1") }
  }

  @Test func aRunAnswerThatCannotBeReadMayHaveTakenEffectSoItIsAnUnknownOutcomeNeverABadResponse() async throws {
    let bodies = [
      "{}",
      #"{"acknowledged":[],"action":"dim","isComplete":true,"outcome":"acknowledged","persistence":"saved","responderCount":2,"scene":3,"unacknowledged":[],"version":1}"#,
      #"{"acknowledged":[],"action":"on","isComplete":true,"outcome":"read","persistence":"saved","responderCount":2,"scene":3,"unacknowledged":[],"version":1}"#,
      #"{"acknowledged":[],"action":"on","isComplete":true,"outcome":"acknowledged","persistence":"someday","responderCount":2,"scene":3,"unacknowledged":[],"version":1}"#,
      #"{"acknowledged":["nonsense"],"action":"on","isComplete":true,"outcome":"acknowledged","persistence":"saved","responderCount":2,"scene":3,"unacknowledged":[],"version":1}"#
    ]
    for body in bodies {
      let (c, _) = try await calls(json(body))

      await #expect(throws: ConnectionError.outcomeUnknown(sent: true), "\(body)") { _ = try await c.runScene(3, action: .on, idempotencyKey: "run-1") }
    }
  }

  // MARK: Refusals

  @Test func theServicesSceneRefusalsBecomeTheServiceControlErrorsTheyAre() async throws {
    let table: [(String, Int, ServiceControlError)] = [
      ("unknownScene", 404, .unknownScene), ("sceneEmpty", 422, .sceneEmpty), ("busy", 409, .busy), ("databasesUnavailable", 422, .databasesUnavailable)
    ]
    for (code, status, expected) in table {
      let (c, _) = try await calls(refusal(code, sent: false, status: status))

      await #expect(throws: expected, "\(code) on a run") { _ = try await c.runScene(3, action: .on, idempotencyKey: "run-1") }
      await #expect(throws: expected, "\(code) on a refresh") { _ = try await c.refreshScenes() }
    }
  }

  @Test func aSceneNumberTheServiceRefusesIsInvalidScene() async throws {
    let (c, _) = try await calls(refusal("invalidScene", sent: false, status: 400))

    await #expect(throws: ConnectionError.invalidScene) { _ = try await c.runScene(0, action: .on, idempotencyKey: "run-1") }
  }

  @Test func aModemThatIsAwayKeepsItsCauseOnARunAndOnARefresh() async throws {
    let (c, _) = try await calls(refusal("modemUnavailable", sent: false, cause: "connecting", status: 503))

    await #expect(throws: ServiceControlError.modemUnavailable(.connecting)) { _ = try await c.runScene(3, action: .on, idempotencyKey: "run-1") }
    await #expect(throws: ServiceControlError.modemUnavailable(.connecting)) { _ = try await c.refreshScenes() }
  }

  @Test func anUnknownOutcomeSaysWhetherTheCommandWasSent() async throws {
    for sent in [true, false] {
      let (c, _) = try await calls(refusal("outcomeUnknown", sent: sent, status: 502))

      await #expect(throws: ConnectionError.outcomeUnknown(sent: sent)) { _ = try await c.runScene(3, action: .on, idempotencyKey: "run-1") }
    }
  }

  @Test func aCredentialRefusedOrWithTooLowAScopeIsUnauthorizedOrForbiddenOnEverySceneCall() async throws {
    for (status, expected) in [(401, ConnectionPathError.unauthorized), (403, ConnectionPathError.forbidden)] {
      let (c, _) = try await calls(refusal("authenticationFailed", sent: false, status: status))

      await #expect(throws: expected) { _ = try await c.scenes() }
      await #expect(throws: expected) { _ = try await c.refreshScenes() }
      await #expect(throws: expected) { _ = try await c.runScene(3, action: .on, idempotencyKey: "run-1") }
    }
  }

  @Test func aRefusalThisLibraryHasNoCaseForKeepsItsCodeAndWhetherAnythingWasSent() async throws {
    let (c, _) = try await calls(refusal("modemRejected", sent: false, status: 503))

    await #expect(throws: ConnectionError.rejected(code: "modemRejected", sent: false)) { _ = try await c.runScene(3, action: .on, idempotencyKey: "run-1") }
  }
}
