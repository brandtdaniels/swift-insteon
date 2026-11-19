import Foundation
import InsteonHTTP
import Testing
@testable import InsteonServerSupport

@Suite(.timeLimit(.minutes(1)))
struct ClientFileTests {
  private func directory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("insteon-client-file-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  @Test func theClientFileSitsBesideTheStateFileUnderItsOwnName() {
    #expect(FileClientPersistence.url(besideState: "/var/lib/insteon/gateway.json").path == "/var/lib/insteon/gateway-clients.json")
    #expect(FileClientPersistence.url(besideState: "/tmp/other.state").path == "/tmp/other-clients.json")
    #expect(FileClientPersistence.url(besideState: "/tmp/noextension").path == "/tmp/noextension-clients.json")
  }

  @Test func clientsSurviveARestartAndTheFileHoldsNoToken() async throws {
    let url = try directory().appendingPathComponent("clients.json")
    let first = ClientStore(persistence: FileClientPersistence(url: url))
    let issued = try await first.issue(name: "Phone", scope: .control)
    let serviceID = try await first.serviceID()
    let second = ClientStore(persistence: FileClientPersistence(url: url))
    #expect(await second.authenticate(token: issued.token) == issued.client)
    #expect(try await second.serviceID() == serviceID)
    let text = try String(contentsOf: url, encoding: .utf8)
    let secret = try #require(issued.token.split(separator: ".").last.map(String.init))
    #expect(!text.contains(secret))
    #expect(text.contains("\"hash\""))
    #expect(text.contains("\"salt\""))
  }

  @Test func theFileAndItsDirectoryAreReadableOnlyByTheCurrentUser() async throws {
    let url = try directory().appendingPathComponent("created").appendingPathComponent("clients.json")
    _ = try await ClientStore(persistence: FileClientPersistence(url: url)).issue(name: "Phone", scope: .read)
    let file = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
    let parent = try FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path)[.posixPermissions] as? Int
    #expect(file == 0o600)
    #expect(parent == 0o700)
  }

  @Test func aFileThatCannotBeReadIsLeftAsItIsAndNothingIsIssued() async throws {
    let url = try directory().appendingPathComponent("clients.json")
    let garbage = Data("not a registry".utf8)
    try garbage.write(to: url)
    let store = ClientStore(persistence: FileClientPersistence(url: url))
    await #expect(throws: ClientError.notSaved) { try await store.issue(name: "Phone", scope: .read) }
    #expect(try Data(contentsOf: url) == garbage)
  }

  @Test func aFileInANewerFormatIsLeftAsItIs() async throws {
    let url = try directory().appendingPathComponent("clients.json")
    let newer = Data(#"{"version":2,"serviceId":"abc","clients":[]}"#.utf8)
    try newer.write(to: url)
    let store = ClientStore(persistence: FileClientPersistence(url: url))
    await #expect(throws: ClientError.notSaved) { try await store.issue(name: "Phone", scope: .read) }
    #expect(try Data(contentsOf: url) == newer)
  }

  @Test func aSymbolicLinkIsNotFollowed() async throws {
    let directory = try directory()
    let target = directory.appendingPathComponent("elsewhere.json")
    try Data(#"{"version":1,"serviceId":"abc","clients":[]}"#.utf8).write(to: target)
    let link = directory.appendingPathComponent("clients.json")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    let store = ClientStore(persistence: FileClientPersistence(url: link))
    await #expect(throws: ClientError.notSaved) { try await store.issue(name: "Phone", scope: .read) }
  }
}
