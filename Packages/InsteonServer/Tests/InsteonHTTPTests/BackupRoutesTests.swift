import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import InsteonCore
import InsteonService
import Testing
@testable import InsteonHTTP

/// `GET /api/v1/backup`: the same document `insteon backup` writes, for an admin, from the cache.
@Suite(.timeLimit(.minutes(1)))
struct BackupRoutesTests {
  let password = String(repeating: "p", count: 40)
  private var basic: String { "Basic " + Data(("insteon:" + password).utf8).base64EncodedString() }

  private struct Setup {
    let clients: ClientStore
    let routes: RouteStore
    let service: FakeService
    let app: Application<RouterResponder<BasicRequestContext>>
    init(password: String, service: FakeService = FakeService(), routes: any RoutePersisting = RecordingRoutePersistence()) throws {
      let clients = ClientStore(persistence: InMemoryClientPersistence())
      let store = RouteStore(persistence: routes)
      self.clients = clients
      self.routes = store
      self.service = service
      app = Application(responder: makeInsteonRouter(service: service, authentication: try HTTPAuthentication(password: password), clients: clients, routes: store).buildResponder())
    }
  }

  private func fetch(_ setup: Setup, authorization: String) async throws -> TestResponse {
    try await setup.app.test(.router) { client in
      try await client.execute(uri: "/api/v1/backup", method: .get, headers: [.authorization: authorization])
    }
  }

  @Test func givesAnAdminTheBackupAsJSONWithAValidChecksum() async throws {
    let setup = try Setup(password: password)
    let response = try await fetch(setup, authorization: basic)
    #expect(response.status == .ok)
    #expect(response.headers[.contentType] == "application/json")
    let backup = try HomeBackup(parsing: Data(response.body.readableBytesView))
    #expect(backup.source == .service)
    #expect(backup.modem?.address == InsteonAddress(0x11, 0x22, 0x33))
    #expect(backup.devices.count == 2)
    #expect(backup.devices.contains { $0.unreadable?.reason == .notCached })
  }

  @Test func includesTheRulesAndRoutesAsTheirOwnRoutesWriteThem() async throws {
    let setup = try Setup(password: password)
    let rule = ServiceNotificationRule(id: "front-door", name: "Front door", trigger: .event("opened", device: InsteonAddress(0x1A, 0x2B, 0x3C)), cooldownSeconds: 30, isEnabled: true, includesDetail: true)
    try await setup.service.putNotificationRule(rule)
    _ = try await setup.routes.put(kind: "relay", ticket: "ticket-1")
    let backup = try HomeBackup(parsing: Data(try await fetch(setup, authorization: basic).body.readableBytesView))
    #expect(backup.routes == [BackupRoute(kind: "relay", ticket: "ticket-1")])
    let encoded = try JSONEncoder().encode(NotificationRuleRecord(rule))
    let expected = try JSONDecoder().decode(BackupValue.self, from: encoded)
    #expect(backup.notificationRules == [expected])
  }

  @Test func holdsNoPasswordOrClientTokenOrHubAddress() async throws {
    let setup = try Setup(password: password)
    let issued = try await setup.clients.issue(name: "Phone", scope: .admin)
    let response = try await fetch(setup, authorization: basic)
    let text = String(decoding: response.body.readableBytesView, as: UTF8.self)
    #expect(!text.contains(password))
    #expect(!text.contains(issued.token))
    #expect(!text.contains(issued.client.id))
    #expect(!text.lowercased().contains("password"))
    #expect(!text.lowercased().contains("token"))
  }

  @Test func needsTheAdminScope() async throws {
    let setup = try Setup(password: password)
    for scope in [ClientScope.read, .control] {
      let issued = try await setup.clients.issue(name: "Client", scope: scope)
      let response = try await fetch(setup, authorization: "Bearer " + issued.token)
      #expect(response.status == .forbidden)
      #expect(try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) is [String: Any])
    }
    let admin = try await setup.clients.issue(name: "Admin", scope: .admin)
    #expect(try await fetch(setup, authorization: "Bearer " + admin.token).status == .ok)
    #expect(await setup.service.backups == 1)
  }

  @Test func needsAuthentication() async throws {
    let setup = try Setup(password: password)
    let response = try await setup.app.test(.router) { client in try await client.execute(uri: "/api/v1/backup", method: .get) }
    #expect(response.status == .unauthorized)
    #expect(await setup.service.backups == 0)
  }

  @Test func failsWithTheRulesErrorWhenTheRulesCantBeRead() async throws {
    let setup = try Setup(password: password, service: FakeService(ruleFailure: .notSaved))
    let response = try await fetch(setup, authorization: basic)
    #expect(response.status != .ok)
    let object = try #require(try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
    #expect(object["code"] as? String == "notificationRulesNotSaved")
  }

  @Test func failsWithTheRoutesErrorWhenTheRoutesCantBeRead() async throws {
    let persistence = RecordingRoutePersistence()
    persistence.refuse(reads: true)
    let setup = try Setup(password: password, routes: persistence)
    let response = try await fetch(setup, authorization: basic)
    #expect(response.status != .ok)
    let object = try #require(try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
    #expect(object["code"] as? String == "routeRegistrationsNotSaved")
  }
}
