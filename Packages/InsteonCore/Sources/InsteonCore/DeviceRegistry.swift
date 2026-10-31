import InsteonDeviceCatalog
import InsteonProtocol

/// The devices an app knows, each with the identity it reported and what the Insteon device
/// catalog says about that identity.
///
/// The registry only keeps what it's told: it never sends anything to a modem or a device, so
/// a call never waits on one. Record the identity a device reports, such as its answer to ID
/// Request or the modem's ALL-Linking Completed report, and look the device up later by its
/// address:
///
/// ```swift
/// let registry = DeviceRegistry(catalog: try DeviceCatalog.bundled())
/// let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)
///
/// await registry.record(ReportedIdentity(category: 0x01, subcategory: 0x20, firmwareVersion: 0x45), for: lamp)
///
/// let known = await registry.device(lamp)
/// print(known?.info.displayName ?? "unknown product")
/// ```
///
/// Each device's description comes from the registry's catalog. Setting a newer catalog with
/// ``setCatalog(_:)`` describes every device again from the identity it reported, so no device
/// is lost when the catalog changes.
///
/// To keep the devices between launches, save ``snapshot`` with a ``DeviceRegistryStore`` and
/// create the next registry with ``init(catalog:snapshot:)``.
public actor DeviceRegistry {

  /// The catalog devices are described with, or `nil` to describe them by their identities
  /// alone.
  public private(set) var catalog: DeviceCatalog?

  private var registered: [InsteonAddress: RegisteredDevice]

  /// Creates a registry.
  ///
  /// - Parameters:
  ///   - catalog: The catalog to describe devices with, or `nil` to describe them by their
  ///     identities alone, as when the catalog couldn't be loaded.
  ///   - snapshot: The devices to start with, such as ones a ``DeviceRegistryStore`` loaded.
  ///     Defaults to none.
  public init(catalog: DeviceCatalog?, snapshot: DeviceRegistrySnapshot = DeviceRegistrySnapshot()) {

    var registered: [InsteonAddress: RegisteredDevice] = [:]

    for (address, identity) in snapshot.identities {

      registered[address] = Self.describe(address, identity, catalog: catalog)

    }

    self.catalog = catalog
    self.registered = registered

  }

  /// Records the identity a device reported, replacing any identity recorded for it before.
  ///
  /// - Parameters:
  ///   - identity: The category, subcategory and firmware version the device reported.
  ///   - device: The device's address.
  /// - Returns: The device, described with the registry's catalog.
  @discardableResult
  public func record(_ identity: ReportedIdentity, for device: InsteonAddress) -> RegisteredDevice {

    let entry: RegisteredDevice = Self.describe(device, identity, catalog: catalog)
    registered[device] = entry

    return entry

  }

  /// The device at an address, if its identity is recorded.
  ///
  /// - Parameter address: The device's address.
  /// - Returns: The device, or `nil` if the registry doesn't know it.
  public func device(_ address: InsteonAddress) -> RegisteredDevice? {

    registered[address]

  }

  /// Every device the registry knows, in address order.
  public var devices: [RegisteredDevice] {

    registered.values.sorted { (first: RegisteredDevice, second: RegisteredDevice) -> Bool in

      first.address.bytes.lexicographicallyPrecedes(second.address.bytes)

    }

  }

  /// Forgets a device, such as one removed from the network.
  ///
  /// - Parameter address: The device's address.
  /// - Returns: The device that was forgotten, or `nil` if the registry didn't know it.
  @discardableResult
  public func forget(_ address: InsteonAddress) -> RegisteredDevice? {

    registered.removeValue(forKey: address)

  }

  /// Describes every device with another catalog, such as a newer copy an app downloaded.
  ///
  /// Each device keeps the identity it reported, so a device the catalog doesn't have is
  /// still known, with a description that has no profile.
  ///
  /// - Parameter catalog: The catalog, or `nil` to describe devices by their identities alone.
  public func setCatalog(_ catalog: DeviceCatalog?) {

    self.catalog = catalog

    for (address, entry) in registered {

      registered[address] = Self.describe(address, entry.identity, catalog: catalog)

    }

  }

  /// The registry's devices, as a value to save and restore with ``init(catalog:snapshot:)``.
  public var snapshot: DeviceRegistrySnapshot {

    var identities: [InsteonAddress: ReportedIdentity] = [:]

    for (address, entry) in registered {

      identities[address] = entry.identity

    }

    return DeviceRegistrySnapshot(identities: identities)

  }

  private static func describe(_ address: InsteonAddress, _ identity: ReportedIdentity, catalog: DeviceCatalog?) -> RegisteredDevice {

    let description = DeviceDescription(
      category: identity.category,
      subcategory: identity.subcategory,
      firmwareVersion: identity.firmwareVersion,
      catalog: catalog
    )

    return RegisteredDevice(address: address, identity: identity, deviceDescription: description)

  }

}
