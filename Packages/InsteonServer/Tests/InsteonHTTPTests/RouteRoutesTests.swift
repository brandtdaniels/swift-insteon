import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import InsteonService
import Testing
@testable import InsteonHTTP

/// Registering transport routes and the pairing documents that list them, through the real router.
@Suite(.timeLimit(.minutes(1)))
struct RouteRoutesTests {
  let password = String(repeating: "p", count: 40)
  private var basic: String { "Basic " + Data(("insteon:" + password).utf8).base64EncodedString() }

  private struct Setup {
    let clients: ClientStore
    let routes: RouteStore
    let persistence: RecordingRoutePersistence
    let app: Application<RouterResponder<BasicRequestContext>>
    init(password: String, persistence: RecordingRoutePersistence = RecordingRoutePersistence()) throws {
      let clients = ClientStore(persistence: InMemoryClientPersistence())
      let routes = RouteStore(persistence: persistence)
      self.clients = clients
      self.routes = routes
      self.persistence = persistence
      let pairing = PairingConfiguration(homeName: "Home", routes: [PairingRoute(kind: "lan", url: "http://insteon.local:8080")])
      app = Application(responder: makeInsteonRouter(service: FakeService(), authentication: try HTTPAuthentication(password: password), clients: clients, pairing: pairing, routes: routes).buildResponder())
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

  private func put(_ client: some TestClientProtocol, _ kind: String = "loopback", body: String = #"{"ticket":"127.0.0.1:9000"}"#, as authorization: String) async throws -> TestResponse {
    try await client.execute(uri: "/api/v1/routes/" + kind, method: .put, headers: headers(authorization), body: ByteBuffer(string: body))
  }

  private func pairingRoutes(_ client: some TestClientProtocol, name: String = "Phone") async throws -> [[String: Any]] {
    let created = try await client.execute(uri: "/api/v1/clients", method: .post, headers: headers(basic), body: ByteBuffer(string: #"{"name":""# + name + #"","scope":"control"}"#))
    let pairing = try #require(try object(created)["pairing"] as? [String: Any])
    return try #require(pairing["routes"] as? [[String: Any]])
  }

  // MARK: Reading and writing

  @Test func anAdminRegistersARouteAndAnyReaderListsIt() async throws {
    let setup = try Setup(password: password)
    let reader = "Bearer " + (try await setup.clients.issue(name: "Display", scope: .read)).token
    try await setup.app.test(.router) { client in
      let empty = try await client.execute(uri: "/api/v1/routes", method: .get, headers: [.authorization: reader])
      #expect(empty.status == .ok)
      #expect(try object(empty)["version"] as? Int == 1)
      #expect((try object(empty)["routes"] as? [Any])?.isEmpty == true)

      let stored = try await put(client, as: basic)
      #expect(stored.status == .ok)
      let route = try #require(try object(stored)["route"] as? [String: Any])
      #expect(route["kind"] as? String == "loopback" && route["ticket"] as? String == "127.0.0.1:9000")

      let listed = try await client.execute(uri: "/api/v1/routes", method: .get, headers: [.authorization: reader])
      let routes = try #require(try object(listed)["routes"] as? [[String: Any]])
      #expect(routes.count == 1 && routes[0]["kind"] as? String == "loopback" && routes[0]["ticket"] as? String == "127.0.0.1:9000")
    }
  }

  @Test func registeringAKindAgainReplacesItsTicket() async throws {
    let setup = try Setup(password: password)
    try await setup.app.test(.router) { client in
      _ = try await put(client, as: basic)
      _ = try await put(client, body: #"{"ticket":"127.0.0.1:9100"}"#, as: basic)
    }
    #expect(try await setup.routes.routes() == [RegisteredRoute(kind: "loopback", ticket: "127.0.0.1:9100")])
  }

  @Test func anAdminRemovesARouteOnce() async throws {
    let setup = try Setup(password: password)
    try await setup.app.test(.router) { client in
      _ = try await put(client, as: basic)
      let removed = try await client.execute(uri: "/api/v1/routes/loopback", method: .delete, headers: headers(basic, json: false))
      #expect(removed.status == .noContent)
      let again = try await client.execute(uri: "/api/v1/routes/loopback", method: .delete, headers: headers(basic, json: false))
      #expect(again.status == .notFound)
      #expect(try object(again)["code"] as? String == "unknownRouteRegistration")
      #expect(try object(again)["sent"] as? Bool == false)
    }
    #expect(try await setup.routes.routes().isEmpty)
  }

  @Test(arguments: [#"{}"#, #"{"ticket":7}"#, #"{"ticket":""}"#, #"{"ticket":"t","extra":1}"#, "not json", "[]", #"{"ticket":null}"#])
  func aMalformedRequestIsRefusedAndStoresNothing(_ body: String) async throws {
    let setup = try Setup(password: password)
    try await setup.app.test(.router) { client in
      let response = try await put(client, body: body, as: basic)
      #expect(response.status == .badRequest)
      #expect(try object(response)["code"] as? String == "invalidRouteRegistration")
      #expect(try object(response)["sent"] as? Bool == false)
    }
    #expect(try await setup.routes.routes().isEmpty)
  }

  @Test(arguments: ["Upper", "lan", "has_underscore", "9lives"])
  func aKindThatIsNotAShortLowercaseIdentifierIsRefused(_ kind: String) async throws {
    let setup = try Setup(password: password)
    try await setup.app.test(.router) { client in
      let response = try await put(client, kind, as: basic)
      #expect(response.status == .badRequest)
      #expect(try object(response)["code"] as? String == "invalidRouteRegistration")
    }
  }

  @Test func aWriteNeedsTheApiMarkerAndJSON() async throws {
    let setup = try Setup(password: password)
    try await setup.app.test(.router) { client in
      let unmarked = try await client.execute(uri: "/api/v1/routes/loopback", method: .put, headers: headers(basic, marker: false), body: ByteBuffer(string: #"{"ticket":"t"}"#))
      #expect(unmarked.status == .forbidden)
      #expect(try object(unmarked)["code"] as? String == "apiMarkerMissing")
      let form = try await client.execute(uri: "/api/v1/routes/loopback", method: .put, headers: headers(basic, json: false), body: ByteBuffer(string: "ticket=t"))
      #expect(form.status == .unsupportedMediaType)
      let unmarkedDelete = try await client.execute(uri: "/api/v1/routes/loopback", method: .delete, headers: [.authorization: basic])
      #expect(unmarkedDelete.status == .forbidden)
    }
    #expect(try await setup.routes.routes().isEmpty)
  }

  @Test func theNumberOfRoutesIsLimitedAndAFailedSaveIsReported() async throws {
    let setup = try Setup(password: password)
    for index in 0..<RouteStore.maximumRoutes { _ = try await setup.routes.put(kind: "kind" + String(index), ticket: "t") }
    try await setup.app.test(.router) { client in
      let full = try await put(client, "extra", as: basic)
      #expect(full.status == .conflict)
      #expect(try object(full)["code"] as? String == "routeRegistrationLimitReached")
    }
    let failing = try Setup(password: password)
    failing.persistence.refuse(writes: true)
    try await failing.app.test(.router) { client in
      let response = try await put(client, as: basic)
      #expect(response.status == .internalServerError)
      #expect(try object(response)["code"] as? String == "routeRegistrationsNotSaved")
    }
  }

  // MARK: Scope

  @Test func onlyAnAdminChangesRoutes() async throws {
    let setup = try Setup(password: password)
    _ = try await setup.routes.put(kind: "kept", ticket: "t")
    try await setup.app.test(.router) { client in
      for scope in [ClientScope.read, .control] {
        let bearer = "Bearer " + (try await setup.clients.issue(name: "Client", scope: scope)).token
        let written = try await put(client, as: bearer)
        #expect(written.status == .forbidden, "\(scope)")
        #expect(try object(written)["code"] as? String == "forbidden")
        let removed = try await client.execute(uri: "/api/v1/routes/kept", method: .delete, headers: headers(bearer, json: false))
        #expect(removed.status == .forbidden, "\(scope)")
        // Reading is open to every scope.
        #expect(try await client.execute(uri: "/api/v1/routes", method: .get, headers: [.authorization: bearer]).status == .ok)
      }
      let admin = "Bearer " + (try await setup.clients.issue(name: "Console", scope: .admin)).token
      #expect(try await put(client, as: admin).status == .ok)
    }
    #expect(try await setup.routes.routes().map(\.kind) == ["kept", "loopback"])
  }

  @Test func aRequestWithoutCredentialsIsRefused() async throws {
    let setup = try Setup(password: password)
    try await setup.app.test(.router) { client in
      let response = try await client.execute(uri: "/api/v1/routes", method: .get)
      #expect(response.status == .unauthorized)
    }
  }

  // MARK: Pairing

  @Test func aPairingIssuedAfterwardListsTheRegisteredRoutesAfterTheLANRouteInRegistrationOrder() async throws {
    let setup = try Setup(password: password)
    try await setup.app.test(.router) { client in
      _ = try await put(client, "zeta", body: #"{"ticket":"zt"}"#, as: basic)
      _ = try await put(client, "alpha", body: #"{"ticket":"at"}"#, as: basic)
      let routes = try await pairingRoutes(client)
      #expect(routes.map { $0["kind"] as? String } == ["lan", "zeta", "alpha"])
      try #require(routes.count == 3)
      #expect(routes[0]["url"] as? String == "http://insteon.local:8080" && routes[0]["ticket"] == nil)
      #expect(routes[1]["ticket"] as? String == "zt" && routes[1]["url"] == nil)
      #expect(routes[2]["ticket"] as? String == "at")
    }
  }

  @Test func aRemovedRouteIsNotInTheNextPairing() async throws {
    let setup = try Setup(password: password)
    try await setup.app.test(.router) { client in
      _ = try await put(client, as: basic)
      _ = try await client.execute(uri: "/api/v1/routes/loopback", method: .delete, headers: headers(basic, json: false))
      #expect(try await pairingRoutes(client).map { $0["kind"] as? String } == ["lan"])
    }
  }

  @Test func aClientPairedBeforeARouteWasRegisteredKeepsWorking() async throws {
    let setup = try Setup(password: password)
    try await setup.app.test(.router) { client in
      let earlier = try await client.execute(uri: "/api/v1/clients", method: .post, headers: headers(basic), body: ByteBuffer(string: #"{"name":"Phone","scope":"control"}"#))
      let credential = try #require((try object(earlier)["pairing"] as? [String: Any])?["credential"] as? String)
      _ = try await put(client, as: basic)
      #expect(try await client.execute(uri: "/api/v1/health", method: .get, headers: [.authorization: "Bearer " + credential]).status == .ok)
    }
  }

  @Test func pairingAClientAgainListsTheRegisteredRoutes() async throws {
    let setup = try Setup(password: password)
    let phone = try await setup.clients.issue(name: "Phone", scope: .control)
    try await setup.app.test(.router) { client in
      _ = try await put(client, as: basic)
      let response = try await client.execute(uri: "/api/v1/clients/" + phone.client.id + "/pairing", method: .post, headers: headers(basic, json: false))
      let routes = try #require(try object(response)["routes"] as? [[String: Any]])
      #expect(routes.map { $0["kind"] as? String } == ["lan", "loopback"])
    }
  }

  @Test func aPairingThatCannotReadTheRoutesIssuesNoClient() async throws {
    let persistence = RecordingRoutePersistence()
    let setup = try Setup(password: password, persistence: persistence)
    persistence.refuse(reads: true)
    try await setup.app.test(.router) { client in
      let response = try await client.execute(uri: "/api/v1/clients", method: .post, headers: headers(basic), body: ByteBuffer(string: #"{"name":"Phone","scope":"control"}"#))
      #expect(response.status == .internalServerError)
      #expect(try object(response)["code"] as? String == "routeRegistrationsNotSaved")
    }
    #expect(try await setup.clients.clients().isEmpty)
  }
}
