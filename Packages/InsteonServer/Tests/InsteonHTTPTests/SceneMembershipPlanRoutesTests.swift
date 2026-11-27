import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import InsteonCore
import InsteonDeviceCatalog
import InsteonModem
import InsteonProtocol
import InsteonService
import Testing
@testable import InsteonHTTP

/// Plans made from a made-up catalog and cached databases, as the service would answer them.
enum ScenePlanExample {
  static let modem = InsteonAddress(0x11, 0x22, 0x33)
  static let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)
  static let stale = InsteonAddress(0x4D, 0x5E, 0x6F)
  static let expiresAt = Date(timeIntervalSince1970: 1_800_000_300)

  private static let identity = ReportedIdentity(category: 0x01, subcategory: 0x7D, firmwareVersion: 0x45)

  private static let catalog: DeviceCatalog = {
    let load = GroupType(
      name: "load",
      label: "Load",
      kind: .dimmer,
      linkData: GroupType.LinkData(responder: [
        LinkDataByte(position: 1, name: "onLevel", summary: "The on-level."),
        LinkDataByte(position: 2, name: "rampRate", summary: "The ramp rate."),
        LinkDataByte(position: 3, name: "button", summary: "The device's own group.", isPerGroup: true)
      ])
    )
    let profile = DeviceProfile(
      model: "9001",
      name: "Example Dimmer",
      identities: [DeviceIdentity(category: 0x01, subcategory: 0x7D)],
      engines: [DeviceEngine(engine: .i2cs, category: 0x01, subcategory: 0x7D)],
      commandSets: [CommandSetEntry(commandSet: "madeUpDimmer", category: 0x01, subcategory: 0x7D)],
      groups: [.init(number: 1, name: "Load", role: .responder, type: "load")]
    )
    return DeviceCatalog(profiles: [profile], commandSets: [CommandSet(id: "madeUpDimmer", name: "Made-Up Dimmer", summary: "A made-up command set.", groupTypes: [load])])
  }()

  private static func record(_ role: BackupRecordRole, group: UInt8, _ address: InsteonAddress, data: [UInt8] = [0xFF, 0x1F, 0x01], memory: UInt16? = nil, state: BackupRecordState = .inUse) -> BackupRecord {
    BackupRecord(state: state, role: role, group: group, address: address, data: data, memoryAddress: memory)
  }

  /// The plan for `change`: the lamp's database holds one record of the modem (group 9), a free slot and the end.
  static func plan(_ change: SceneMembershipChange, lampRecords: [BackupRecord]? = nil, modemRecords: [BackupRecord] = []) async -> SceneMembershipPlan {
    let held = lampRecords ?? [
      record(.responder, group: 9, modem, memory: 0x0FFF),
      record(.responder, group: 0, InsteonAddress(0, 0, 0), data: [0, 0, 0], memory: 0x0FF7, state: .free),
      record(.responder, group: 0, InsteonAddress(0, 0, 0), data: [0, 0, 0], memory: 0x0FEF, state: .end)
    ]
    let backup = NetworkBackup(
      createdAt: Date(timeIntervalSince1970: 1_800_000_000),
      source: .service,
      modem: BackupModem(address: modem, allLinkDatabase: modemRecords),
      devices: [
        BackupDevice(address: lamp, identity: BackupIdentity(identity), engine: .i2cs, allLinkDatabase: BackupDatabase(delta: 1, records: held)),
        BackupDevice(address: stale, unreadable: BackupUnreadable(reason: .notCached))
      ]
    )
    let registry = DeviceRegistry(catalog: catalog, snapshot: DeviceRegistrySnapshot(identities: [lamp: identity]))
    let devices: [InsteonAddress: RegisteredDevice] = await registry.device(lamp).map { [lamp: $0] } ?? [:]
    return SceneMembershipPlanner.plan(change, from: backup, devices: devices, modemLinkData: nil)
  }

  static func receipt(_ change: SceneMembershipChange, lampRecords: [BackupRecord]? = nil, modemRecords: [BackupRecord] = []) async -> SceneMembershipPlanReceipt {
    SceneMembershipPlanReceipt(plan: await plan(change, lampRecords: lampRecords, modemRecords: modemRecords), expiresAt: expiresAt)
  }

  static func addLamp(scene: UInt8 = 4) -> SceneMembershipChange {
    SceneMembershipChange(scene: scene, additions: [.init(device: lamp, onLevel: 0xFF, rampRate: 0x1F)], removals: [])!
  }
}

/// `POST /api/v1/scenes/{number}/plans`: what adding and removing members would write,
/// from the cache and the catalog, with nothing sent.
@Suite(.timeLimit(.minutes(1)))
struct SceneMembershipPlanRoutesTests {
  let password = String(repeating: "p", count: 40)
  private var basic: String { "Basic " + Data(("insteon:" + password).utf8).base64EncodedString() }

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

  private func plan(_ setup: Setup, number: String = "4", body: String = #"{"add":[{"device":"1A.2B.3C","onLevel":255,"rampRate":31}],"remove":["4D.5E.6F"]}"#, authorization: String?, marker: Bool = true, contentType: String = "application/json") async throws -> TestResponse {
    var fields: HTTPFields = authorization.map { [.authorization: $0] } ?? [:]
    fields[.contentType] = contentType
    if marker { fields[HTTPField.Name("X-Insteon-Request")!] = "1" }
    let headers = fields
    return try await setup.app.test(.router) { client in
      try await client.execute(uri: "/api/v1/scenes/\(number)/plans", method: .post, headers: headers, body: ByteBuffer(string: body))
    }
  }

  private func setup(_ receipt: SceneMembershipPlanReceipt) throws -> Setup {
    try Setup(password: password, service: FakeService(membershipReceipt: receipt))
  }

  // MARK: The plan

  @Test func answersTheOrderedStepsWithTheRecordsAndTheDataBytesEachWouldWrite() async throws {
    let setup = try setup(await ScenePlanExample.receipt(ScenePlanExample.addLamp()))
    let response = try await plan(setup, body: #"{"add":[{"device":"1A.2B.3C","onLevel":255,"rampRate":31}]}"#, authorization: try await token(setup, scope: .admin))
    let body = try object(response)
    let steps = try #require(body["steps"] as? [[String: Any]])

    #expect(response.status == .ok)
    #expect(response.headers[.contentType] == "application/json")
    #expect(body["version"] as? Int == 1)
    #expect(body["scene"] as? Int == 4)
    #expect(body["isApplicable"] as? Bool == true)
    #expect(body["isEmpty"] as? Bool == false)
    #expect(steps.map { $0["order"] as? Int } == [1, 2])
    #expect(steps.map { $0["kind"] as? String } == ["addDeviceRecord", "addModemRecord"])
    #expect(steps.map { $0["target"] as? String } == ["1A.2B.3C", "modem"])
    #expect(steps.map { $0["effect"] as? String } == ["write", "write"])
    #expect(steps.map { $0["updateInPlace"] as? Bool } == [false, false])
    let deviceRecord = try #require(steps[0]["record"] as? [String: Any])
    #expect(deviceRecord["role"] as? String == "responder")
    #expect(deviceRecord["group"] as? Int == 4)
    #expect(deviceRecord["address"] as? String == "11.22.33")
    #expect(deviceRecord["data"] as? [Int] == [255, 31, 1])
    #expect(deviceRecord["memoryAddress"] as? String == "0x0FF7")
    let modemRecord = try #require(steps[1]["record"] as? [String: Any])
    #expect(modemRecord["role"] as? String == "controller")
    #expect(modemRecord["address"] as? String == "1A.2B.3C")
    #expect(modemRecord["memoryAddress"] is NSNull)
  }

  @Test func answersThePlanIdItsExpiryAndTheConsentTheApplyStepWillNeed() async throws {
    let receipt = await ScenePlanExample.receipt(ScenePlanExample.addLamp())
    let setup = try setup(receipt)
    let body = try object(try await plan(setup, authorization: basic))
    let consent = try #require(body["consent"] as? [String: Any])

    #expect(body["planId"] as? String == receipt.plan.id)
    #expect((body["planId"] as? String)?.hasPrefix("sha256:") == true)
    #expect(body["expiresAt"] as? String == ISO8601DateFormatter().string(from: ScenePlanExample.expiresAt))
    #expect(consent["writeLinkRecords"] as? Bool == true)
    #expect(consent["readFingerprint"] as? String == receipt.plan.fingerprint)
  }

  @Test func tellsWhetherEachDeviceAcceptsARemoteWriteAndWhatItIs() async throws {
    let setup = try setup(await ScenePlanExample.receipt(ScenePlanExample.addLamp()))
    let body = try object(try await plan(setup, authorization: basic))
    let devices = try #require(body["devices"] as? [[String: Any]])

    #expect(devices.count == 1)
    #expect(devices[0]["address"] as? String == "1A.2B.3C")
    #expect(devices[0]["acceptsRemoteWrite"] as? Bool == true)
    #expect(devices[0]["engine"] as? String == "i2cs")
    #expect(devices[0]["product"] as? String != nil)
  }

  @Test func passesAMembersGroupToTheService() async throws {
    let setup = try setup(await ScenePlanExample.receipt(ScenePlanExample.addLamp()))
    _ = try await plan(setup, body: #"{"add":[{"device":"1A.2B.3C","group":2}]}"#, authorization: basic)

    #expect(await setup.service.membershipRequests.first?.additions.first?.group == 2)
  }

  @Test func passesTheChangeToTheServiceAsAskedWithNoDefaultsFilledIn() async throws {
    let setup = try setup(await ScenePlanExample.receipt(ScenePlanExample.addLamp()))
    _ = try await plan(setup, number: "9", body: #"{"add":[{"device":"1A.2B.3C","onLevel":128},{"device":"7A.8B.9C","rampRate":28}],"remove":["4D.5E.6F"]}"#, authorization: basic)

    #expect(await setup.service.membershipRequests == [
      SceneMembershipChange(scene: 9, additions: [
        .init(device: InsteonAddress(0x1A, 0x2B, 0x3C), onLevel: 128, rampRate: nil),
        .init(device: InsteonAddress(0x7A, 0x8B, 0x9C), onLevel: nil, rampRate: 28)
      ], removals: [InsteonAddress(0x4D, 0x5E, 0x6F)])
    ])
  }

  @Test func leavesTheDevicesAChangeNamesTwiceOrInBothListsToThePlannerToRefuse() async throws {
    let setup = try setup(await ScenePlanExample.receipt(ScenePlanExample.addLamp()))
    let body = #"{"add":[{"device":"1A.2B.3C","group":1},{"device":"1A.2B.3C","group":2}],"remove":["1A.2B.3C","1A.2B.3C"]}"#
    let response = try await plan(setup, body: body, authorization: basic)

    #expect(response.status == .ok)
    #expect(await setup.service.membershipRequests == [
      SceneMembershipChange(scene: 4, additions: [
        .init(device: ScenePlanExample.lamp, onLevel: nil, rampRate: nil, group: 1),
        .init(device: ScenePlanExample.lamp, onLevel: nil, rampRate: nil, group: 2)
      ], removals: [ScenePlanExample.lamp, ScenePlanExample.lamp])
    ])
  }

  @Test func answersAnUnknownGroupRefusalForAGroupTheCatalogDoesNotGiveTheDevice() async throws {
    let change = SceneMembershipChange(scene: 4, additions: [.init(device: ScenePlanExample.lamp, onLevel: 255, rampRate: 31, group: 9)], removals: [])!
    let setup = try setup(await ScenePlanExample.receipt(change))
    let body = try object(try await plan(setup, authorization: basic))
    let refusals = try #require(body["refusals"] as? [[String: Any]])

    #expect(refusals.map { $0["code"] as? String } == ["unknownGroup"])
    #expect(body["isApplicable"] as? Bool == false)
  }

  @Test func answersARefusalForADeviceWhoseDatabaseIsNotCachedWithTheHintToRefresh() async throws {
    let change = SceneMembershipChange(scene: 4, additions: [.init(device: ScenePlanExample.stale, onLevel: 255, rampRate: 31)], removals: [])!
    let setup = try setup(await ScenePlanExample.receipt(change))
    let body = try object(try await plan(setup, authorization: basic))
    let refusals = try #require(body["refusals"] as? [[String: Any]])

    #expect(body["isApplicable"] as? Bool == false)
    #expect((body["steps"] as? [Any])?.isEmpty == true)
    #expect(body["consent"] is NSNull)
    #expect(refusals.count == 1)
    #expect(refusals[0]["code"] as? String == "databaseNotCached")
    #expect(refusals[0]["device"] as? String == "4D.5E.6F")
    #expect((refusals[0]["detail"] as? String)?.contains("Refresh") == true)
  }

  @Test func listsAChangedLevelAsAnUpdateInPlaceAndRefusesItAsNotYetSupported() async throws {
    let change = SceneMembershipChange(scene: 4, additions: [.init(device: ScenePlanExample.lamp, onLevel: 128, rampRate: 31)], removals: [])!
    let held = [
      BackupRecord(state: .inUse, role: .responder, group: 4, address: ScenePlanExample.modem, data: [255, 31, 1], memoryAddress: 0x0FFF),
      BackupRecord(state: .end, role: .responder, group: 0, address: InsteonAddress(0, 0, 0), data: [0, 0, 0], memoryAddress: 0x0FF7)
    ]
    let modemRecords = [BackupRecord(state: .inUse, role: .controller, group: 4, address: ScenePlanExample.lamp, data: [0, 0, 0])]
    let setup = try setup(await ScenePlanExample.receipt(change, lampRecords: held, modemRecords: modemRecords))
    let body = try object(try await plan(setup, authorization: basic))
    let steps = try #require(body["steps"] as? [[String: Any]])
    let refusals = try #require(body["refusals"] as? [[String: Any]])

    #expect(steps.map { $0["kind"] as? String } == ["updateDeviceRecord"])
    #expect(steps.first?["updateInPlace"] as? Bool == true)
    #expect(refusals.map { $0["code"] as? String } == ["notYetSupported"])
    #expect(body["isApplicable"] as? Bool == false)
  }

  @Test func answersAWarningAndNoStepForAMemberAlreadyInTheScene() async throws {
    let held = [
      BackupRecord(state: .inUse, role: .responder, group: 4, address: ScenePlanExample.modem, data: [255, 31, 1], memoryAddress: 0x0FFF),
      BackupRecord(state: .end, role: .responder, group: 0, address: InsteonAddress(0, 0, 0), data: [0, 0, 0], memoryAddress: 0x0FF7)
    ]
    let modemRecords = [BackupRecord(state: .inUse, role: .controller, group: 4, address: ScenePlanExample.lamp, data: [0, 0, 0])]
    let setup = try setup(await ScenePlanExample.receipt(ScenePlanExample.addLamp(), lampRecords: held, modemRecords: modemRecords))
    let body = try object(try await plan(setup, authorization: basic))
    let warnings = try #require(body["warnings"] as? [[String: Any]])

    #expect((body["steps"] as? [Any])?.isEmpty == true)
    #expect(body["isEmpty"] as? Bool == true)
    #expect(body["consent"] is NSNull)
    #expect(warnings.map { $0["code"] as? String } == ["alreadyMember"])
  }

  // MARK: Scope, marker and input

  @Test func refusesAReadClientBeforeTheServiceIsAsked() async throws {
    let setup = try setup(await ScenePlanExample.receipt(ScenePlanExample.addLamp()))
    let response = try await plan(setup, authorization: try await token(setup, scope: .read))

    #expect(response.status == .forbidden)
    #expect(try object(response)["code"] as? String == "forbidden")
    #expect(await setup.service.membershipRequests.isEmpty)
  }

  @Test func refusesAControlClientBecauseAPlanNeedsTheAdminScope() async throws {
    let setup = try setup(await ScenePlanExample.receipt(ScenePlanExample.addLamp()))
    let response = try await plan(setup, authorization: try await token(setup, scope: .control))

    #expect(response.status == .forbidden)
    #expect(try object(response)["code"] as? String == "forbidden")
    #expect(await setup.service.membershipRequests.isEmpty)
  }

  @Test func refusesACallWithNoCredential() async throws {
    let setup = try setup(await ScenePlanExample.receipt(ScenePlanExample.addLamp()))

    #expect(try await plan(setup, authorization: nil).status == .unauthorized)
    #expect(await setup.service.membershipRequests.isEmpty)
  }

  @Test func refusesARequestWithoutTheExplicitRequestMarker() async throws {
    let setup = try setup(await ScenePlanExample.receipt(ScenePlanExample.addLamp()))
    let response = try await plan(setup, authorization: basic, marker: false)

    #expect(response.status == .forbidden)
    #expect(try object(response)["code"] as? String == "apiMarkerMissing")
    #expect(await setup.service.membershipRequests.isEmpty)
  }

  @Test func refusesABodyThatIsNotJSON() async throws {
    let setup = try setup(await ScenePlanExample.receipt(ScenePlanExample.addLamp()))
    let response = try await plan(setup, authorization: basic, contentType: "text/plain")

    #expect(response.status == .unsupportedMediaType)
    #expect(await setup.service.membershipRequests.isEmpty)
  }

  @Test(arguments: ["0", "255", "256", "-1", "abc", "005", "+5", "٣"])
  func refusesANumberThatIsNotAGroupFrom1Through254(_ number: String) async throws {
    let setup = try setup(await ScenePlanExample.receipt(ScenePlanExample.addLamp()))
    let response = try await plan(setup, number: number, authorization: basic)

    #expect(response.status == .badRequest)
    #expect(try object(response)["code"] as? String == "invalidScene")
    #expect(try object(response)["sent"] as? Bool == false)
    #expect(await setup.service.membershipRequests.isEmpty)
  }

  @Test(arguments: [
    "{}",
    #"{"add":[],"remove":[]}"#,
    "not json",
    "[]",
    #"{"add":[{"device":"1A.2B.3C"}],"extra":1}"#,
    #"{"add":[{"device":"1A.2B.3C","level":1}]}"#,
    #"{"add":[{"onLevel":1}]}"#,
    #"{"add":[{"device":"1A.2B.3C","onLevel":256}]}"#,
    #"{"add":[{"device":"1A.2B.3C","onLevel":-1}]}"#,
    #"{"add":[{"device":"1A.2B.3C","rampRate":"fast"}]}"#,
    #"{"add":[{"device":"1A.2B.3C","onLevel":1.5}]}"#,
    #"{"add":[{"device":"1A.2B.3C","group":0}]}"#,
    #"{"add":[{"device":"1A.2B.3C","group":256}]}"#,
    #"{"add":[{"device":"1A.2B.3C","group":"1"}]}"#,
    #"{"add":"1A.2B.3C"}"#,
    #"{"remove":[5]}"#
  ])
  func refusesAChangeThatIsNotAnAddAndARemoveList(_ body: String) async throws {
    let setup = try setup(await ScenePlanExample.receipt(ScenePlanExample.addLamp()))
    let response = try await plan(setup, body: body, authorization: basic)

    #expect(response.status == .badRequest)
    #expect(try object(response)["code"] as? String == "invalidMembership")
    #expect(try object(response)["sent"] as? Bool == false)
    #expect(await setup.service.membershipRequests.isEmpty)
  }

  @Test func refusesAnAddressThatIsNotAnInsteonAddress() async throws {
    let setup = try setup(await ScenePlanExample.receipt(ScenePlanExample.addLamp()))
    let response = try await plan(setup, body: #"{"remove":["not an address"]}"#, authorization: basic)

    #expect(response.status == .badRequest)
    #expect(try object(response)["code"] as? String == "invalidAddress")
    #expect(await setup.service.membershipRequests.isEmpty)
  }

  @Test func refusesMoreThanThirtyTwoMembersInOneChange() async throws {
    let setup = try setup(await ScenePlanExample.receipt(ScenePlanExample.addLamp()))
    let many = (0..<33).map { #"{"device":"1A.2B.\#(String(format: "%02X", $0))"}"# }.joined(separator: ",")
    let response = try await plan(setup, body: #"{"add":[\#(many)]}"#, authorization: basic)

    #expect(try object(response)["code"] as? String == "invalidMembership")
  }

  // MARK: Failures

  @Test func answersAGroupADeviceControlsAsAnUnknownSceneWithSentFalse() async throws {
    let setup = try Setup(password: password, service: FakeService(membershipFailure: ServiceControlError.unknownScene))
    let response = try await plan(setup, number: "7", authorization: basic)
    let body = try object(response)

    #expect(response.status == .notFound)
    #expect(body["code"] as? String == "unknownScene")
    #expect(body["sent"] as? Bool == false)
  }
}
