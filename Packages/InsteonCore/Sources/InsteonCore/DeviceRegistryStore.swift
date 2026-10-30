/// Somewhere an app keeps a ``DeviceRegistry``'s devices between launches.
///
/// ``JSONFileDeviceRegistryStore`` keeps them in a JSON file. An app can conform its own type
/// to keep them elsewhere.
///
/// ```swift
/// let store: any DeviceRegistryStore = JSONFileDeviceRegistryStore(fileURL: url)
/// let registry = DeviceRegistry(catalog: catalog, snapshot: try await store.load())
///
/// await registry.record(identity, for: lamp)
/// try await store.save(await registry.snapshot)
/// ```
public protocol DeviceRegistryStore: Sendable {

  /// Reads the devices the store keeps.
  ///
  /// - Returns: The devices, or an empty snapshot if the store keeps none yet.
  /// - Throws: An error if the store has devices that can't be read.
  func load() async throws -> DeviceRegistrySnapshot

  /// Keeps the devices in a snapshot, replacing the ones the store kept.
  ///
  /// - Parameter snapshot: The devices to keep.
  /// - Throws: An error if they couldn't be kept.
  func save(_ snapshot: DeviceRegistrySnapshot) async throws

}
