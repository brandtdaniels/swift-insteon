/// Somewhere an app keeps a ``DeviceNetwork``'s ``NetworkSnapshot`` between launches.
///
/// ``JSONFileDeviceRegistryStore`` keeps it in a JSON file. An app can conform its own type to
/// keep it elsewhere.
///
/// ```swift
/// let store: any NetworkSnapshotStore = JSONFileDeviceRegistryStore(fileURL: url)
/// let network = session.network(catalog: catalog, snapshot: try await store.loadNetwork(), hub: session.hub)
///
/// _ = try await network.allLinkDatabase(of: lamp)
/// try await store.saveNetwork(await network.snapshot())
/// ```
public protocol NetworkSnapshotStore: Sendable {

  /// Reads the snapshot the store keeps.
  ///
  /// - Returns: The snapshot, or an empty one if the store keeps none yet.
  /// - Throws: An error if the store has a snapshot that can't be read.
  func loadNetwork() async throws -> NetworkSnapshot

  /// Keeps a snapshot, replacing the one the store kept.
  ///
  /// - Parameter snapshot: The snapshot to keep.
  /// - Throws: An error if it couldn't be kept.
  func saveNetwork(_ snapshot: NetworkSnapshot) async throws

}
