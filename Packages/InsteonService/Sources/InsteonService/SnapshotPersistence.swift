import InsteonCore

/// A snapshot persistence policy that reports health without changing an execution result.
public protocol SnapshotPersisting: Sendable {
  /// Saves a snapshot and reports failure without throwing away a known device outcome.
  func save(_ snapshot: NetworkSnapshot) async -> PersistenceOutcome
}

/// Adapts an existing snapshot store to the service's persistence-health contract.
public struct NetworkSnapshotPersistence: SnapshotPersisting {
  private let store: any NetworkSnapshotStore

  /// Creates a policy around a store, such as InsteonCore's protected JSON file store.
  public init(store: any NetworkSnapshotStore) { self.store = store }

  /// Attempts one save. Errors are redacted into a failed persistence outcome.
  public func save(_ snapshot: NetworkSnapshot) async -> PersistenceOutcome {
    do {
      try await store.saveNetwork(snapshot)
      return .saved
    } catch {
      return .failed
    }
  }
}
