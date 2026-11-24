import Foundation
import Testing
@testable import InsteonHTTP

/// A persistence that records what it was asked to keep and can refuse.
final class RecordingRoutePersistence: RoutePersisting, @unchecked Sendable {
  struct Refused: Error {}
  private let lock = NSLock()
  private var registry: RouteRegistry?
  private var refusesReads = false
  private var refusesWrites = false

  init(_ registry: RouteRegistry? = nil) { self.registry = registry }

  func refuse(reads: Bool = false, writes: Bool = false) { lock.withLock { refusesReads = reads; refusesWrites = writes } }
  var stored: RouteRegistry? { lock.withLock { registry } }

  func load() throws -> RouteRegistry? {
    try lock.withLock {
      if refusesReads { throw Refused() }
      return registry
    }
  }

  func save(_ registry: RouteRegistry) throws {
    try lock.withLock {
      if refusesWrites { throw Refused() }
      self.registry = registry
    }
  }
}

/// Registering, replacing and removing the routes a pairing document lists after the LAN route.
@Suite(.timeLimit(.minutes(1)))
struct RouteStoreTests {
  @Test func routesComeBackInTheOrderTheyWereRegistered() async throws {
    let store = RouteStore(persistence: RecordingRoutePersistence())
    _ = try await store.put(kind: "zeta", ticket: "z")
    _ = try await store.put(kind: "alpha", ticket: "a")
    #expect(try await store.routes().map(\.kind) == ["zeta", "alpha"])
  }

  @Test func registeringAKindAgainReplacesItsTicketInPlace() async throws {
    let store = RouteStore(persistence: RecordingRoutePersistence())
    _ = try await store.put(kind: "first", ticket: "one")
    _ = try await store.put(kind: "second", ticket: "two")
    _ = try await store.put(kind: "first", ticket: "uno")
    #expect(try await store.routes() == [RegisteredRoute(kind: "first", ticket: "uno"), RegisteredRoute(kind: "second", ticket: "two")])
  }

  @Test func removingAKindKeepsTheOthersInOrder() async throws {
    let store = RouteStore(persistence: RecordingRoutePersistence())
    for kind in ["a", "b", "c"] { _ = try await store.put(kind: kind, ticket: kind) }
    try await store.remove(kind: "b")
    #expect(try await store.routes().map(\.kind) == ["a", "c"])
  }

  @Test func removingAKindThatIsNotRegisteredIsRefused() async throws {
    let store = RouteStore(persistence: RecordingRoutePersistence())
    await #expect(throws: RouteError.unknownRoute) { try await store.remove(kind: "ghost") }
  }

  @Test(arguments: ["", "Upper", "1starts-with-digit", "has space", "under_score", "lan", "dot.ted", "-dash", String(repeating: "a", count: 33)])
  func aKindThatIsNotAShortLowercaseIdentifierIsRefusedAndStoresNothing(_ kind: String) async throws {
    let persistence = RecordingRoutePersistence()
    let store = RouteStore(persistence: persistence)
    await #expect(throws: RouteError.invalidRoute) { try await store.put(kind: kind, ticket: "t") }
    #expect(persistence.stored == nil)
  }

  @Test(arguments: ["a", "loopback", "tail-scale", "iroh2", String(repeating: "a", count: 32)])
  func aShortLowercaseIdentifierIsAccepted(_ kind: String) async throws {
    let store = RouteStore(persistence: RecordingRoutePersistence())
    #expect(try await store.put(kind: kind, ticket: "t").kind == kind)
  }

  @Test(arguments: ["", "line\nbreak", "tab\there", "nul\u{0}byte", "has space", "t\u{EF}cket", String(repeating: "t", count: 1025)])
  func aTicketThatIsEmptyHasAnythingButPrintableASCIIOrIsTooLargeIsRefused(_ ticket: String) async throws {
    let store = RouteStore(persistence: RecordingRoutePersistence())
    await #expect(throws: RouteError.invalidRoute) { try await store.put(kind: "loopback", ticket: ticket) }
    #expect(try await store.routes().isEmpty)
  }

  @Test func aTicketOfTheLargestSizeIsAccepted() async throws {
    let store = RouteStore(persistence: RecordingRoutePersistence())
    _ = try await store.put(kind: "loopback", ticket: String(repeating: "t", count: RouteStore.longestTicket))
    #expect(try await store.routes().count == 1)
  }

  @Test func theNumberOfRoutesIsLimitedButReplacingOneAtTheLimitIsNot() async throws {
    let store = RouteStore(persistence: RecordingRoutePersistence())
    for index in 0..<RouteStore.maximumRoutes { _ = try await store.put(kind: "kind" + String(index), ticket: "t") }
    await #expect(throws: RouteError.limitReached) { try await store.put(kind: "extra", ticket: "t") }
    _ = try await store.put(kind: "kind0", ticket: "changed")
    #expect(try await store.routes().count == RouteStore.maximumRoutes)
  }

  @Test func aRouteAnotherProcessStoredIsSeenAtOnce() async throws {
    let persistence = RecordingRoutePersistence()
    let store = RouteStore(persistence: persistence)
    #expect(try await store.routes().isEmpty)
    try persistence.save(RouteRegistry(routes: [RegisteredRoute(kind: "elsewhere", ticket: "t")]))
    #expect(try await store.routes().map(\.kind) == ["elsewhere"])
  }

  @Test func aFailedSaveChangesNothingAndIsReported() async throws {
    let persistence = RecordingRoutePersistence()
    let store = RouteStore(persistence: persistence)
    _ = try await store.put(kind: "kept", ticket: "t")
    persistence.refuse(writes: true)
    await #expect(throws: RouteError.notSaved) { try await store.put(kind: "lost", ticket: "t") }
    await #expect(throws: RouteError.notSaved) { try await store.remove(kind: "kept") }
    persistence.refuse(writes: false)
    #expect(try await store.routes().map(\.kind) == ["kept"])
  }

  @Test func aStoreThatCannotReadReportsItInsteadOfShowingNoRoutes() async throws {
    let persistence = RecordingRoutePersistence(RouteRegistry(routes: [RegisteredRoute(kind: "kept", ticket: "t")]))
    persistence.refuse(reads: true)
    let store = RouteStore(persistence: persistence)
    await #expect(throws: RouteError.notSaved) { try await store.routes() }
  }

  @Test func withoutPersistenceTheRoutesLastForTheLifeOfTheStore() async throws {
    let store = RouteStore()
    _ = try await store.put(kind: "loopback", ticket: "t")
    #expect(try await store.routes().map(\.kind) == ["loopback"])
  }
}
