import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import InsteonCore
import InsteonLinking
import InsteonProtocol
import InsteonService
import Testing
@testable import InsteonHTTP

/// `GET /api/v1/scenes`: the scenes of the home from the service's cache, for any reader.
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
}
