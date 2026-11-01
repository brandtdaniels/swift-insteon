import InsteonDeviceCatalog
import InsteonProtocol

/// A device a ``DeviceRegistry`` knows: its address, the identity it reported, and what the
/// Insteon device catalog says about that identity.
///
/// ```swift
/// if let lamp = await registry.device(InsteonAddress(0x1A, 0x2B, 0x3C)) {
///   print(lamp.info.displayName ?? "\(lamp.identity.category)")
/// }
/// ```
public struct RegisteredDevice: Hashable, Sendable {

  /// The device's address.
  public var address: InsteonAddress

  /// The category, subcategory and firmware version the device reported.
  public var identity: ReportedIdentity

  /// What the registry's catalog says about the identity. A device the catalog doesn't have,
  /// or one described without a catalog, has no product.
  public var info: DeviceInfo

  /// Creates a registered device.
  ///
  /// - Parameters:
  ///   - address: The device's address.
  ///   - identity: The identity the device reported.
  ///   - info: What the catalog says about the identity.
  public init(address: InsteonAddress, identity: ReportedIdentity, info: DeviceInfo) {

    self.address = address
    self.identity = identity
    self.info = info

  }

  /// Creates a registered device from the catalog's description of its identity.
  init(address: InsteonAddress, identity: ReportedIdentity, deviceDescription: DeviceDescription) {

    self.init(address: address, identity: identity, info: DeviceInfo(deviceDescription))

  }

  /// The catalog's description of the identity.
  var deviceDescription: DeviceDescription {

    info.catalogDescription

  }

}
