import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import InsteonService
import Testing
@testable import InsteonHTTP

/// Managing clients and pairing documents through the real router.
@Suite(.timeLimit(.minutes(1)))
struct ClientRoutesTests {
  let password = String(repeating: "p", count: 40)
  static let routes = [PairingRoute(kind: "lan", url: "http://insteon.local:8080"), PairingRoute(kind: "example", ticket: "opaque-ticket")]
  private var basic: String { "Basic " + Data(("insteon:" + password).utf8).base64EncodedString() }

  private struct Setup {
    let service = FakeService()
    let persistence: RecordingPersistence
    let clients: ClientStore
    let app: Application<RouterResponder<BasicRequestContext>>
    init(password: String) throws {
      let persistence = RecordingPersistence()
      let clients = ClientStore(persistence: persistence)
      let configuration = PairingConfiguration(homeName: "Home", routes: ClientRoutesTests.routes)
      self.persistence = persistence
      self.clients = clients
      app = Application(responder: makeInsteonRouter(service: FakeService(), authentication: try HTTPAuthentication(password: password), clients: clients, pairing: configuration).buildResponder())
    }
  }

  private func headers(_ authorization: String, body: Bool = false) -> HTTPFields {
    var fields: HTTPFields = [.authorization: authorization, HTTPField.Name("X-Insteon-Request")!: "1"]
    if body { fields[.contentType] = "application/json" }
    return fields
  }

  private func object(_ response: TestResponse) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
  }

  private func create(_ client: some TestClientProtocol, _ name: String, scope: String, as authorization: String) async throws -> TestResponse {
    try await client.execute(uri: "/api/v1/clients", method: .post, headers: headers(authorization, body: true), body: ByteBuffer(string: #"{"name":""# + name + #"","scope":""# + scope + #""}"#))
  }

  // MARK: Creating

  @Test func anAdminCreatesAClientAndGetsItsTokenOnceInAPairingDocument() async throws {
    let setup = try Setup(password: password)
    try await setup.app.test(.router) { client in
      let response = try await create(client, "Phone", scope: "control", as: basic)
      #expect(response.status == .created)
      let json = try object(response)
      #expect(json["version"] as? Int == 1)
      let created = try #require(json["client"] as? [String: Any])
      #expect(created["name"] as? String == "Phone")
      #expect(created["scope"] as? String == "control")
      let pairing = try #require(json["pairing"] as? [String: Any])
      #expect(pairing["version"] as? Int == 1)
      #expect(pairing["serviceId"] as? String == (try await setup.clients.serviceID()))
      #expect(pairing["name"] as? String == "Home")
      #expect(pairing["scope"] as? String == "control")
      #expect(pairing["api"] as? String == "/api/v1")
      let routes = try #require(pairing["routes"] as? [[String: Any]])
      #expect(routes.count == 2)
      #expect(routes[0]["kind"] as? String == "lan" && routes[0]["url"] as? String == "http://insteon.local:8080" && routes[0]["ticket"] == nil)
      #expect(routes[1]["kind"] as? String == "example" && routes[1]["ticket"] as? String == "opaque-ticket" && routes[1]["url"] == nil)
      let credential = try #require(pairing["credential"] as? String)
      #expect(json["token"] == nil)

      let health = try await client.execute(uri: "/api/v1/health", method: .get, headers: [.authorization: "Bearer " + credential])
      #expect(health.status == .ok)

      let listed = try await client.execute(uri: "/api/v1/clients", method: .get, headers: [.authorization: basic])
      #expect(!String(buffer: listed.body).contains(credential))
      #expect(!String(buffer: listed.body).contains(try #require(credential.split(separator: ".").last.map(String.init))))
    }
  }

  @Test func aSecondRequestMakesASecondClient() async throws {
    let setup = try Setup(password: password)
    try await setup.app.test(.router) { client in
      let first = try object(try await create(client, "Phone", scope: "control", as: basic))
      let second = try object(try await create(client, "Phone", scope: "control", as: basic))
      let ids = [first, second].compactMap { ($0["client"] as? [String: Any])?["id"] as? String }
      #expect(Set(ids).count == 2)
      let credentials = [first, second].compactMap { ($0["pairing"] as? [String: Any])?["credential"] as? String }
      #expect(Set(credentials).count == 2)
      let listed = try object(try await client.execute(uri: "/api/v1/clients", method: .get, headers: [.authorization: basic]))
      #expect((listed["clients"] as? [[String: Any]])?.count == 2)
      #expect(listed["version"] as? Int == 1)
    }
  }

  @Test(arguments: [
    #"{"name":"","scope":"read"}"#, #"{"name":"Phone"}"#, #"{"scope":"read"}"#, #"{"name":"Phone","scope":"root"}"#,
    #"{"name":"Phone","scope":"read","extra":1}"#, #"{"name":7,"scope":"read"}"#, "not json", "[]"
  ])
  func aMalformedRequestIsRefusedAndCreatesNothing(_ body: String) async throws {
    let setup = try Setup(password: password)
    try await setup.app.test(.router) { client in
      let response = try await client.execute(uri: "/api/v1/clients", method: .post, headers: headers(basic, body: true), body: ByteBuffer(string: body))
      #expect(response.status == .badRequest)
      #expect(try object(response)["code"] as? String == "invalidClient")
      #expect(try object(response)["sent"] as? Bool == false)
    }
    #expect(try await setup.clients.clients().isEmpty)
  }

  @Test func aCreateNeedsTheApiMarkerAndJSON() async throws {
    let setup = try Setup(password: password)
    try await setup.app.test(.router) { client in
      let unmarked = try await client.execute(uri: "/api/v1/clients", method: .post, headers: [.authorization: basic, .contentType: "application/json"], body: ByteBuffer(string: #"{"name":"Phone","scope":"read"}"#))
      #expect(unmarked.status == .forbidden)
      #expect(try object(unmarked)["code"] as? String == "apiMarkerMissing")
      let form = try await client.execute(uri: "/api/v1/clients", method: .post, headers: headers(basic), body: ByteBuffer(string: "name=Phone"))
      #expect(form.status == .unsupportedMediaType)
    }
    #expect(try await setup.clients.clients().isEmpty)
  }

  @Test func theNumberOfClientsIsLimitedAndAFailedSaveIsReported() async throws {
    let setup = try Setup(password: password)
    for index in 0..<ClientStore.maximumClients { _ = try await setup.clients.issue(name: "C" + String(index), scope: .read) }
    try await setup.app.test(.router) { client in
      let full = try await create(client, "More", scope: "read", as: basic)
      #expect(full.status == .conflict)
      #expect(try object(full)["code"] as? String == "clientLimitReached")
    }
    let failing = try Setup(password: password)
    await failing.persistence.refuseWrites(true)
    try await failing.app.test(.router) { client in
      let response = try await create(client, "Phone", scope: "read", as: basic)
      #expect(response.status == .internalServerError)
      #expect(try object(response)["code"] as? String == "clientsNotSaved")
      #expect(try object(response)["sent"] as? Bool == false)
    }
  }

  // MARK: Scope

  @Test func onlyAnAdminManagesClients() async throws {
    let setup = try Setup(password: password)
    let reader = try await setup.clients.issue(name: "Display", scope: .read)
    let controller = try await setup.clients.issue(name: "Phone", scope: .control)
    let target = try await setup.clients.issue(name: "Tablet", scope: .read)
    try await setup.app.test(.router) { client in
      for issued in [reader, controller] {
        let bearer = "Bearer " + issued.token
        let requests: [(HTTPRequest.Method, String)] = [(.get, "/api/v1/clients"), (.post, "/api/v1/clients"), (.delete, "/api/v1/clients/" + target.client.id), (.post, "/api/v1/clients/" + target.client.id + "/pairing")]
        for (method, path) in requests {
          let response = try await client.execute(uri: path, method: method, headers: headers(bearer, body: method == .post && !path.hasSuffix("pairing")), body: method == .post && !path.hasSuffix("pairing") ? ByteBuffer(string: #"{"name":"X","scope":"admin"}"#) : nil)
          #expect(response.status == .forbidden, "\(issued.client.scope) \(method) \(path)")
          #expect(try object(response)["code"] as? String == "forbidden")
        }
      }
    }
    #expect(try await setup.clients.clients().count == 3)
    #expect(await setup.clients.authenticate(token: target.token) == target.client)
  }

  @Test func anAdminClientManagesClientsLikeTheGatewayPassword() async throws {
    let setup = try Setup(password: password)
    let admin = try await setup.clients.issue(name: "Console", scope: .admin)
    try await setup.app.test(.router) { client in
      let response = try await create(client, "Phone", scope: "read", as: "Bearer " + admin.token)
      #expect(response.status == .created)
    }
  }

  // MARK: Revoking and pairing again

  @Test func revokingEndsTheClientsNextRequest() async throws {
    let setup = try Setup(password: password)
    let phone = try await setup.clients.issue(name: "Phone", scope: .control)
    try await setup.app.test(.router) { client in
      let before = try await client.execute(uri: "/api/v1/devices", method: .get, headers: [.authorization: "Bearer " + phone.token])
      #expect(before.status == .ok)
      let revoked = try await client.execute(uri: "/api/v1/clients/" + phone.client.id, method: .delete, headers: headers(basic))
      #expect(revoked.status == .noContent)
      let after = try await client.execute(uri: "/api/v1/devices", method: .get, headers: [.authorization: "Bearer " + phone.token])
      #expect(after.status == .unauthorized)
      #expect(try object(after)["code"] as? String == "authenticationFailed")
      let again = try await client.execute(uri: "/api/v1/clients/" + phone.client.id, method: .delete, headers: headers(basic))
      #expect(again.status == .notFound)
      #expect(try object(again)["code"] as? String == "unknownClient")
    }
  }

  @Test func revokingNeedsTheApiMarker() async throws {
    let setup = try Setup(password: password)
    let phone = try await setup.clients.issue(name: "Phone", scope: .control)
    try await setup.app.test(.router) { client in
      let response = try await client.execute(uri: "/api/v1/clients/" + phone.client.id, method: .delete, headers: [.authorization: basic])
      #expect(response.status == .forbidden)
      #expect(try object(response)["code"] as? String == "apiMarkerMissing")
    }
    #expect(await setup.clients.authenticate(token: phone.token) == phone.client)
  }

  @Test func askingToPairAClientAgainGivesItAFreshCredentialAndEndsTheOldOne() async throws {
    let setup = try Setup(password: password)
    let phone = try await setup.clients.issue(name: "Phone", scope: .control)
    try await setup.app.test(.router) { client in
      let response = try await client.execute(uri: "/api/v1/clients/" + phone.client.id + "/pairing", method: .post, headers: headers(basic))
      #expect(response.status == .ok)
      let document = try object(response)
      #expect(document["version"] as? Int == 1)
      #expect(document["scope"] as? String == "control")
      #expect((document["routes"] as? [[String: Any]])?.count == 2)
      let fresh = try #require(document["credential"] as? String)
      #expect(fresh != phone.token)
      #expect(try await client.execute(uri: "/api/v1/devices", method: .get, headers: [.authorization: "Bearer " + phone.token]).status == .unauthorized)
      #expect(try await client.execute(uri: "/api/v1/devices", method: .get, headers: [.authorization: "Bearer " + fresh]).status == .ok)
      let unknown = try await client.execute(uri: "/api/v1/clients/0000000000000000/pairing", method: .post, headers: headers(basic))
      #expect(unknown.status == .notFound)
    }
  }

  @Test func theDocumentIsNeverCached() async throws {
    let setup = try Setup(password: password)
    try await setup.app.test(.router) { client in
      let response = try await create(client, "Phone", scope: "read", as: basic)
      #expect(response.headers[.cacheControl] == "no-store")
    }
  }

  // MARK: Streams

  @Test func revokingAClientEndsItsOpenStreamsAndLeavesOthersOpen() async throws {
    let clock = ManualClock()
    let policy = EventStreamPolicy(heartbeatInterval: .seconds(10), maximumLifetime: .seconds(600), maximumStreams: 8)
    let streams = EventStreamRegistry(limit: policy.maximumStreams)
    let api = DeviceAPI(service: FakeService(endlessEvents: true), policy: policy, clock: clock, registry: streams)
    let clients = ClientStore(persistence: InMemoryClientPersistence())
    let clientAPI = ClientAPI(clients: clients, pairing: PairingConfiguration(), streams: streams)
    let revoked = try await clients.issue(name: "Phone", scope: .read)
    let kept = try await clients.issue(name: "Tablet", scope: .read)

    func open(_ id: String?) -> (task: Task<Void, any Error>, chunks: AsyncStream<String>) {
      let (chunks, continuation) = AsyncStream<String>.makeStream()
      let task = Task {
        let response = await RequestPrincipal.$current.withValue(RequestPrincipal(scope: .read, clientID: id)) { await api.events() }
        try await response.body.write(ChunkRecorder(chunks: continuation))
      }
      return (task, chunks)
    }
    let first = open(revoked.client.id), second = open(revoked.client.id), other = open(kept.client.id), gateway = open(nil)
    var iterators = [first.chunks, second.chunks, other.chunks, gateway.chunks].map { $0.makeAsyncIterator() }
    // A regression fails here instead of waiting on a stream that never ends.
    defer { for open in [first, second, other, gateway] { open.task.cancel() } }
    for index in iterators.indices { #expect(await iterators[index].next() == ": connected\n\n") }

    try await clientAPI.revoke(id: revoked.client.id)
    // The registry no longer holds the client's streams, so the check is on state, not on a wait.
    try #require(await streams.openStreamCount(clientID: revoked.client.id) == 0)
    try #require(await streams.openStreamCount(clientID: kept.client.id) == 1)
    _ = await first.task.result
    _ = await second.task.result
    #expect(await iterators[0].next() == ChunkRecorder.finished)
    #expect(await iterators[1].next() == ChunkRecorder.finished)

    // The others are still open: a keepalive reaches them.
    await clock.waitForSleepers(2, until: .seconds(10))
    clock.advance(by: .seconds(10))
    #expect(await iterators[2].next() == ": keepalive\n\n")
    #expect(await iterators[3].next() == ": keepalive\n\n")
    other.task.cancel(); gateway.task.cancel()
    _ = await other.task.result; _ = await gateway.task.result
  }

  /// The request authenticated, the client was revoked, and only then did the stream register: the interleaving that left a revoked client with a stream.
  @Test func aStreamThatRegistersAfterItsClientWasRevokedEndsWithoutWritingAnything() async throws {
    let streams = EventStreamRegistry(limit: 8)
    let clients = ClientStore(persistence: InMemoryClientPersistence())
    let api = DeviceAPI(service: FakeService(endlessEvents: true), clock: ManualClock(), registry: streams, isClientActive: { id in ((try? await clients.clients()) ?? []).contains { $0.id == id } })
    let clientAPI = ClientAPI(clients: clients, pairing: PairingConfiguration(), streams: streams)
    let phone = try await clients.issue(name: "Phone", scope: .read)

    let response = await RequestPrincipal.$current.withValue(RequestPrincipal(scope: .read, clientID: phone.client.id)) { await api.events() }
    try await clientAPI.revoke(id: phone.client.id)

    let (chunks, continuation) = AsyncStream<String>.makeStream()
    let task = Task { try await response.body.write(ChunkRecorder(chunks: continuation)) }
    defer { task.cancel() }
    var iterator = chunks.makeAsyncIterator()
    // The first thing written is either the greeting of an open stream or the end of a closed one.
    try #require(await iterator.next() == ChunkRecorder.finished)
    _ = await task.result
    #expect(await streams.openStreamCount(clientID: phone.client.id) == 0)
  }
}
