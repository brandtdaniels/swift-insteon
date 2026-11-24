import Foundation
import InsteonCore
import InsteonHubClient
import InsteonHTTP
import Testing
@testable import InsteonServerSupport

/// Route registration over the real runner, router and files, with a scripted Hub.
@Suite(.timeLimit(.minutes(1)))
struct RouteServeTests: ServingTests {
  let gatewayPassword = String(repeating: "g", count: 40)
  let device = InsteonAddress(0x1A, 0x2B, 0x3C)

  private func away() -> ServerRunner.ModemOpener {
    opener(ScriptedHubOpener([.fail(HubStoppedAnswering(underlyingError: URLError(.timedOut)))]))
  }

  private func routeKinds(_ json: [String: Any]) -> [String?] {
    ((json["pairing"] as? [String: Any])?["routes"] as? [[String: Any]] ?? (json["routes"] as? [[String: Any]]) ?? []).map { $0["kind"] as? String }
  }

  @Test func theRoutesFileSitsBesideTheStateFileUnderItsOwnName() {
    #expect(FileRoutePersistence.url(besideState: "/var/lib/insteon/gateway.json").path == "/var/lib/insteon/gateway-routes.json")
    #expect(FileRoutePersistence.url(besideState: "/tmp/noextension").path == "/tmp/noextension-routes.json")
  }

  @Test func aRegisteredRouteSurvivesARestartInAPrivateFileAndIsInTheNextPairing() async throws {
    let directory = try scratch()
    let first = try await start(directory, openModem: away())
    let stored = try await first.request("/api/v1/routes/loopback", method: "PUT", body: #"{"ticket":"127.0.0.1:9000"}"#, password: gatewayPassword)
    #expect(stored.status == 200)
    await first.stop()

    let url = FileRoutePersistence.url(besideState: directory.appendingPathComponent("state.json").path)
    #expect(url.lastPathComponent == "state-routes.json")
    #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int == 0o600)

    let second = try await start(directory, openModem: away())
    let created = try await second.request("/api/v1/clients", method: "POST", body: #"{"name":"Phone","scope":"control"}"#, password: gatewayPassword)
    #expect(routeKinds(created.json) == ["lan", "loopback"])
    await second.stop()
  }

  @Test func aReaderListsTheRoutesAndRemovingOneLeavesTheOthers() async throws {
    let server = try await start(try scratch(), openModem: away())
    let created = try await server.request("/api/v1/clients", method: "POST", body: #"{"name":"Display","scope":"read"}"#, password: gatewayPassword)
    let token = try #require((created.json["pairing"] as? [String: Any])?["credential"] as? String)
    for kind in ["first", "second"] {
      #expect(try await server.request("/api/v1/routes/" + kind, method: "PUT", body: #"{"ticket":"t"}"#, password: gatewayPassword).status == 200)
    }
    #expect(try await server.request("/api/v1/routes/first", method: "DELETE", password: gatewayPassword).status == 204)
    let listed = try await server.request("/api/v1/routes", password: gatewayPassword, bearer: token)
    #expect(listed.status == 200 && routeKinds(listed.json) == ["second"])
    await server.stop()
  }

  @Test func theCommandListsTheRoutesARunningServerHolds() async throws {
    let directory = try scratch()
    let server = try await start(directory, openModem: away())
    _ = try await server.request("/api/v1/routes/loopback", method: "PUT", body: #"{"ticket":"127.0.0.1:9000"}"#, password: gatewayPassword)
    let state = directory.appendingPathComponent("state.json").path
    let output = try await PairCommand.run(arguments: ["--name", "Phone", "--state", state], environment: ["HOME": directory.path], showsQRCode: false)
    let json = try #require(output.firstIndex(of: "{").flatMap { start in output.lastIndex(of: "}").map { String(output[start...$0]) } })
    let document = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    let routes = try #require(document["routes"] as? [[String: Any]])
    #expect(routes.map { $0["kind"] as? String } == ["lan", "loopback"])
    try #require(routes.count == 2)
    #expect(routes[1]["ticket"] as? String == "127.0.0.1:9000")
    await server.stop()
  }

  @Test func aRoutesFileThatCannotBeReadStopsTheServerBeforeItListensAndTheCommandBeforeItMakesAClient() async throws {
    let directory = try scratch()
    let state = directory.appendingPathComponent("state.json").path
    try Data("garbage".utf8).write(to: FileRoutePersistence.url(besideState: state))
    let environment = ["HOME": directory.path, "INSTEON_GATEWAY_PASSWORD": gatewayPassword, "INSTEON_HUB_USERNAME": "hub-user", "INSTEON_HUB_PASSWORD": "hub-secret-pass"]
    do {
      try await ServerRunner.run(arguments: ["--state", state, "--hub", "192.168.1.20"], environment: environment, openModem: away())
      Issue.record("the server should not start")
    } catch {
      #expect(ServerFailure(error).code == .routesFileUnusable)
      #expect(ServerFailure(error).message.contains("state-routes.json"))
    }
    do {
      _ = try await PairCommand.run(arguments: ["--name", "Phone", "--state", state], environment: ["HOME": directory.path], showsQRCode: false)
      Issue.record("pairing should have failed")
    } catch {
      #expect(ServerFailure(error).code == .routesFileUnusable)
    }
    let clients = ClientStore(persistence: FileClientPersistence(url: FileClientPersistence.url(besideState: state)))
    #expect(try await clients.clients().isEmpty)
  }
}
