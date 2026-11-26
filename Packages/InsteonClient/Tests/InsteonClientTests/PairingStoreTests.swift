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

/// A secret store whose saves wait until the test releases them, so an interleaving is exact.
private actor HeldSecretStore: SecretStore {
  private var secrets: [String: String] = [:]
  private var released = false
  private var waiting: [CheckedContinuation<Void, Never>] = []
  private var entered = 0
  private var enteredWaiter: CheckedContinuation<Void, Never>?

  func save(_ secret: String, account: String) async throws {
    entered += 1
    enteredWaiter?.resume()
    enteredWaiter = nil
    if !released { await withCheckedContinuation { waiting.append($0) } }
    secrets[account] = secret
  }

  func load(account: String) -> String? { secrets[account] }

  func remove(account: String) { secrets[account] = nil }

  func accounts() -> [String] { Array(secrets.keys) }

  /// Returns once a save has reached the store.
  func untilASaveHasEntered() async {
    if entered == 0 { await withCheckedContinuation { enteredWaiter = $0 } }
  }

  /// Lets every held save, and every later one, finish.
  func release() {
    released = true
    for continuation in waiting { continuation.resume() }
    waiting = []
  }
}

/// A secret store whose removals fail until told to work.
private actor FlakySecretStore: SecretStore {
  struct Down: Error {}
  private var secrets: [String: String] = [:]
  private var removing = false

  func save(_ secret: String, account: String) { secrets[account] = secret }
  func load(account: String) -> String? { secrets[account] }
  func remove(account: String) throws {
    if !removing { throw Down() }
    secrets[account] = nil
  }
  func accounts() -> [String] { Array(secrets.keys) }
  func allowRemoving() { removing = true }
}

/// Gives every task already started a chance to run to its next suspension.
private func letStartedTasksRun() async {
  for _ in 0..<100 { await Task.yield() }
}

private func pairingsFile(in directory: URL) -> URL { directory.appendingPathComponent("pairings.json") }

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

  @Test func twoSavesAtOnceForDifferentServicesKeepBoth() async throws {
    let directory = try scratchDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let secrets = HeldSecretStore()
    let store = PairingStore(directory: directory, secrets: secrets)

    let first = Task { try await store.save(pairing(id: "a")) }
    await secrets.untilASaveHasEntered()
    let second = Task { try await store.save(pairing(id: "b")) }
    await letStartedTasksRun()
    await secrets.release()
    try await first.value
    try await second.value

    #expect(Set(try await store.load().map(\.serviceID)) == ["a", "b"])
  }

  @Test func aSaveThatCannotWriteTheFileLeavesTheOldCredentialInPlace() async throws {
    let directory = try scratchDirectory()
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
      try? FileManager.default.removeItem(at: directory)
    }
    let secrets = InMemorySecretStore()
    let store = PairingStore(directory: directory, secrets: secrets)
    try await store.save(pairing(id: "a", credential: "old-credential"))
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)

    await #expect(throws: PairingStore.Failure.notSaved) { try await store.save(pairing(id: "a", credential: "new-credential")) }
    await #expect(throws: PairingStore.Failure.notSaved) { try await store.save(pairing(id: "b", credential: "other-credential")) }

    #expect(await secrets.load(account: "a") == "old-credential")
    #expect(await secrets.load(account: "b") == nil)
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

  @Test func aRemoveThatFailsOnTheSecretStoreCanBeRetriedToCompletion() async throws {
    let directory = try scratchDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let secrets = FlakySecretStore()
    let store = PairingStore(directory: directory, secrets: secrets)
    try await store.save(pairing(id: "a"))

    await #expect(throws: FlakySecretStore.Down.self) { try await store.remove(serviceID: "a") }
    await secrets.allowRemoving()
    try await store.remove(serviceID: "a")

    #expect(await secrets.accounts().isEmpty)
    #expect(try await store.load().isEmpty)
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
    let file = pairingsFile(in: directory)
    try Data("garbage".utf8).write(to: file)

    await #expect(throws: PairingStore.Failure.unreadable) { _ = try await store.load() }
    await #expect(throws: PairingStore.Failure.unreadable) { try await store.save(pairing(id: "z")) }
    #expect(String(decoding: try Data(contentsOf: file), as: UTF8.self) == "garbage")
  }

  @Test func theFileIsReadableOnlyByItsOwner() async throws {
    let directory = try scratchDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try await PairingStore(directory: directory, secrets: InMemorySecretStore()).save(pairing())

    let file = pairingsFile(in: directory)
    let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
    #expect(permissions == 0o600)
  }

  @Test func theFileIsNeverMoreOpenThanItsOwnerEvenWithAnOpenUmask() async throws {
    let directory = try scratchDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let before = umask(0)
    defer { umask(before) }

    let store = PairingStore(directory: directory, secrets: InMemorySecretStore())
    try await store.save(pairing())
    try await store.save(pairing(name: "Renamed"))

    let permissions = try FileManager.default.attributesOfItem(atPath: pairingsFile(in: directory).path)[.posixPermissions] as? Int
    #expect(permissions == 0o600)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["pairings.json"])
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
