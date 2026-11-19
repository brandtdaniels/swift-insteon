import Foundation
import Testing
@testable import InsteonHTTP

/// Bytes that count up, and a record of how many each request asked for.
actor CountingRandomness: RandomnessSource {
  private var next: UInt8 = 1
  private(set) var requested: [Int] = []

  func bytes(_ count: Int) -> [UInt8] {
    requested.append(count)
    defer { next &+= 1 }
    return [UInt8](repeating: next, count: count)
  }
}

/// A persistence that can be told to fail, and that shows what was written.
actor RecordingPersistence: ClientPersisting {
  struct Refused: Error {}
  private(set) var stored: ClientRegistry?
  private(set) var writes = 0
  var refusesWrites = false

  init(_ stored: ClientRegistry? = nil) { self.stored = stored }
  func refuseWrites(_ refuse: Bool) { refusesWrites = refuse }

  func load() async throws -> ClientRegistry? { stored }

  func save(_ registry: ClientRegistry) async throws {
    if refusesWrites { throw Refused() }
    stored = registry
    writes += 1
  }

  func text() -> String {
    guard let stored, let data = try? JSONEncoder().encode(stored) else { return "" }
    return String(decoding: data, as: UTF8.self)
  }
}

@Suite(.timeLimit(.minutes(1)))
struct ClientStoreTests {
  let clock = Date(timeIntervalSince1970: 1_800_000_000)

  private func store(_ persistence: any ClientPersisting = InMemoryClientPersistence(), randomness: any RandomnessSource = CountingRandomness()) -> ClientStore {
    ClientStore(persistence: persistence, now: { clock }, randomness: randomness)
  }

  // MARK: Issuing

  @Test func anIssuedClientIsReturnedOnceWithItsTokenAndIsListedWithoutIt() async throws {
    let store = store()
    let issued = try await store.issue(name: "Phone", scope: .control)
    #expect(issued.client.name == "Phone")
    #expect(issued.client.scope == .control)
    #expect(issued.client.createdAt == clock)
    #expect(!issued.token.isEmpty)
    let listed = try await store.clients()
    #expect(listed == [issued.client])
  }

  @Test func theTokenIsStoredOnlyAsASaltedHash() async throws {
    let persistence = RecordingPersistence()
    let store = store(persistence)
    let issued = try await store.issue(name: "Phone", scope: .read)
    let secret = try #require(issued.token.split(separator: ".").last.map(String.init))
    let text = await persistence.text()
    #expect(!text.isEmpty)
    #expect(!text.contains(issued.token))
    #expect(!text.contains(secret))
    let stored = try #require(await persistence.stored?.clients.first)
    #expect(!stored.salt.isEmpty)
    #expect(stored.hash.count == 32)
  }

  @Test func eachSecretComesFromThirtyTwoRandomBytesAndEachClientHasItsOwnSalt() async throws {
    let randomness = CountingRandomness()
    let persistence = RecordingPersistence()
    let store = store(persistence, randomness: randomness)
    let first = try await store.issue(name: "One", scope: .read)
    let second = try await store.issue(name: "Two", scope: .read)
    #expect(first.token != second.token)
    #expect(await randomness.requested.contains(32))
    let stored = try #require(await persistence.stored?.clients)
    #expect(stored[0].salt != stored[1].salt)
    #expect(stored[0].hash != stored[1].hash)
  }

  @Test(arguments: ["", "   ", String(repeating: "x", count: 65), "line\nbreak", "tab\tname"])
  func aNameThatIsEmptyTooLongOrHasControlCharactersIsRefused(_ name: String) async throws {
    let store = store()
    await #expect(throws: ClientError.invalidName) { try await store.issue(name: name, scope: .read) }
    #expect(try await store.clients().isEmpty)
  }

  @Test func theNameIsTrimmedAndTwoClientsMayShareOne() async throws {
    let store = store()
    let first = try await store.issue(name: "  Phone ", scope: .read)
    let second = try await store.issue(name: "Phone", scope: .read)
    #expect(first.client.name == "Phone")
    #expect(first.client.id != second.client.id)
  }

  @Test func theNumberOfClientsIsLimited() async throws {
    let store = store()
    for index in 0..<ClientStore.maximumClients { _ = try await store.issue(name: "C" + String(index), scope: .read) }
    await #expect(throws: ClientError.limitReached) { try await store.issue(name: "One too many", scope: .read) }
  }

  // MARK: Authenticating

  @Test func aTokenAuthenticatesItsClient() async throws {
    let store = store()
    let issued = try await store.issue(name: "Phone", scope: .control)
    #expect(await store.authenticate(token: issued.token) == issued.client)
  }

  @Test func anAlteredUnknownOrMalformedTokenAuthenticatesNobody() async throws {
    let store = store()
    let issued = try await store.issue(name: "Phone", scope: .control)
    let parts = issued.token.split(separator: ".").map(String.init)
    let altered = parts[0] + "." + String(parts[1].dropLast()) + (parts[1].hasSuffix("A") ? "B" : "A")
    for token in [altered, "ffffffffffffffff." + parts[1], parts[0], parts[0] + ".", "." + parts[1], "", String(repeating: "a", count: 5000), parts[0] + "." + parts[1] + "." + parts[1]] {
      #expect(await store.authenticate(token: token) == nil)
    }
  }

  @Test func aRevokedClientsTokenStopsWorkingAndItLeavesTheList() async throws {
    let store = store()
    let kept = try await store.issue(name: "Tablet", scope: .read)
    let revoked = try await store.issue(name: "Phone", scope: .control)
    try await store.revoke(id: revoked.client.id)
    #expect(await store.authenticate(token: revoked.token) == nil)
    #expect(await store.authenticate(token: kept.token) == kept.client)
    #expect(try await store.clients() == [kept.client])
  }

  @Test func revokingAnUnknownClientIsReported() async {
    let store = store()
    await #expect(throws: ClientError.unknownClient) { try await store.revoke(id: "nobody") }
  }

  @Test func rotatingGivesTheSameClientANewTokenAndEndsTheOldOne() async throws {
    let store = store()
    let issued = try await store.issue(name: "Phone", scope: .control)
    let rotated = try await store.rotate(id: issued.client.id)
    #expect(rotated.client == issued.client)
    #expect(rotated.token != issued.token)
    #expect(await store.authenticate(token: issued.token) == nil)
    #expect(await store.authenticate(token: rotated.token) == rotated.client)
    await #expect(throws: ClientError.unknownClient) { try await store.rotate(id: "nobody") }
  }

  // MARK: Persistence

  @Test func clientsSurviveARestartAndTheServiceIdentityStaysTheSame() async throws {
    let persistence = RecordingPersistence()
    let before = store(persistence)
    let issued = try await before.issue(name: "Phone", scope: .admin)
    let serviceID = try await before.serviceID()
    let after = store(persistence)
    #expect(await after.authenticate(token: issued.token) == issued.client)
    #expect(try await after.serviceID() == serviceID)
    #expect(serviceID.count == 32)
  }

  @Test func aClientIssuedByAnotherProcessIsRecognizedAndRevokingDoesNotLoseIt() async throws {
    let persistence = RecordingPersistence()
    let running = store(persistence)
    let fromRunning = try await running.issue(name: "Tablet", scope: .read)
    let other = store(persistence)
    let fromOther = try await other.issue(name: "Phone", scope: .control)
    #expect(await running.authenticate(token: fromOther.token) == fromOther.client)
    try await running.revoke(id: fromRunning.client.id)
    #expect(await other.authenticate(token: fromOther.token) == fromOther.client)
    #expect(try await other.clients() == [fromOther.client])
  }

  @Test func aFailedSaveLeavesNothingIssuedRevokedOrRotated() async throws {
    let persistence = RecordingPersistence()
    let store = store(persistence)
    let issued = try await store.issue(name: "Phone", scope: .control)
    await persistence.refuseWrites(true)
    await #expect(throws: ClientError.notSaved) { try await store.issue(name: "Tablet", scope: .read) }
    await #expect(throws: ClientError.notSaved) { try await store.revoke(id: issued.client.id) }
    await #expect(throws: ClientError.notSaved) { try await store.rotate(id: issued.client.id) }
    #expect(try await store.clients() == [issued.client])
    #expect(await store.authenticate(token: issued.token) == issued.client)
  }

  @Test func aRegistryThatCannotBeReadFailsClosed() async throws {
    let store = store(UnreadablePersistence())
    #expect(await store.authenticate(token: "anything.atAll") == nil)
    await #expect(throws: ClientError.notSaved) { try await store.issue(name: "Phone", scope: .read) }
  }

  // MARK: Scopes

  @Test func aScopeAllowsItselfAndTheOnesBelowIt() {
    #expect(ClientScope.admin.allows(.control) && ClientScope.admin.allows(.read) && ClientScope.admin.allows(.admin))
    #expect(ClientScope.control.allows(.read) && ClientScope.control.allows(.control) && !ClientScope.control.allows(.admin))
    #expect(ClientScope.read.allows(.read) && !ClientScope.read.allows(.control) && !ClientScope.read.allows(.admin))
  }

  @Test func theComparisonOfTwoDigestsReadsEveryByte() {
    #expect(SecureDigest.matches([1, 2, 3], [1, 2, 3]))
    #expect(!SecureDigest.matches([1, 2, 3], [1, 2, 4]))
    #expect(!SecureDigest.matches([9, 2, 3], [1, 2, 3]))
    #expect(!SecureDigest.matches([1, 2], [1, 2, 3]))
  }
}

private struct UnreadablePersistence: ClientPersisting {
  struct Unreadable: Error {}
  func load() async throws -> ClientRegistry? { throw Unreadable() }
  func save(_ registry: ClientRegistry) async throws { throw Unreadable() }
}

/// Gives other callers a turn between reading and writing, as a file system does.
private actor YieldingPersistence: ClientPersisting {
  private var registry: ClientRegistry?
  func load() async throws -> ClientRegistry? {
    for _ in 0..<5 { await Task.yield() }
    return registry
  }
  func save(_ registry: ClientRegistry) async throws {
    for _ in 0..<5 { await Task.yield() }
    self.registry = registry
  }
}

extension ClientStoreTests {
  @Test func changesMadeAtTheSameTimeAreAllKept() async throws {
    let store = ClientStore(persistence: YieldingPersistence())
    try await withThrowingTaskGroup(of: Void.self) { group in
      for index in 0..<8 { group.addTask { _ = try await store.issue(name: "C" + String(index), scope: .read) } }
      try await group.waitForAll()
    }
    #expect(try await store.clients().count == 8)
  }
}
