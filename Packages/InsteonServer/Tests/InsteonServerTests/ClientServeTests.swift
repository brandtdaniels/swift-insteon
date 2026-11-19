import Foundation
import InsteonCore
import InsteonHubClient
import InsteonService
import Testing
@testable import InsteonServerSupport

/// Clients and pairing over the real runner, router and files, with a scripted Hub.
@Suite(.timeLimit(.minutes(1)))
struct ClientServeTests: ServingTests {
  let gatewayPassword = String(repeating: "g", count: 40)
  let device = InsteonAddress(0x1A, 0x2B, 0x3C)

  private func away() -> ServerRunner.ModemOpener {
    opener(ScriptedHubOpener([.fail(HubStoppedAnswering(underlyingError: URLError(.timedOut)))]))
  }

  private func credential(_ json: [String: Any]) throws -> (id: String, token: String) {
    let client = try #require(json["client"] as? [String: Any])
    let pairing = try #require(json["pairing"] as? [String: Any])
    return (try #require(client["id"] as? String), try #require(pairing["credential"] as? String))
  }

  @Test func aClientIsCreatedUsedLimitedAndRevokedOverTheRealListener() async throws {
    let directory = try scratch()
    let server = try await start(directory, openModem: away())
    let created = try await server.request("/api/v1/clients", method: "POST", body: #"{"name":"Display","scope":"read"}"#, password: gatewayPassword)
    #expect(created.status == 201)
    let (id, token) = try credential(created.json)

    let devices = try await server.request("/api/v1/devices", password: gatewayPassword, bearer: token)
    #expect(devices.status == 200)
    let refused = try await server.request("/api/v1/devices/1A.2B.3C/commands", method: "POST", body: #"{"action":"on"}"#, password: gatewayPassword, bearer: token)
    #expect(refused.status == 403)
    #expect(refused.json["code"] as? String == "forbidden")
    #expect(refused.json["sent"] as? Bool == false)
    let unmanaged = try await server.request("/api/v1/clients", password: gatewayPassword, bearer: token)
    #expect(unmanaged.status == 403)

    let revoked = try await server.request("/api/v1/clients/" + id, method: "DELETE", password: gatewayPassword)
    #expect(revoked.status == 204)
    let after = try await server.request("/api/v1/devices", password: gatewayPassword, bearer: token)
    #expect(after.status == 401)
    #expect(after.json["code"] as? String == "authenticationFailed")
    // The gateway password is unaffected.
    #expect(try await server.request("/api/v1/devices", password: gatewayPassword).status == 200)

    let secret = try #require(token.split(separator: ".").last.map(String.init))
    let log = server.capture.records.map(\.rendered).joined(separator: "\n")
    #expect(!log.contains(secret) && !log.contains(gatewayPassword))
    let file = try String(contentsOf: FileClientPersistence.url(besideState: directory.appendingPathComponent("state.json").path), encoding: .utf8)
    #expect(!file.contains(secret))
    await server.stop()
  }

  @Test func theAdvertisedAddressAndHomeNameAreInTheDocumentTheServerReturns() async throws {
    let server = try await start(try scratch(), extra: ["--hub", "192.168.1.20", "--advertise-url", "http://insteon.example:9000", "--home-name", "Beach house"], openModem: away())
    let created = try await server.request("/api/v1/clients", method: "POST", body: #"{"name":"Phone","scope":"control"}"#, password: gatewayPassword)
    let pairing = try #require(created.json["pairing"] as? [String: Any])
    #expect(pairing["name"] as? String == "Beach house")
    let routes = try #require(pairing["routes"] as? [[String: Any]])
    #expect(routes.count == 1 && routes[0]["kind"] as? String == "lan" && routes[0]["url"] as? String == "http://insteon.example:9000")
    await server.stop()
  }

  @Test func theLANRouteDefaultsToTheListeningAddress() async throws {
    let server = try await start(try scratch(), openModem: away())
    let created = try await server.request("/api/v1/clients", method: "POST", body: #"{"name":"Phone","scope":"control"}"#, password: gatewayPassword)
    let routes = try #require((created.json["pairing"] as? [String: Any])?["routes"] as? [[String: Any]])
    #expect(routes.first?["url"] as? String == "http://127.0.0.1:" + String(server.port))
    await server.stop()
  }

  @Test func aClientPairedByTheCommandWhileTheServerRunsIsRecognized() async throws {
    let directory = try scratch()
    let server = try await start(directory, openModem: away())
    let state = directory.appendingPathComponent("state.json").path
    let output = try await PairCommand.run(arguments: ["--name", "Phone", "--state", state], environment: ["HOME": directory.path], showsQRCode: false)
    let json = try #require(output.firstIndex(of: "{").flatMap { start in output.lastIndex(of: "}").map { String(output[start...$0]) } })
    let document = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    let token = try #require(document["credential"] as? String)
    #expect(try await server.request("/api/v1/health", password: gatewayPassword, bearer: token).status == 200)
    await server.stop()
  }

  @Test func aClientFileThatCannotBeReadStopsTheServerBeforeItListens() async throws {
    let directory = try scratch()
    try Data("garbage".utf8).write(to: FileClientPersistence.url(besideState: directory.appendingPathComponent("state.json").path))
    let environment = ["HOME": directory.path, "INSTEON_GATEWAY_PASSWORD": gatewayPassword, "INSTEON_HUB_USERNAME": "hub-user", "INSTEON_HUB_PASSWORD": "hub-secret-pass"]
    do {
      try await ServerRunner.run(arguments: ["--state", directory.appendingPathComponent("state.json").path, "--hub", "192.168.1.20"], environment: environment, openModem: away())
      Issue.record("the server should not start")
    } catch {
      #expect(ServerFailure(error).code == .clientFileUnusable)
    }
  }
}
