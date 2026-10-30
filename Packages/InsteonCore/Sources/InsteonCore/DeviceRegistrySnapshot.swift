import InsteonProtocol

/// What a ``DeviceRegistry`` holds, as a value an app can save and give back to a registry
/// later, such as through a ``DeviceRegistryStore``.
///
/// A snapshot holds only device addresses and the identities the devices reported. It never
/// holds credentials, names or rooms.
///
/// ```swift
/// let snapshot = await registry.snapshot
/// try await store.save(snapshot)
///
/// let restored = DeviceRegistry(catalog: catalog, snapshot: try await store.load())
/// ```
public struct DeviceRegistrySnapshot: Hashable, Sendable {

  /// The identities the devices reported, by device.
  public var identities: [InsteonAddress: ReportedIdentity]

  /// Creates a snapshot.
  ///
  /// - Parameter identities: The identities the devices reported, by device. Defaults to none.
  public init(identities: [InsteonAddress: ReportedIdentity] = [:]) {

    self.identities = identities

  }

  /// Whether the snapshot holds no devices.
  public var isEmpty: Bool {

    identities.isEmpty

  }

}
