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
/// let restored = session.network(catalog: catalog, snapshot: try store.loadNetwork(), hub: session.hub)
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

extension NetworkSnapshot {

  /// This snapshot with the changes from one snapshot to another applied to it, and
  /// everything else left as this snapshot has it.
  ///
  /// It's how a process that started a ``DeviceNetwork`` from a store's snapshot saves what the
  /// network learned without undoing what another process saved in the meantime: read the
  /// store again, and save its snapshot merged with the changes from the snapshot the network
  /// started from to the network's latest snapshot.
  ///
  /// ```swift
  /// let start = try store.loadNetwork()
  /// let network = session.network(catalog: catalog, snapshot: start, hub: session.hub)
  ///
  /// _ = try await network.allLinkDatabase(of: lamp)
  ///
  /// let learned = await network.snapshot()
  /// try store.saveNetwork(try store.loadNetwork().merging(changesFrom: start, to: learned))
  /// ```
  ///
  /// Each value is compared between `start` and `end` on its own. A value that differs is
  /// taken from `end`, and one that `end` doesn't have is removed; a value that's the same in
  /// both is left as this snapshot has it, even when this snapshot's differs from both. The
  /// values are:
  ///
  /// - Each device's identity in ``registry``.
  /// - Each field of each device's state in ``devices``: its engine, the copy of its ALL-Link
  ///   database, its level and when it last answered. A device left with no field is removed.
  /// - The modem's ALL-Link database, ``modemDatabase``, as a whole.
  /// - The Hub, ``hub``, as a whole: its host, port and Insteon ID together.
  ///
  /// So a device that only another process learned about keeps what that process saved, and a
  /// field that both changed takes the value in `end`.
  ///
  /// - Parameters:
  ///   - start: The snapshot the changes are from, such as the one a network started from.
  ///   - end: The snapshot the changes are to, such as the network's latest snapshot.
  /// - Returns: This snapshot with the changes applied.
  public func merging(changesFrom start: NetworkSnapshot, to end: NetworkSnapshot) -> NetworkSnapshot {

    var merged: NetworkSnapshot = self

    let identified: Set<InsteonAddress> = Set(start.registry.identities.keys).union(end.registry.identities.keys)

    for address in identified {

      let before: ReportedIdentity? = start.registry.identities[address]
      let after: ReportedIdentity? = end.registry.identities[address]

      if before != after {

        merged.registry.identities[address] = after

      }

    }

    let known: Set<InsteonAddress> = Set(start.devices.keys).union(end.devices.keys)

    for address in known {

      let before: NetworkDeviceState = start.devices[address] ?? NetworkDeviceState()
      let after: NetworkDeviceState = end.devices[address] ?? NetworkDeviceState()

      guard before != after else {

        continue

      }

      let current: NetworkDeviceState = merged.devices[address] ?? NetworkDeviceState()
      let state: NetworkDeviceState = current.merging(changesFrom: before, to: after)

      merged.devices[address] = state.isEmpty ? nil : state

    }

    if start.modemDatabase != end.modemDatabase {

      merged.modemDatabase = end.modemDatabase

    }

    if start.hub != end.hub {

      merged.hub = end.hub

    }

    return merged

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

  /// This state with each field that differs between `start` and `end` taken from `end`, as
  /// ``NetworkSnapshot/merging(changesFrom:to:)`` merges a device's state.
  func merging(changesFrom start: NetworkDeviceState, to end: NetworkDeviceState) -> NetworkDeviceState {

    var merged: NetworkDeviceState = self

    if start.engine != end.engine {

      merged.engine = end.engine

    }

    if start.allLinkDatabase != end.allLinkDatabase {

      merged.allLinkDatabase = end.allLinkDatabase

    }

    if start.level != end.level {

      merged.level = end.level

    }

    if start.lastSeen != end.lastSeen {

      merged.lastSeen = end.lastSeen

    }

    return merged

  }

}

/// Where a Hub is on the local network, and its Insteon ID when it's known.
///
/// It never holds the Hub's credentials or its MAC address.
///
/// ```swift
/// let hub = HubLocation(host: "192.0.2.10", port: 25105)
/// let network = session.network(catalog: catalog, snapshot: NetworkSnapshot(), hub: hub)
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
