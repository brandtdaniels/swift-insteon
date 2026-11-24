import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import InsteonCore
import InsteonService
import Testing
@testable import InsteonHTTP

/// Managing notification rules and following their notifications, through the real router.
@Suite(.timeLimit(.minutes(1)))
struct NotificationRoutesTests {
  let password = String(repeating: "p", count: 40)
  private var basic: String { "Basic " + Data(("insteon:" + password).utf8).base64EncodedString() }
  static let body = #"{"name":"Basement leak","trigger":{"kind":"event","event":"wet","device":"1A.2B.3C"},"cooldownSeconds":300,"enabled":true,"includeDetail":false}"#

  private struct Setup {
    let service: FakeService
    let clients: ClientStore
    let app: Application<RouterResponder<BasicRequestContext>>
    init(password: String, service: FakeService = FakeService()) throws {
      let clients = ClientStore(persistence: InMemoryClientPersistence())
      self.service = service
      self.clients = clients
      app = Application(responder: makeInsteonRouter(service: service, authentication: try HTTPAuthentication(password: password), clients: clients).buildResponder())
    }
  }

  private func headers(_ authorization: String, json: Bool = true, marker: Bool = true) -> HTTPFields {
    var fields: HTTPFields = [.authorization: authorization]
    if marker { fields[HTTPField.Name("X-Insteon-Request")!] = "1" }
    if json { fields[.contentType] = "application/json" }
    return fields
  }

  private func object(_ response: TestResponse) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
  }

  private func put(_ client: some TestClientProtocol, _ id: String = "basement-leak", body: String = NotificationRoutesTests.body, as authorization: String) async throws -> TestResponse {
    try await client.execute(uri: "/api/v1/notification-rules/" + id, method: .put, headers: headers(authorization), body: ByteBuffer(string: body))
  }

  private func token(_ setup: Setup, scope: ClientScope) async throws -> String {
    "Bearer " + (try await setup.clients.issue(name: "Client", scope: scope)).token
  }

  // MARK: Reading and writing

  @Test func anAdminStoresARuleAndAnyReaderListsIt() async throws {
    let setup = try Setup(password: password)
    let reader = try await token(setup, scope: .read)
    try await setup.app.test(.router) { client in
      let empty = try await client.execute(uri: "/api/v1/notification-rules", method: .get, headers: [.authorization: reader])
      #expect(empty.status == .ok)
      #expect(try object(empty)["version"] as? Int == 1)
      #expect((try object(empty)["rules"] as? [Any])?.isEmpty == true)

      let stored = try await put(client, as: basic)
      #expect(stored.status == .ok)
      let rule = try #require(try object(stored)["rule"] as? [String: Any])
      #expect(rule["id"] as? String == "basement-leak")
      #expect(rule["name"] as? String == "Basement leak")
      #expect(rule["cooldownSeconds"] as? Int == 300)
      #expect(rule["enabled"] as? Bool == true)
      #expect(rule["includeDetail"] as? Bool == false)
      let trigger = try #require(rule["trigger"] as? [String: Any])
      #expect(trigger["kind"] as? String == "event" && trigger["event"] as? String == "wet" && trigger["device"] as? String == "1A.2B.3C")

      let listed = try await client.execute(uri: "/api/v1/notification-rules", method: .get, headers: [.authorization: reader])
      #expect((try object(listed)["rules"] as? [[String: Any]])?.count == 1)
    }
    let rules = await setup.service.rules
    #expect(rules == [ServiceNotificationRule(id: "basement-leak", name: "Basement leak", trigger: .event("wet", device: InsteonAddress(0x1A, 0x2B, 0x3C)), cooldownSeconds: 300, isEnabled: true, includesDetail: false)])
  }

  @Test func aGroupCommandRuleAndTheDefaultsRoundTrip() async throws {
    let setup = try Setup(password: password)
    try await setup.app.test(.router) { client in
      let stored = try await put(client, "paddle", body: #"{"name":"Paddle","trigger":{"kind":"groupCommand","command1":19,"group":5,"device":"1A.2B.3C"}}"#, as: basic)
      #expect(stored.status == .ok)
      let rule = try #require(try object(stored)["rule"] as? [String: Any])
      #expect(rule["cooldownSeconds"] as? Int == 0 && rule["enabled"] as? Bool == true && rule["includeDetail"] as? Bool == false)
      let trigger = try #require(rule["trigger"] as? [String: Any])
      #expect(trigger["kind"] as? String == "groupCommand" && trigger["command1"] as? Int == 19 && trigger["group"] as? Int == 5)
    }
  }

  @Test func anAdminRemovesARuleAndAnUnknownOneIsReported() async throws {
    let setup = try Setup(password: password)
    try await setup.app.test(.router) { client in
      _ = try await put(client, as: basic)
      let removed = try await client.execute(uri: "/api/v1/notification-rules/basement-leak", method: .delete, headers: headers(basic, json: false))
      #expect(removed.status == .noContent)
      let again = try await client.execute(uri: "/api/v1/notification-rules/basement-leak", method: .delete, headers: headers(basic, json: false))
      #expect(again.status == .notFound)
      #expect(try object(again)["code"] as? String == "unknownNotificationRule")
    }
    #expect(await setup.service.rules.isEmpty)
  }

  // MARK: Scope

  @Test func onlyAnAdminChangesRulesAndNothingChangesForAnyoneElse() async throws {
    let setup = try Setup(password: password)
    let reader = try await token(setup, scope: .read)
    let controller = try await token(setup, scope: .control)
    try await setup.app.test(.router) { client in
      _ = try await put(client, as: basic)
      for authorization in [reader, controller] {
        let write = try await put(client, "basement-leak", body: #"{"name":"Changed","trigger":{"kind":"event","event":"wet","device":"1A.2B.3C"}}"#, as: authorization)
        #expect(write.status == .forbidden)
        #expect(try object(write)["code"] as? String == "forbidden")
        let delete = try await client.execute(uri: "/api/v1/notification-rules/basement-leak", method: .delete, headers: headers(authorization, json: false))
        #expect(delete.status == .forbidden)
      }
      let listed = try await client.execute(uri: "/api/v1/notification-rules", method: .get, headers: [.authorization: controller])
      #expect(listed.status == .ok)
    }
    #expect(await setup.service.rules.map(\.name) == ["Basement leak"])
  }

  @Test func theRoutesNeedACredential() async throws {
    let setup = try Setup(password: password)
    try await setup.app.test(.router) { client in
      let response = try await client.execute(uri: "/api/v1/notification-rules", method: .get, headers: [:])
      #expect(response.status == .unauthorized)
    }
  }

  // MARK: Input

  @Test(arguments: [
    "not json", "[]", "{}",
    #"{"trigger":{"kind":"event","event":"wet","device":"1A.2B.3C"}}"#,
    #"{"name":"Leak"}"#,
    #"{"name":7,"trigger":{"kind":"event","event":"wet","device":"1A.2B.3C"}}"#,
    #"{"name":"Leak","trigger":{"kind":"event","event":"wet","device":"1A.2B.3C"},"extra":1}"#,
    #"{"id":"other","name":"Leak","trigger":{"kind":"event","event":"wet","device":"1A.2B.3C"}}"#,
    #"{"name":"Leak","trigger":{"kind":"silence","device":"1A.2B.3C"}}"#,
    #"{"name":"Leak","trigger":{"kind":"event","device":"1A.2B.3C"}}"#,
    #"{"name":"Leak","trigger":{"kind":"event","event":"wet","device":"nonsense"}}"#,
    #"{"name":"Leak","trigger":{"kind":"event","event":"wet","device":"1A.2B.3C","extra":true}}"#,
    #"{"name":"Leak","trigger":{"kind":"groupCommand","command1":300,"group":5,"device":"1A.2B.3C"}}"#,
    #"{"name":"Leak","trigger":{"kind":"groupCommand","command1":17,"device":"1A.2B.3C"}}"#,
    #"{"name":"Leak","trigger":{"kind":"event","event":"wet","device":"1A.2B.3C"},"cooldownSeconds":"5"}"#,
    #"{"name":"Leak","trigger":{"kind":"event","event":"wet","device":"1A.2B.3C"},"enabled":"yes"}"#
  ])
  func aMalformedRuleIsRefusedAndStoresNothing(_ body: String) async throws {
    let setup = try Setup(password: password)
    try await setup.app.test(.router) { client in
      let response = try await put(client, body: body, as: basic)
      #expect(response.status == .badRequest)
      #expect(try object(response)["code"] as? String == "invalidNotificationRule")
      #expect(try object(response)["sent"] as? Bool == false)
    }
    #expect(await setup.service.rules.isEmpty)
  }

  @Test func aWriteNeedsTheApiMarkerAndJSON() async throws {
    let setup = try Setup(password: password)
    try await setup.app.test(.router) { client in
      let unmarked = try await client.execute(uri: "/api/v1/notification-rules/leak", method: .put, headers: headers(basic, marker: false), body: ByteBuffer(string: Self.body))
      #expect(unmarked.status == .forbidden)
      #expect(try object(unmarked)["code"] as? String == "apiMarkerMissing")
      let form = try await client.execute(uri: "/api/v1/notification-rules/leak", method: .put, headers: headers(basic, json: false), body: ByteBuffer(string: "name=Leak"))
      #expect(form.status == .unsupportedMediaType)
      let delete = try await client.execute(uri: "/api/v1/notification-rules/leak", method: .delete, headers: headers(basic, json: false, marker: false))
      #expect(delete.status == .forbidden)
    }
    #expect(await setup.service.rules.isEmpty)
  }

  // MARK: What the service refuses

  @Test(arguments: [
    (NotificationRuleError.invalidRule, "invalidNotificationRule", 400),
    (NotificationRuleError.unknownDevice, "unknownDevice", 404),
    (NotificationRuleError.limitReached, "notificationRuleLimitReached", 409),
    (NotificationRuleError.notSaved, "notificationRulesNotSaved", 500)
  ])
  func aRefusalByTheServiceHasItsOwnCodeAndStatus(_ error: NotificationRuleError, _ code: String, _ status: Int) async throws {
    let setup = try Setup(password: password, service: FakeService(ruleFailure: error))
    try await setup.app.test(.router) { client in
      let write = try await put(client, as: basic)
      #expect(Int(write.status.code) == status)
      #expect(try object(write)["code"] as? String == code)
      #expect(try object(write)["sent"] as? Bool == false)
      if error == .notSaved {
        let read = try await client.execute(uri: "/api/v1/notification-rules", method: .get, headers: [.authorization: basic])
        #expect(read.status == .internalServerError)
        #expect(try object(read)["code"] as? String == "notificationRulesNotSaved")
      }
    }
  }

  // MARK: The event

  @Test func aNotificationFrameCarriesTheRuleTheDeviceAndTheTimeAndNothingElse() async throws {
    let device = InsteonAddress(0x1A, 0x2B, 0x3C)
    let fired = ServiceNotification(ruleID: "basement-leak", ruleName: "Basement leak", device: device, firedAt: Date(timeIntervalSince1970: 1_800_000_000), eventName: nil)
    let frame = try object(EventDTO(.notification(fired), at: EventCursor(runID: "run1", sequence: 7)))
    #expect(Set(frame.keys) == ["version", "runId", "sequence", "kind", "ruleId", "ruleName", "address", "firedAt"])
    #expect(frame["kind"] as? String == "notification")
    #expect(frame["ruleId"] as? String == "basement-leak" && frame["ruleName"] as? String == "Basement leak")
    #expect(frame["address"] as? String == "1A.2B.3C")
    #expect(frame["firedAt"] as? String == "2027-01-15T08:00:00Z")
    #expect(frame["sequence"] as? Int == 7 && frame["runId"] as? String == "run1")
  }

  @Test func aNotificationFrameNamesTheEventOnlyWhenTheRuleIncludesDetail() async throws {
    let device = InsteonAddress(0x1A, 0x2B, 0x3C)
    let fired = ServiceNotification(ruleID: "leak", ruleName: "Leak", device: device, firedAt: Date(timeIntervalSince1970: 1_800_000_000), eventName: "wet")
    let frame = try object(EventDTO(.notification(fired), at: EventCursor(runID: "run1", sequence: 7)))
    #expect(frame["name"] as? String == "wet")
  }

  @Test func aNotificationReachesAStreamAsAnOrdinaryNumberedFrame() async throws {
    let device = InsteonAddress(0x1A, 0x2B, 0x3C)
    let fired = ServiceNotification(ruleID: "leak", ruleName: "Leak", device: device, firedAt: Date(timeIntervalSince1970: 1_800_000_000), eventName: nil)
    let (source, events) = AsyncStream<ServiceEvent>.makeStream()
    let api = DeviceAPI(service: FakeService(eventStream: source))
    let (chunks, continuation) = AsyncStream<String>.makeStream()
    let task = Task {
      let response = await api.events()
      try await response.body.write(ChunkRecorder(chunks: continuation))
    }
    var reader = chunks.makeAsyncIterator()
    _ = await reader.next()
    events.yield(.notification(fired))
    let frame = try #require(await reader.next())
    #expect(frame.hasPrefix("id: fake-1\ndata: {"))
    #expect(frame.contains(#""kind":"notification""#))
    task.cancel()
    _ = await task.result
  }

  private func object(_ dto: some Encodable) throws -> [String: Any] {
    let encoder = JSONEncoder()
    return try #require(try JSONSerialization.jsonObject(with: try encoder.encode(dto)) as? [String: Any])
  }
}
