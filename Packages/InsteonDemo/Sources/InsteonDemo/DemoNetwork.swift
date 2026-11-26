import Foundation
import InsteonCore
import InsteonDeviceCatalog
import InsteonProtocol
import InsteonService

/// A made-up Insteon network for an app to run on when no Hub is at hand.
///
/// It has a few devices, each named and identified by an invented catalog, and a few scenes
/// made of ALL-Link records. Nothing leaves the process, and the products are not real.
///
/// ```swift
/// let service = DemoNetwork.make()
/// let devices = try await service.devices()
/// ```
public enum DemoNetwork {

  /// A made-up ALL-Link group and the devices that respond to it.
  struct Scene: Sendable, Equatable {

    /// The ALL-Link group.
    let group: AllLinkGroupNumber

    /// The devices that respond to the group.
    let members: [InsteonAddress]

  }

  /// A made-up device.
  struct Device: Sendable, Equatable {

    /// The device's address.
    let address: InsteonAddress

    /// What the device reports about itself.
    let identity: ReportedIdentity

  }

  /// The modem's address.
  public static let modem = InsteonAddress(0x7E, 0x00, 0x01)

  /// A demo dimmer.
  public static let lamp = InsteonAddress(0x7E, 0x00, 0x10)

  /// A second demo dimmer.
  public static let ceiling = InsteonAddress(0x7E, 0x00, 0x11)

  /// A demo relay.
  public static let outlet = InsteonAddress(0x7E, 0x00, 0x12)

  /// The demo devices, in the order the service lists them.
  static let devices: [Device] = [
    Device(address: lamp, identity: DemoCatalog.dimmerIdentity),
    Device(address: ceiling, identity: DemoCatalog.dimmerIdentity),
    Device(address: outlet, identity: DemoCatalog.relayIdentity)
  ]

  /// The demo scenes.
  static let scenes: [Scene] = [
    Scene(group: 20, members: [lamp, ceiling]),
    Scene(group: 21, members: [lamp, outlet])
  ]

  /// A service over a demo network, with every device off.
  ///
  /// Each call makes its own network, so one holds no state of another.
  public static func make() -> InsteonService {

    let identities: [InsteonAddress: ReportedIdentity] = Dictionary(uniqueKeysWithValues: devices.map { ($0.address, $0.identity) })
    let snapshot = NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: identities))
    let network = DeviceNetwork(modem: DemoModem(), catalog: DemoCatalog.catalog, snapshot: snapshot)

    return InsteonService(network: network)

  }

}
