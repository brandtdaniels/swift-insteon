import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonClient
import InsteonNetworking
import InsteonService
import Testing

private let token = "tok-5d10-invented"

private func pairing(id: String = "svc-1", name: String = "Example Network", credential: String = token, routes: String = #"[{"kind":"lan","url":"http://192.0.2.20:8080"}]"#) throws -> ClientPairing {
  try ClientPairing(decoding: Data(#"{"version":1,"serviceId":"\#(id)","name":"\#(name)","credential":"\#(credential)","scope":"control","api":"/api/v1","routes":\#(routes)}"#.utf8))
}

private func scratchDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent("insteon-client-tests-" + UUID().uuidString)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

private let healthy = json(#"{"version":1,"status":"ready","modem":{"connected":true,"cause":null}}"#)
private let oneDevice = json(#"{"version":1,"devices":[{"address":"1A.2B.3C","productName":"Example Dimmer","canTurnOnAndOff":true,"canDim":true,"value":1,"lastAnsweredAt":null}],"stale":false,"cause":null}"#)

@Suite("PairingStore keeps pairings, with the credential in a secret store", .timeLimit(.minutes(1)))
struct PairingStoreTests {

  @Test func aSavedPairingComesBackWithEverythingItHeld() async throws {
    let directory = try scratchDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PairingStore(directory: directory, secrets: InMemorySecretStore())

    try await store.save(pairing())
    let loaded = try await store.load()

    #expect(loaded.count == 1)
    #expect(loaded[0].serviceID == "svc-1")
    #expect(loaded[0].name == "Example Network")
    #expect(loaded[0].scope == "control")
    #expect(loaded[0].routes == [ClientPairing.Route(kind: "lan", url: "http://192.0.2.20:8080", ticket: nil)])
  }

  @Test func theCredentialIsInTheSecretStoreAndNeverInTheFile() async throws {
    let directory = try scratchDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let secrets = InMemorySecretStore()
    let store = PairingStore(directory: directory, secrets: secrets)

    try await store.save(pairing())

    #expect(await secrets.accounts().count == 1)
    for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
      let text = String(decoding: try Data(contentsOf: file), as: UTF8.self)
      #expect(!text.contains(token))
    }
  }

  @Test func savingAgainForTheSameServiceReplacesIt() async throws {
    let directory = try scratchDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PairingStore(directory: directory, secrets: InMemorySecretStore())

    try await store.save(pairing(name: "Old"))
    try await store.save(pairing(name: "Renamed"))

    #expect(try await store.load().map(\.name) == ["Renamed"])
  }

  @Test func pairingsAreKeptInTheOrderTheyWereAdded() async throws {
    let directory = try scratchDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PairingStore(directory: directory, secrets: InMemorySecretStore())

    try await store.save(pairing(id: "a"))
    try await store.save(pairing(id: "b"))

    #expect(try await store.load().map(\.serviceID) == ["a", "b"])
  }

  @Test func removingAPairingRemovesItsCredentialToo() async throws {
    let directory = try scratchDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let secrets = InMemorySecretStore()
    let store = PairingStore(directory: directory, secrets: secrets)
    try await store.save(pairing(id: "a"))
    try await store.save(pairing(id: "b"))

    try await store.remove(serviceID: "a")

    #expect(try await store.load().map(\.serviceID) == ["b"])
    #expect(await secrets.accounts().count == 1)
  }

  @Test func removingAPairingThatIsNotThereChangesNothing() async throws {
    let directory = try scratchDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PairingStore(directory: directory, secrets: InMemorySecretStore())
    try await store.save(pairing())

    try await store.remove(serviceID: "other")

    #expect(try await store.load().count == 1)
  }

  @Test func aStoreWithNothingSavedLoadsNothing() async throws {
    let directory = try scratchDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    #expect(try await PairingStore(directory: directory, secrets: InMemorySecretStore()).load().isEmpty)
  }

  @Test func aPairingWhoseCredentialIsGoneIsLeftOutOfWhatLoads() async throws {
    let directory = try scratchDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = InMemorySecretStore()
    try await PairingStore(directory: directory, secrets: first).save(pairing())

    #expect(try await PairingStore(directory: directory, secrets: InMemorySecretStore()).load().isEmpty)
  }

  @Test func aFileThatIsNotAPairingListIsReportedNotReplaced() async throws {
    let directory = try scratchDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PairingStore(directory: directory, secrets: InMemorySecretStore())
    try await store.save(pairing())
    let file = try #require(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
    try Data("garbage".utf8).write(to: file)

    await #expect(throws: PairingStore.Failure.unreadable) { _ = try await store.load() }
    await #expect(throws: PairingStore.Failure.unreadable) { try await store.save(pairing(id: "z")) }
    #expect(String(decoding: try Data(contentsOf: file), as: UTF8.self) == "garbage")
  }

  @Test func theFileIsReadableOnlyByItsOwner() async throws {
    let directory = try scratchDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try await PairingStore(directory: directory, secrets: InMemorySecretStore()).save(pairing())

    let file = try #require(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
    let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
    #expect(permissions == 0o600)
  }

  /// The first acceptance test: a pairing saved, loaded and turned into paths answers a call
  /// through a ClientConnection against a scripted service.
  @Test func aSavedPairingReachesTheServiceThroughAConnection() async throws {
    let directory = try scratchDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PairingStore(directory: directory, secrets: InMemorySecretStore())
    try await store.save(pairing(routes: #"[{"kind":"example-transport","ticket":"t1"},{"kind":"lan","url":"http://192.0.2.20:8080"}]"#))
    let http = FakeHTTPClient { request in
      switch (request.url?.host, request.url?.path) {
      case ("192.0.2.20", "/api/v1/health"): healthy
      case ("192.0.2.20", _): oneDevice
      default: throw Unplugged()
      }
    }

    let saved = try #require(try await store.load().first)
    let connection = ClientConnection(paths: saved.paths(transports: [ForwardingOpener(kind: "example-transport", forwardTo: nil)], http: http))
    let devices = try await connection.devices()

    #expect(devices.count == 1)
    #expect(await connection.currentPath == "lan")
    for request in await http.requests {
      #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer " + token)
    }
  }
}
