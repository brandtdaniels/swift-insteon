import InsteonDeviceCatalog
import InsteonProtocol

/// A device a ``DeviceRegistry`` knows: its address, the identity it reported, and what the
/// Insteon device catalog says about that identity.
///
/// ```swift
/// if let lamp = await registry.device(InsteonAddress(0x1A, 0x2B, 0x3C)) {
///   print(lamp.deviceDescription.displayName ?? "\(lamp.identity.category)")
/// }
/// ```
public struct RegisteredDevice: Hashable, Sendable {

  /// The device's address.
  public var address: InsteonAddress

  /// The category, subcategory and firmware version the device reported.
  public var identity: ReportedIdentity

  /// What the registry's catalog says about the identity. A device the catalog doesn't have,
  /// or one described without a catalog, has a description with no profile.
  public var deviceDescription: DeviceDescription

  /// Creates a registered device.
  ///
  /// - Parameters:
  ///   - address: The device's address.
  ///   - identity: The identity the device reported.
  ///   - deviceDescription: What the catalog says about the identity.
  public init(address: InsteonAddress, identity: ReportedIdentity, deviceDescription: DeviceDescription) {

    self.address = address
    self.identity = identity
    self.deviceDescription = deviceDescription

  }

}
