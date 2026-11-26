import Foundation
import InsteonHTTP
import Testing
@testable import InsteonServerSupport

@Suite(.timeLimit(.minutes(1)))
struct PairCommandTests {
  private func state() throws -> (path: String, environment: [String: String]) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("insteon-pair-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return (directory.appendingPathComponent("gateway.json").path, ["HOME": directory.path])
  }

  private func document(_ output: String) throws -> [String: Any] {
    let json = try #require(output.firstIndex(of: "{").flatMap { start in output.lastIndex(of: "}").map { String(output[start...$0]) } })
    return try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
  }

  @Test func pairingPrintsADocumentWhoseCredentialIsANewClient() async throws {
    let (path, environment) = try state()
    let output = try await PairCommand.run(arguments: ["--name", "Phone", "--state", path, "--port", "8123"], environment: environment, showsQRCode: false)
    let document = try document(output)
    #expect(document["version"] as? Int == 1)
    #expect(document["scope"] as? String == "control")
    #expect(document["name"] as? String == "Network")
    #expect(document["api"] as? String == "/api/v1")
    let routes = try #require(document["routes"] as? [[String: Any]])
    #expect(routes.count == 1)
    #expect(routes[0]["kind"] as? String == "lan")
    #expect(routes[0]["url"] as? String == "http://127.0.0.1:8123")

    let store = ClientStore(persistence: FileClientPersistence(url: FileClientPersistence.url(besideState: path)))
    let credential = try #require(document["credential"] as? String)
    let client = try #require(await store.authenticate(token: credential))
    #expect(client.name == "Phone")
    #expect(client.scope == .control)
    #expect(document["serviceId"] as? String == (try await store.serviceID()))
  }

  @Test func eachRunMakesAnotherClientAndTheServiceStaysTheSame() async throws {
    let (path, environment) = try state()
    let first = try document(try await PairCommand.run(arguments: ["--name", "Phone", "--state", path], environment: environment, showsQRCode: false))
    let second = try document(try await PairCommand.run(arguments: ["--name", "Phone", "--state", path], environment: environment, showsQRCode: false))
    #expect(first["credential"] as? String != second["credential"] as? String)
    #expect(first["serviceId"] as? String == second["serviceId"] as? String)
    let store = ClientStore(persistence: FileClientPersistence(url: FileClientPersistence.url(besideState: path)))
    #expect(try await store.clients().count == 2)
  }

  @Test func theScopeTheNetworkNameAndTheAdvertisedAddressAreOptions() async throws {
    let (path, environment) = try state()
    let output = try await PairCommand.run(arguments: ["--name", "Tablet", "--scope", "read", "--network-name", "Beach house", "--advertise-url", "https://insteon.example.net:8443/", "--state", path], environment: environment, showsQRCode: false)
    let document = try document(output)
    #expect(document["scope"] as? String == "read")
    #expect(document["name"] as? String == "Beach house")
    #expect((document["routes"] as? [[String: Any]])?.first?["url"] as? String == "https://insteon.example.net:8443")
  }

  @Test func theQRCodeFollowsTheDocumentOnlyWhenAsked() async throws {
    let (path, environment) = try state()
    let plain = try await PairCommand.run(arguments: ["--name", "Phone", "--state", path], environment: environment, showsQRCode: false)
    let withCode = try await PairCommand.run(arguments: ["--name", "Phone", "--state", path], environment: environment, showsQRCode: true)
    #expect(!plain.contains("\u{2580}") && !plain.contains("\u{2588}"))
    #expect(withCode.contains("\u{2580}"))
    let skipped = try await PairCommand.run(arguments: ["--name", "Phone", "--no-qr", "--state", path], environment: environment, showsQRCode: true)
    #expect(!skipped.contains("\u{2580}"))
  }

  @Test(arguments: [
    [], ["--name"], ["--name", ""], ["--name", "Phone", "--name", "Tablet"], ["--name", "Phone", "--scope", "root"],
    ["--name", "Phone", "--advertise-url", "ftp://insteon.local"], ["--name", "Phone", "--advertise-url", "http://user:pw@insteon.local"],
    ["--name", "Phone", "--advertise-url", "http://insteon.local/path?x=1"], ["--name", "Phone", "--hub", "192.168.1.20"],
    ["--name", "Phone", "--listen", "8.8.8.8"], ["--name", String(repeating: "x", count: 65)]
  ])
  func aMistakenCommandLineIsRefusedAndMakesNoClient(_ arguments: [String]) async throws {
    let (path, environment) = try state()
    await #expect(throws: (any Error).self) { try await PairCommand.run(arguments: arguments + ["--state", path], environment: environment, showsQRCode: false) }
    let store = ClientStore(persistence: FileClientPersistence(url: FileClientPersistence.url(besideState: path)))
    #expect(try await store.clients().isEmpty)
  }

  @Test func theClientFileThatCannotBeReadIsReportedWithTheFileToFix() async throws {
    let (path, environment) = try state()
    try Data("garbage".utf8).write(to: FileClientPersistence.url(besideState: path))
    do {
      _ = try await PairCommand.run(arguments: ["--name", "Phone", "--state", path], environment: environment, showsQRCode: false)
      Issue.record("pairing should have failed")
    } catch {
      let failure = ServerFailure(error)
      #expect(failure.code == .clientFileUnusable)
      #expect(failure.message.contains("gateway-clients.json"))
      #expect(failure.exitStatus == ServerFailure.configurationStatus)
    }
  }
}
