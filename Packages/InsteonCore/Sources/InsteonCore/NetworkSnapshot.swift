import Foundation
import InsteonLinking
import InsteonProtocol

/// What a ``DeviceNetwork`` knows, as a value an app can save and give back to a network
/// later, such as through a ``NetworkSnapshotStore``.
///
/// A snapshot holds the identities the devices reported, as a ``DeviceRegistrySnapshot``, and
/// beside them what the network learned about each device and the modem: each device's engine,
/// a copy of its ALL-Link database with the delta it was read at, its last known level and when
/// it last answered, the modem's ALL-Link database, and the Hub the modem was reached through.
/// It never holds credentials, the Hub's MAC address, names or rooms.
///
/// ```swift
/// let snapshot = await network.snapshot()
/// try store.saveNetwork(snapshot)
///
/// let restored = DeviceNetwork(modem: modem, catalog: catalog, snapshot: try store.loadNetwork())
/// ```
public struct NetworkSnapshot: Hashable, Sendable {

  /// The identities the devices reported.
  public var registry: DeviceRegistrySnapshot

  /// What the network learned about each device besides its identity, by device. A device can
  /// be here without an identity, such as an i2CS device that isn't linked to the modem. The
  /// initializer leaves out a device about which nothing is known.
  public var devices: [InsteonAddress: NetworkDeviceState]

  /// The records of the modem's own ALL-Link database as last read, in the modem's order, or
  /// `nil` if it hasn't been read.
  public var modemDatabase: [AllLinkRecord]?

  /// The Hub the modem was last reached through, or `nil` if it wasn't reached through a Hub.
  public var hub: HubLocation?

  /// Creates a snapshot.
  ///
  /// - Parameters:
  ///   - registry: The identities the devices reported. Defaults to none.
  ///   - devices: What the network learned about each device. Defaults to nothing.
  ///   - modemDatabase: The modem's records as last read. Defaults to `nil`.
  ///   - hub: The Hub the modem was reached through. Defaults to `nil`.
  public init(
    registry: DeviceRegistrySnapshot = DeviceRegistrySnapshot(),
    devices: [InsteonAddress: NetworkDeviceState] = [:],
    modemDatabase: [AllLinkRecord]? = nil,
    hub: HubLocation? = nil
  ) {

    self.registry = registry
    self.devices = devices.filter { (entry: (key: InsteonAddress, value: NetworkDeviceState)) -> Bool in !entry.value.isEmpty }
    self.modemDatabase = modemDatabase
    self.hub = hub

  }

  /// Whether the snapshot holds nothing.
  public var isEmpty: Bool {

    registry.isEmpty && devices.isEmpty && modemDatabase == nil && hub == nil

  }

}

/// What a ``DeviceNetwork`` learned about one device besides its identity.
///
/// ```swift
/// if let state = await network.state(of: lamp), let level = state.level {
///   print("\(LightLevel.percent(level: level))%")
/// }
/// ```
public struct NetworkDeviceState: Hashable, Sendable {

  /// The engine the device reported, or `nil` if it hasn't reported one this package knows.
  public var engine: InsteonEngine?

  /// A copy of the device's ALL-Link database and the delta it was read at, or `nil` if it
  /// hasn't been read.
  public var allLinkDatabase: AllLinkDatabaseCopy?

  /// The level the device last reported in its acknowledgment of a status request, from
  /// `0x00` for off to `0xFF` for fully on, or `nil` if it hasn't reported one. An on/off
  /// device reports `0x00` for off and any other level for on.
  public var level: UInt8?

  /// When the device last answered the modem, to the second, or `nil` if it hasn't.
  public var lastSeen: Date?

  /// Creates a device's state.
  ///
  /// - Parameters:
  ///   - engine: The engine the device reported. Defaults to `nil`.
  ///   - allLinkDatabase: A copy of the device's ALL-Link database. Defaults to `nil`.
  ///   - level: The level the device last reported. Defaults to `nil`.
  ///   - lastSeen: When the device last answered. Defaults to `nil`.
  public init(engine: InsteonEngine? = nil, allLinkDatabase: AllLinkDatabaseCopy? = nil, level: UInt8? = nil, lastSeen: Date? = nil) {

    self.engine = engine
    self.allLinkDatabase = allLinkDatabase
    self.level = level
    self.lastSeen = lastSeen

  }

  /// Whether nothing is known about the device.
  public var isEmpty: Bool {

    engine == nil && allLinkDatabase == nil && level == nil && lastSeen == nil

  }

}

/// Where a Hub is on the local network, and its Insteon ID when it's known.
///
/// It never holds the Hub's credentials or its MAC address.
///
/// ```swift
/// let hub = HubLocation(host: "192.0.2.10", port: 25105)
/// let network = DeviceNetwork(modem: modem, catalog: catalog, hub: hub)
/// ```
public struct HubLocation: Hashable, Sendable {

  /// The Hub's host name or IP address.
  public var host: String

  /// The Hub's TCP port.
  public var port: Int

  /// The Hub's Insteon ID, the address of its modem, or `nil` if it isn't known.
  public var insteonID: InsteonAddress?

  /// Creates a Hub's location.
  ///
  /// - Parameters:
  ///   - host: The Hub's host name or IP address.
  ///   - port: The Hub's TCP port.
  ///   - insteonID: The Hub's Insteon ID, if it's known. Defaults to `nil`.
  public init(host: String, port: Int, insteonID: InsteonAddress? = nil) {

    self.host = host
    self.port = port
    self.insteonID = insteonID

  }

  /// Whether two locations name the same host and port, whatever their Insteon IDs.
  ///
  /// - Parameter other: Another location.
  /// - Returns: `true` if the host and port are the same.
  public func isSameEndpoint(as other: HubLocation) -> Bool {

    host == other.host && port == other.port

  }

}
