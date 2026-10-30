import Foundation
import InsteonDeviceCatalog
import InsteonLinking
import InsteonModem
import InsteonProtocol

/// The Insteon devices reached through one modem: what they are, their ALL-Link databases,
/// and what they last reported.
///
/// A network owns the modem it talks through, a ``DeviceRegistry`` of the identities devices
/// reported, and one `AllLinkDatabaseCache`, the only one that reads databases through the
/// modem, so copies stay consistent. It starts from a ``NetworkSnapshot``, such as one a
/// ``NetworkSnapshotStore`` loaded, and ``snapshot()`` gives back what it knows to save for
/// the next launch:
///
/// ```swift
/// let store = JSONFileDeviceRegistryStore(fileURL: url)
/// let network = DeviceNetwork(modem: modem, catalog: try? DeviceCatalog.bundled(), snapshot: try store.loadNetwork())
///
/// for entry in try await network.modemDatabase() {
///   print(entry.record.address, entry.device?.deviceDescription.displayName ?? "unknown")
/// }
///
/// let database = try await network.allLinkDatabase(of: lamp)   // Read only if it changed.
/// try store.saveNetwork(await network.snapshot())
/// ```
///
/// A device's ALL-Link database is handed back from the copy the network holds while the
/// device reports the delta the copy was read at, and read again when the delta differs or no
/// copy is held; the delta is compared for equality only. The modem's own database reports no
/// delta, so ``modemDatabase()`` always reads it.
///
/// Identifying a device is shared: while one identification of an address is in progress,
/// another call for the same address waits for its result instead of asking the device again.
///
/// Times, such as when a device last answered, come from the `now` function the network is
/// created with, so a test can give fixed times.
public actor DeviceNetwork {

  /// The modem the devices are reached through.
  public nonisolated let modem: any LinkingModem

  /// The identities devices reported, described with the Insteon device catalog.
  public nonisolated let registry: DeviceRegistry

  /// The copies of devices' ALL-Link databases, the only cache that reads them through the
  /// modem. Give it to a linker or unlinker that changes databases, so it forgets the copies
  /// they change.
  public nonisolated let cache: AllLinkDatabaseCache

  private let identifier: DeviceIdentifier

  private let now: @Sendable () -> Date

  private var devices: [InsteonAddress: NetworkDeviceState]

  private var modemRecords: [AllLinkRecord]?

  private var hub: HubLocation?

  /// Whether the modem is the Hub's, because the network was created with a Hub, so the
  /// modem's address is the Hub's Insteon ID.
  private let isHubsModem: Bool

  /// An identification in progress, which every caller for its address waits on.
  private struct Identification {

    let id: Int

    let task: Task<DeviceIdentification, any Error>

  }

  private var identifications: [InsteonAddress: Identification] = [:]

  private var nextIdentificationID: Int = 0

  /// How many calls have waited on an identification another call started. Tests read it to
  /// know a call has joined one in progress.
  private(set) var joinedIdentifications: Int = 0

  /// Creates a network.
  ///
  /// - Parameters:
  ///   - modem: The modem the devices are reached through.
  ///   - catalog: The catalog to describe devices with, or `nil` to describe them by their
  ///     identities alone.
  ///   - snapshot: What the network knew before, such as a snapshot a ``NetworkSnapshotStore``
  ///     loaded. Defaults to nothing.
  ///   - hub: The Hub the modem is reached through, or `nil` for a modem that isn't a Hub's,
  ///     which keeps the Hub the snapshot names as it is. A Hub at the snapshot's host and
  ///     port keeps its Insteon ID. Only a network created with a Hub learns the Hub's
  ///     Insteon ID from ``modemInfo()``. Defaults to `nil`.
  ///   - timeout: How long to wait for each request to a device that a standard message
  ///     answers. Defaults to `Modem.defaultRequestTimeout`. ALL-Link databases are read with
  ///     `Modem.defaultExtendedRequestTimeout`.
  ///   - clock: The clock that times waits for a device's broadcast. Defaults to a
  ///     `ContinuousClock`; tests can pass a clock they control.
  ///   - now: The current time, for when a device last answered. Defaults to the system's
  ///     time; tests can pass fixed times.
  public init(
    modem: any LinkingModem,
    catalog: DeviceCatalog?,
    snapshot: NetworkSnapshot = NetworkSnapshot(),
    hub: HubLocation? = nil,
    timeout: Duration = Modem.defaultRequestTimeout,
    clock: any Clock<Duration> = ContinuousClock(),
    now: @escaping @Sendable () -> Date = { Date() }
  ) {

    var copies: [InsteonAddress: AllLinkDatabaseCopy] = [:]

    for (address, state) in snapshot.devices {

      copies[address] = state.allLinkDatabase

    }

    var location: HubLocation? = snapshot.hub

    if let hub {

      if let known = snapshot.hub, known.isSameEndpoint(as: hub), hub.insteonID == nil {

        location = HubLocation(host: hub.host, port: hub.port, insteonID: known.insteonID)

      } else {

        location = hub

      }

    }

    self.modem = modem
    self.registry = DeviceRegistry(catalog: catalog, snapshot: snapshot.registry)
    self.cache = AllLinkDatabaseCache(modem: modem, copies: copies)
    self.identifier = DeviceIdentifier(modem: modem, timeout: timeout, clock: clock)
    self.now = now
    self.devices = snapshot.devices
    self.modemRecords = snapshot.modemDatabase
    self.hub = location
    self.isHubsModem = hub != nil

  }

  // MARK: - What the network knows

  /// What the network knows, as a value to save and give back to
  /// ``init(modem:catalog:snapshot:hub:timeout:clock:now:)`` later.
  ///
  /// Each device's ALL-Link database is the copy the cache holds, so a database a linker
  /// changed, and the cache forgot, isn't kept.
  ///
  /// - Returns: The snapshot.
  public func snapshot() async -> NetworkSnapshot {

    let registered: DeviceRegistrySnapshot = await registry.snapshot
    let copies: [InsteonAddress: AllLinkDatabaseCopy] = await cache.copies

    var states: [InsteonAddress: NetworkDeviceState] = devices

    for address in Set(states.keys).union(copies.keys) {

      states[address, default: NetworkDeviceState()].allLinkDatabase = copies[address]

    }

    return NetworkSnapshot(registry: registered, devices: states, modemDatabase: modemRecords, hub: hub)

  }

  /// What the network learned about a device besides its identity.
  ///
  /// - Parameter device: The device's address.
  /// - Returns: Its engine, last known level and when it last answered, or `nil` if nothing
  ///   is known. The copy of its ALL-Link database is the one the snapshot was created with or
  ///   the network last read; ``allLinkDatabase(of:)`` checks it against the device.
  public func state(of device: InsteonAddress) async -> NetworkDeviceState? {

    var state: NetworkDeviceState = devices[device] ?? NetworkDeviceState()
    state.allLinkDatabase = await cache.copies[device]

    return state.isEmpty ? nil : state

  }

  /// The Hub the modem is reached through, or was last, if any.
  public var hubLocation: HubLocation? {

    hub

  }

  // MARK: - Reports

  /// The records of the modem's own ALL-Link database, each with the device it names when
  /// the registry knows the device.
  ///
  /// The modem's database reports no delta, so it's read every time.
  ///
  /// - Returns: The modem's records in its order, as `LinkingModem.allLinkRecords()` returns
  ///   them.
  /// - Throws: The modem's errors.
  public func modemDatabase() async throws -> [ModemDatabaseEntry] {

    // The cache's copy is forgotten first, so the modem itself is asked.
    await cache.invalidateModem()

    let records: [AllLinkRecord] = try await cache.modemRecords()

    modemRecords = records

    var entries: [ModemDatabaseEntry] = []

    for record in records {

      entries.append(ModemDatabaseEntry(record: record, device: await registry.device(record.address)))

    }

    return entries

  }

  /// A device's ALL-Link database, from the copy the network holds while the device reports
  /// the delta it was read at, or else read again.
  ///
  /// The device is asked for its delta with a status request, whose acknowledgment also
  /// carries its level, so the device's level and when it last answered are updated too.
  ///
  /// - Parameter device: The device whose database to return.
  /// - Returns: The database and the delta it was read at. Its records are in the device's
  ///   order, ending with the record that marks the end of the database.
  /// - Throws: The modem's errors, such as `ModemError.deviceRejected` from an i2CS device
  ///   that isn't linked to the modem.
  public func allLinkDatabase(of device: InsteonAddress) async throws -> AllLinkDatabaseCopy {

    let reading: AllLinkDatabaseReading = try await cache.database(of: device)

    devices[device, default: NetworkDeviceState()].level = reading.status
    markSeen(device)

    return reading.copy

  }

  /// Asks a device for its engine and identity, and records what it reports.
  ///
  /// The identity goes in the ``registry``, and the engine and when the device answered in
  /// the device's state. While an identification of the same address is in progress, the call
  /// waits for its result instead of asking the device again. Canceling a call cancels the
  /// identification it waits on, so every call waiting on it throws `CancellationError`.
  ///
  /// - Parameter device: The device to ask.
  /// - Returns: What the device said, as `DeviceIdentifier.identify(_:)` returns it.
  /// - Throws: `DeviceIdentifier`'s errors, or `CancellationError` if the identification was
  ///   canceled.
  public func identify(_ device: InsteonAddress) async throws -> DeviceIdentification {

    let task: Task<DeviceIdentification, any Error> = identification(of: device)

    return try await withTaskCancellationHandler {

      try await task.value

    } onCancel: {

      task.cancel()

    }

  }

  /// The identification of a device in progress, or one started for it.
  private func identification(of device: InsteonAddress) -> Task<DeviceIdentification, any Error> {

    if let running = identifications[device] {

      joinedIdentifications += 1

      return running.task

    }

    let id: Int = nextIdentificationID
    let identifier: DeviceIdentifier = self.identifier

    nextIdentificationID += 1

    // The device is asked outside the actor, so other calls aren't held up, and the result is
    // recorded before any caller sees it.
    let task = Task<DeviceIdentification, any Error> {

      do {

        let identification: DeviceIdentification = try await identifier.identify(device)

        await self.finishIdentification(id, of: device, with: identification)

        return identification

      } catch {

        await self.finishIdentification(id, of: device, with: nil)

        throw error

      }

    }

    identifications[device] = Identification(id: id, task: task)

    return task

  }

  /// Records what an identification found, all at once, and forgets it as in progress.
  private func finishIdentification(_ id: Int, of device: InsteonAddress, with identification: DeviceIdentification?) async {

    if identifications[device]?.id == id {

      identifications[device] = nil

    }

    guard let identification else {

      return

    }

    if let engine = identification.engine {

      devices[device, default: NetworkDeviceState()].engine = engine

    }

    markSeen(device)

    if let pressed = identification.identity {

      await registry.record(ReportedIdentity(pressed), for: device)

    }

  }

  /// Asks the modem about itself, and records its address as the Hub's Insteon ID when the
  /// network was created with a Hub, so the modem is the Hub's.
  ///
  /// A network created without a Hub leaves the Hub the snapshot names as it is, since its
  /// modem isn't that Hub's.
  ///
  /// - Returns: The modem's address, category, subcategory and firmware version.
  /// - Throws: The modem's errors.
  public func modemInfo() async throws -> ModemInfo {

    let info: ModemInfo = try await modem.modemInfo()

    if isHubsModem {

      hub?.insteonID = info.address

    }

    return info

  }

  // MARK: - Changes

  // A stream of changes, fed by the modem's replies, belongs here: devices' levels as they
  // report them, links as they're made, and identities as devices report them.

  // MARK: - Helpers

  /// Records that a device answered at the current time, to the second.
  private func markSeen(_ device: InsteonAddress) {

    let seconds: TimeInterval = now().timeIntervalSince1970.rounded(.down)

    devices[device, default: NetworkDeviceState()].lastSeen = Date(timeIntervalSince1970: seconds)

  }

}

/// A record of the modem's own ALL-Link database, with the device it names when the
/// ``DeviceRegistry`` knows the device.
///
/// ```swift
/// for entry in try await network.modemDatabase() {
///   let role = entry.record.flags.contains(.controller) ? "controller" : "responder"
///   print(role, entry.record.group, entry.device?.deviceDescription.displayName ?? "")
/// }
/// ```
public struct ModemDatabaseEntry: Hashable, Sendable {

  /// The record.
  public var record: AllLinkRecord

  /// The device the record names, with its identity and description, or `nil` if the
  /// registry doesn't know it.
  public var device: RegisteredDevice?

  /// Creates an entry.
  ///
  /// - Parameters:
  ///   - record: The record.
  ///   - device: The device the record names, if the registry knows it.
  public init(record: AllLinkRecord, device: RegisteredDevice?) {

    self.record = record
    self.device = device

  }

}
