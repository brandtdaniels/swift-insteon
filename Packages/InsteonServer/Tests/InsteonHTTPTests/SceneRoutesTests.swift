import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import InsteonCore
import InsteonLinking
import InsteonModem
import InsteonProtocol
import InsteonService
import Testing
@testable import InsteonHTTP

/// `GET /api/v1/scenes`: the scenes of the network from the service's cache, for any reader.
@Suite(.timeLimit(.minutes(1)))
struct SceneRoutesTests {
  let password = String(repeating: "p", count: 40)
  private var basic: String { "Basic " + Data(("insteon:" + password).utf8).base64EncodedString() }

  let modemAddress = InsteonAddress(0x11, 0x22, 0x33)
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

  private func object(_ response: TestResponse) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
  }

  private func token(_ setup: Setup, scope: ClientScope) async throws -> String {
    "Bearer " + (try await setup.clients.issue(name: "Client", scope: scope)).token
  }

  private func fetch(_ setup: Setup, authorization: String?) async throws -> TestResponse {
    try await setup.app.test(.router) { client in
      try await client.execute(uri: "/api/v1/scenes", method: .get, headers: authorization.map { [.authorization: $0] } ?? [:])
    }
  }

  // MARK: Reading

  @Test func givesAReaderTheScenesAWritableOneWithItsMembersAndTheirDataBytes() async throws {
    let listing = SceneListing(scenes: [
      SceneListing.Scene(number: 3, controller: .modem, members: [SceneListing.Member(address: lamp, data: [0xFF, 0x1F, 0x01])])
    ])
    let setup = try Setup(password: password, service: FakeService(scenes: listing))
    let response = try await fetch(setup, authorization: try await token(setup, scope: .read))

    #expect(response.status == .ok)
    #expect(response.headers[.contentType] == "application/json")

    let body = try object(response)
    #expect(body["version"] as? Int == 1)
    #expect(body["whole"] as? Bool == true)
    #expect((body["unreadable"] as? [String])?.isEmpty == true)
    #expect((body["unlisted"] as? [String])?.isEmpty == true)

    let scene = try #require((body["scenes"] as? [[String: Any]])?.first)
    #expect(scene["number"] as? Int == 3)
    #expect(scene["controller"] as? String == "modem")
    #expect(scene["writable"] as? Bool == true)

    let member = try #require((scene["members"] as? [[String: Any]])?.first)
    #expect(member["address"] as? String == "1A.2B.3C")
    #expect(member["data"] as? [Int] == [0xFF, 0x1F, 0x01])
  }

  @Test func namesEachMembersDataBytesFromTheCatalogAndSaysHowSureTheCatalogIs() async throws {
    let listing = SceneListing(scenes: [
      SceneListing.Scene(number: 3, controller: .modem, members: [SceneListing.Member(address: lamp, data: [0xFF, 0x1F, 0x01])])
    ])
    let meaning = LinkDataMeaning(bytes: [
      LinkDataField(position: 1, name: "onLevel", label: "On-level", value: 0xFF, valueName: "On", verification: "observed"),
      LinkDataField(position: 2, name: "rampRate", label: "Ramp rate", value: 0x1F, verification: "documented"),
      LinkDataField(position: 3, name: "group", value: 0x01, isPerGroup: true, verification: "inferred")
    ])
    let setup = try Setup(password: password, service: FakeService(scenes: listing, memberMeanings: [lamp: meaning]))
    let body = try object(try await fetch(setup, authorization: basic))
    let scene = try #require((body["scenes"] as? [[String: Any]])?.first)
    let member = try #require((scene["members"] as? [[String: Any]])?.first)

    #expect(member["described"] as? Bool == true)
    let bytes = try #require(member["bytes"] as? [[String: Any]])
    #expect(bytes.count == 3)
    #expect(bytes[0]["name"] as? String == "onLevel")
    #expect(bytes[0]["label"] as? String == "On-level")
    #expect(bytes[0]["value"] as? Int == 255)
    #expect(bytes[0]["valueName"] as? String == "On")
    #expect(bytes[0]["verification"] as? String == "observed")
    #expect(bytes[1]["verification"] as? String == "documented")
    #expect(bytes[2]["verification"] as? String == "inferred")
    #expect(bytes[2]["perGroup"] as? Bool == true)
    #expect((body["undescribedMembers"] as? [String])?.isEmpty == true)
    #expect(member["data"] as? [Int] == [0xFF, 0x1F, 0x01])
  }

  @Test func listsAMemberTheCatalogDoesNotDescribeAsUndescribedWithItsRawBytes() async throws {
    let listing = SceneListing(scenes: [
      SceneListing.Scene(number: 3, controller: .modem, members: [SceneListing.Member(address: lamp, data: [0xFF, 0x1F, 0x01])]),
      SceneListing.Scene(number: 4, controller: .modem, members: [SceneListing.Member(address: lamp, data: [0x80, 0x1C, 0x00]), SceneListing.Member(address: keypad, data: [0x00, 0x00, 0x00])])
    ])
    let setup = try Setup(password: password, service: FakeService(scenes: listing))
    let body = try object(try await fetch(setup, authorization: basic))
    let members = try #require((body["scenes"] as? [[String: Any]])?.flatMap { $0["members"] as? [[String: Any]] ?? [] })

    #expect(members.allSatisfy { $0["described"] as? Bool == false })
    #expect(members.allSatisfy { ($0["bytes"] as? [Any])?.isEmpty == true })
    #expect(members.first?["data"] as? [Int] == [0xFF, 0x1F, 0x01])
    #expect(body["undescribedMembers"] as? [String] == ["1A.2B.3C", "4D.5E.6F"])
  }

  @Test func asksTheServiceWhatEachMembersBytesMeanForTheScenesGroup() async throws {
    let listing = SceneListing(scenes: [
      SceneListing.Scene(number: 7, controller: .device(keypad), members: [SceneListing.Member(address: lamp, data: [0x80, 0x1C, 0x00])])
    ])
    let setup = try Setup(password: password, service: FakeService(scenes: listing))
    _ = try await fetch(setup, authorization: basic)

    let asked = await setup.service.askedMeanings
    #expect(asked == [FakeService.MeaningQuestion(device: lamp, data: [0x80, 0x1C, 0x00], group: 7)])
  }

  @Test func asksOnceForMembersWithTheSameDeviceBytesAndGroup() async throws {
    let twice = SceneListing.Member(address: lamp, data: [0x80, 0x1C, 0x00])
    let listing = SceneListing(scenes: [SceneListing.Scene(number: 5, controller: .modem, members: [twice, twice])])
    let setup = try Setup(password: password, service: FakeService(scenes: listing))
    _ = try await fetch(setup, authorization: basic)

    #expect(await setup.service.askedMeanings.count == 1)
  }

  @Test func listsASceneADeviceControlsAsReadOnlyNamedByTheDevicesAddress() async throws {
    let listing = SceneListing(scenes: [
      SceneListing.Scene(number: 2, controller: .device(keypad), members: [SceneListing.Member(address: lamp, data: [0x80, 0x1C, 0x00])])
    ])
    let setup = try Setup(password: password, service: FakeService(scenes: listing))
    let scene = try #require((try object(try await fetch(setup, authorization: basic))["scenes"] as? [[String: Any]])?.first)

    #expect(scene["controller"] as? String == "4D.5E.6F")
    #expect(scene["writable"] as? Bool == false)
  }

  @Test func saysWhatItCouldNotReadAndAHalfLinkSoTheListingIsNotWhole() async throws {
    let halfLink = AllLinkGroupReading.HalfLink(endpoint: .device(lamp), record: AllLinkRecord(flags: [.inUse], group: 4, address: modemAddress, data1: 0xFF, data2: 0x1F, data3: 0x01))
    let listing = SceneListing(
      scenes: [SceneListing.Scene(number: 4, controller: .modem, halfLinks: [halfLink])],
      unreadable: [keypad],
      unlisted: [InsteonAddress(0x0A, 0x0B, 0x0C)]
    )
    let setup = try Setup(password: password, service: FakeService(scenes: listing))
    let body = try object(try await fetch(setup, authorization: basic))

    #expect(body["whole"] as? Bool == false)
    #expect(body["unreadable"] as? [String] == ["4D.5E.6F"])
    #expect(body["unlisted"] as? [String] == ["0A.0B.0C"])

    let scene = try #require((body["scenes"] as? [[String: Any]])?.first)
    let found = try #require((scene["halfLinks"] as? [[String: Any]])?.first)
    #expect(found["endpoint"] as? String == "1A.2B.3C")
    #expect(found["group"] as? Int == 4)
    #expect(found["address"] as? String == "11.22.33")
    #expect(found["role"] as? String == "responder")
    #expect(found["data"] as? [Int] == [0xFF, 0x1F, 0x01])
  }

  @Test func listsNoScenesForAHomeWithNone() async throws {
    let setup = try Setup(password: password, service: FakeService(scenes: SceneListing(scenes: [])))
    let body = try object(try await fetch(setup, authorization: basic))

    #expect((body["scenes"] as? [Any])?.isEmpty == true)
    #expect(body["whole"] as? Bool == true)
  }

  @Test func answersFromTheCacheAndAsksTheServiceOnceForEachRequest() async throws {
    let setup = try Setup(password: password, service: FakeService(scenes: SceneListing(scenes: [])))
    _ = try await fetch(setup, authorization: basic)
    _ = try await fetch(setup, authorization: basic)

    #expect(await setup.service.sceneReads == 2)
    #expect(await setup.service.commands.isEmpty)
  }

  @Test func writesTheKeysInSortedOrderSoTheSameHomeGivesTheSameBytes() async throws {
    let setup = try Setup(password: password, service: FakeService(scenes: SceneListing(scenes: [])))
    let text = String(decoding: try await fetch(setup, authorization: basic).body.readableBytesView, as: UTF8.self)
    let keys = ["looseHalfLinks", "modemUnread", "scenes", "unlisted", "unreadable", "version", "whole"]
    let positions = keys.map { text.range(of: "\"\($0)\"")?.lowerBound }

    #expect(!positions.contains { $0 == nil })
    #expect(positions.compactMap { $0 } == positions.compactMap { $0 }.sorted())
  }

  // MARK: Authentication

  @Test func refusesACallWithNoCredential() async throws {
    let setup = try Setup(password: password, service: FakeService(scenes: SceneListing(scenes: [])))
    let response = try await fetch(setup, authorization: nil)

    #expect(response.status == .unauthorized)
    #expect(await setup.service.sceneReads == 0)
  }

  @Test func declaresTheReadScopeAndTheErrorsEveryAuthenticatedRouteHas() {
    #expect(APIOperation.listScenes.requiredScope == .read)
    #expect(APIOperation.listScenes.method == .get)
    #expect(APIOperation.listScenes.path == "/api/v1/scenes")
    #expect(APIOperation.listScenes.errorCodes.contains(.authenticationRequired))
  }

  // MARK: Refreshing

  private func refresh(_ setup: Setup, authorization: String?, marker: Bool = true) async throws -> TestResponse {
    var fields: HTTPFields = authorization.map { [.authorization: $0] } ?? [:]
    if marker { fields[HTTPField.Name("X-Insteon-Request")!] = "1" }
    let headers = fields
    return try await setup.app.test(.router) { client in
      try await client.execute(uri: "/api/v1/scenes/refresh", method: .post, headers: headers)
    }
  }

  private var oneScene: SceneListing {
    SceneListing(scenes: [SceneListing.Scene(number: 3, controller: .modem, members: [SceneListing.Member(address: lamp, data: [0xFF, 0x1F, 0x01])])])
  }

  @Test func letsAControlClientRefreshAndAnswersWithTheListingAGetGives() async throws {
    let setup = try Setup(password: password, service: FakeService(scenes: oneScene))
    let response = try await refresh(setup, authorization: try await token(setup, scope: .control))
    let listed = try await fetch(setup, authorization: try await token(setup, scope: .read))

    #expect(response.status == .ok)
    #expect(response.headers[.contentType] == "application/json")
    #expect(Array(response.body.readableBytesView) == Array(listed.body.readableBytesView))
    #expect(await setup.service.refreshes == 1)
    let scene = try #require((try object(response)["scenes"] as? [[String: Any]])?.first)
    #expect(scene["number"] as? Int == 3)
  }

  @Test func namesEachMembersBytesInTheRefreshedListingAsAGetDoes() async throws {
    let meaning = LinkDataMeaning(bytes: [LinkDataField(position: 1, name: "onLevel", value: 0xFF, verification: "observed")])
    let setup = try Setup(password: password, service: FakeService(scenes: oneScene, memberMeanings: [lamp: meaning]))
    let member = try #require(((try object(try await refresh(setup, authorization: basic))["scenes"] as? [[String: Any]])?.first?["members"] as? [[String: Any]])?.first)

    #expect(member["described"] as? Bool == true)
    #expect((member["bytes"] as? [[String: Any]])?.first?["name"] as? String == "onLevel")
  }

  @Test func sendsNoDeviceCommandWhenItRefreshes() async throws {
    let setup = try Setup(password: password, service: FakeService(scenes: oneScene))
    _ = try await refresh(setup, authorization: basic)

    #expect(await setup.service.commands.isEmpty)
  }

  @Test func refusesAReadClientBeforeTheServiceIsAsked() async throws {
    let setup = try Setup(password: password, service: FakeService(scenes: oneScene))
    let response = try await refresh(setup, authorization: try await token(setup, scope: .read))

    #expect(response.status == .forbidden)
    #expect(try object(response)["code"] as? String == "forbidden")
    #expect(await setup.service.refreshes == 0)
  }

  @Test func refusesACallWithNoCredentialToRefresh() async throws {
    let setup = try Setup(password: password, service: FakeService(scenes: oneScene))
    let response = try await refresh(setup, authorization: nil)

    #expect(response.status == .unauthorized)
    #expect(await setup.service.refreshes == 0)
  }

  @Test func refusesARefreshWithoutTheExplicitRequestMarker() async throws {
    let setup = try Setup(password: password, service: FakeService(scenes: oneScene))
    let response = try await refresh(setup, authorization: basic, marker: false)

    #expect(response.status == .forbidden)
    #expect(try object(response)["code"] as? String == "apiMarkerMissing")
    #expect(await setup.service.refreshes == 0)
  }

  @Test(arguments: [
    (ServiceControlError.busy, 409, "busy"),
    (ServiceControlError.modemUnavailable(.hubUnreachable), 503, "modemUnavailable"),
    (ServiceControlError.databasesUnavailable, 422, "databasesUnavailable")
  ])
  func answersARefusalWithItsTypedErrorAndSaysNothingWasSent(_ failure: ServiceControlError, _ status: Int, _ code: String) async throws {
    let setup = try Setup(password: password, service: FakeService(scenes: oneScene, refreshFailure: failure))
    let response = try await refresh(setup, authorization: basic)
    let body = try object(response)

    #expect(Int(response.status.code) == status)
    #expect(body["code"] as? String == code)
    #expect(body["sent"] as? Bool == false)
    #expect(await setup.service.refreshes == 1)
  }

  @Test func answersALostConnectionAsAReadThatIsSafeToRepeat() async throws {
    let setup = try Setup(password: password, service: FakeService(scenes: oneScene, refreshFailure: ModemError.connectionClosed))
    let response = try await refresh(setup, authorization: basic)
    let body = try object(response)

    #expect(response.status == .gatewayTimeout)
    #expect(body["code"] as? String == "deviceNotAnswering")
    #expect(body["sent"] as? Bool == false)
  }

  @Test func answersACanceledRefreshAsUnavailableWithNothingSent() async throws {
    let setup = try Setup(password: password, service: FakeService(scenes: oneScene, refreshFailure: CancellationError()))
    let body = try object(try await refresh(setup, authorization: basic))

    #expect(body["code"] as? String == "canceled")
    #expect(body["sent"] as? Bool == false)
  }

  @Test func saysAHubProDoesNotGiveOutItsDatabases() async throws {
    let setup = try Setup(password: password, service: FakeService(refreshFailure: ServiceControlError.databasesUnavailable))
    let message = try #require(try object(try await refresh(setup, authorization: basic))["message"] as? String)

    #expect(message.contains("Hub Pro"))
    #expect(message.contains("ALL-Link databases"))
  }

  @Test func declaresTheControlScopeAPostWithNoBodyAndTheSceneListAsItsAnswer() {
    let operation = APIOperation.refreshScenes
    #expect(operation.requiredScope == .control)
    #expect(operation.method == .post)
    #expect(operation.path == "/api/v1/scenes/refresh")
    #expect(operation.requestBody == nil)
    #expect(operation.errorCodes.contains(.forbidden))
    #expect(operation.errorCodes.contains(.busy))
    #expect(operation.errorCodes.contains(.modemUnavailable))
    #expect(operation.errorCodes.contains(.databasesUnavailable))
    #expect(operation.replies.first?.schema == APIOperation.listScenes.replies.first?.schema)
  }
}
