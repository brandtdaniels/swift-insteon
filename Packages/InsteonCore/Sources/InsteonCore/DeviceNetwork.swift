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
///   print(entry.record.address, entry.device?.info.displayName ?? "unknown")
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
/// Canceling any call that waits on an identification cancels the identification, so every
/// call waiting on it throws `CancellationError`. A call that arrives once an identification
/// is canceled starts a new one rather than wait on it, and one that arrives after an
/// identification ends, however it ended, asks the device again.
///
/// Times, such as when a device last answered, come from the `now` function the network is
/// created with, so a test can give fixed times.
public actor DeviceNetwork {

  /// The modem the devices are reached through. It's internal, so every message a front end
  /// sends a device goes through the guards of ``Device`` and ``send(_:collectingFor:onAcknowledgment:)``.
  nonisolated let modem: any LinkingModem

  /// The identities devices reported, described with the Insteon device catalog.
  public nonisolated let registry: DeviceRegistry

  /// The copies of devices' ALL-Link databases, the only cache that reads them through the
  /// modem. The network's ``linking`` coordinator gives it to the linkers and unlinkers that
  /// change databases, so it forgets the copies they change; it's internal, so it has no other
  /// writer.
  nonisolated let cache: AllLinkDatabaseCache

  private let identifier: DeviceIdentifier

  private let now: @Sendable () -> Date

  /// How long to wait for each request to a device that a standard message answers.
  nonisolated let requestTimeout: Duration

  /// The clock that times waits for what a device sends after a request.
  nonisolated let clock: any Clock<Duration>

  private var devices: [InsteonAddress: NetworkDeviceState]

  private var modemRecords: [AllLinkRecord]?

  private var hub: HubLocation?

  /// Whether the modem is the Hub's, because the network was created with a Hub, so the
  /// modem's address is the Hub's Insteon ID.
  private let isHubsModem: Bool

  /// Takes turns for the network's links and unlinks, so one runs at a time.
  nonisolated let linkingTurns: LinkingTurns

  /// An identification in progress, which every caller for its address waits on.
  private struct Identification {

    let id: Int

    let task: Task<DeviceIdentification, any Error>

    /// The calls that wait on it and haven't been canceled.
    let waiters: IdentificationWaiters

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
  ///     answers, such as the status request that asks for a device's ALL-Link database
  ///     delta. Defaults to `Modem.defaultRequestTimeout`. ALL-Link databases are read with
  ///     `Modem.defaultExtendedRequestTimeout`, since each record arrives in an extended
  ///     message.
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
    self.cache = AllLinkDatabaseCache(modem: modem, statusTimeout: timeout, copies: copies)
    self.identifier = DeviceIdentifier(modem: modem, timeout: timeout, clock: clock)
    self.now = now
    self.requestTimeout = timeout
    self.clock = clock
    self.devices = snapshot.devices
    self.modemRecords = snapshot.modemDatabase
    self.hub = location
    self.isHubsModem = hub != nil
    self.linkingTurns = LinkingTurns()

  }

  // MARK: - What the network knows

  /// What the network knows, as a value to save and give back to
  /// ``init(modem:catalog:snapshot:hub:timeout:clock:now:)`` later.
  ///
  /// Each device's ALL-Link database is the copy the cache holds, so a database a linker
  /// changed, and the cache forgot, isn't kept, nor is one with a record whose checksum
  /// failed, which the cache doesn't keep.
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
  ///   the network last read; ``allLinkDatabase(of:beforeReading:)`` checks it against the device.
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

      entries.append(ModemDatabaseEntry(record: LinkRecord(record), device: await registry.device(record.address)))

    }

    return entries

  }

  /// A device's ALL-Link database, from the copy the network holds while the device reports
  /// the delta it was read at, or else read again.
  ///
  /// The device is asked for its delta with a status request, whose acknowledgment also
  /// carries its level, so the device's level and when it last answered are updated too.
  ///
  /// ```swift
  /// let database = try await network.allLinkDatabase(of: lamp, beforeReading: { print("Reading...") })
  /// ```
  ///
  /// - Parameters:
  ///   - device: The device whose database to return.
  ///   - beforeReading: Called before the database is read, and not when the copy is handed
  ///     back, so an app can say that a read that takes a request for every record has
  ///     begun. Defaults to doing nothing.
  /// - Returns: The database and the delta it was read at. Its records are in the device's
  ///   order, ending with the record that marks the end of the database.
  /// - Throws: The modem's errors, such as `ModemError.deviceRejected` from an i2CS device
  ///   that isn't linked to the modem.
  public func allLinkDatabase(
    of device: InsteonAddress,
    beforeReading: @Sendable () -> Void = {}
  ) async throws -> LinkDatabase {

    let copy: AllLinkDatabaseCopy = try await databaseCopy(of: device, beforeReading: beforeReading)

    return LinkDatabase(copy)

  }

  /// A device's ALL-Link database as the cache holds it, the way
  /// ``allLinkDatabase(of:beforeReading:)`` returns it.
  func databaseCopy(
    of device: InsteonAddress,
    beforeReading: @Sendable () -> Void = {}
  ) async throws -> AllLinkDatabaseCopy {

    let reading: AllLinkDatabaseReading = try await cache.database(of: device, beforeReading: beforeReading)

    devices[device, default: NetworkDeviceState()].level = reading.status
    markSeen(device)

    return reading.copy

  }

  /// Asks a device for its engine and identity, and records what it reports.
  ///
  /// The identity goes in the ``registry``, and the engine and when the device answered in
  /// the device's state. While an identification of the same address is in progress, the call
  /// waits for its result instead of asking the device again. Canceling a call stops it
  /// waiting once the identification ends, and throws `CancellationError`; the identification
  /// itself is canceled only when every call waiting on it is, so canceling one call leaves
  /// the others their result. A call made after that starts a new identification instead of
  /// waiting on the canceled one.
  ///
  /// - Parameter device: The device to ask.
  /// - Returns: What the device said, as `DeviceIdentifier.identify(_:)` returns it.
  /// - Throws: `DeviceIdentifier`'s errors, or `CancellationError` if the call or the
  ///   identification was canceled.
  public func identify(_ device: InsteonAddress) async throws -> DeviceIdentification {

    let (task, waiters): (Task<DeviceIdentification, any Error>, IdentificationWaiters) = identification(of: device)

    let result: Result<DeviceIdentification, any Error> = await withTaskCancellationHandler {

      await task.result

    } onCancel: {

      // The last call to stop waiting cancels the identification, at once, so a call made
      // after it starts a new one.
      if waiters.leave() {

        task.cancel()

      }

    }

    try Task.checkCancellation()

    return try result.get()

  }

  /// The identification of a device in progress, or one started for it.
  ///
  /// An identification that's canceled but hasn't finished yet isn't joined: a new one
  /// replaces it, and the canceled one, when it finishes, leaves the new one in place.
  ///
  /// - Returns: The identification's task, and its waiters, with the caller counted among
  ///   them.
  private func identification(of device: InsteonAddress) -> (Task<DeviceIdentification, any Error>, IdentificationWaiters) {

    if let running = identifications[device], !running.task.isCancelled, running.waiters.join() {

      joinedIdentifications += 1

      return (running.task, running.waiters)

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

    let waiters = IdentificationWaiters()

    identifications[device] = Identification(id: id, task: task, waiters: waiters)

    return (task, waiters)

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

  // MARK: - Devices

  /// A device on the network, to control through the Insteon device catalog's description of
  /// it.
  ///
  /// Creating one sends nothing. The first operation that needs to know what the device is
  /// asks it with ID Request through ``identify(_:)`` when the ``registry`` doesn't know it.
  ///
  /// ```swift
  /// let lamp = network.device(InsteonAddress(0x1A, 0x2B, 0x3C))
  /// let result = try await lamp.turnOn(level: 50)
  /// ```
  ///
  /// - Parameters:
  ///   - address: The device's address.
  ///   - beforeIdentifying: Called before the device is asked for its identity, so an app can
  ///     say why it's waiting. Defaults to doing nothing.
  /// - Returns: The device.
  public nonisolated func device(_ address: InsteonAddress, beforeIdentifying: @escaping @Sendable () -> Void = {}) -> Device {

    Device(address: address, network: self, beforeIdentifying: beforeIdentifying)

  }

  /// Sends a device a message as it's given, for exploring what the Insteon device catalog
  /// doesn't describe yet, then collects the other messages the device sends for a time.
  ///
  /// The message passes the same guards as every message a ``Device`` sends, checked by its
  /// bytes before anything is sent. Poke is never sent, and a ``ProtectedCommand``'s Set
  /// Operating Flags bytes are sent only to a device the ``registry`` knows whose command set
  /// names the cmd2 for a flag or command it doesn't guard. Nor are the bytes the device's
  /// command set never sends, or an extended message that writes a byte holding a flag the
  /// catalog guards, which only ``Device/writeSetting(_:to:button:)`` writes. An extended Set
  /// to a device with no command set isn't sent either, since which bits it writes can't be
  /// told. The device isn't asked for its identity first.
  ///
  /// Listening starts before the message, so nothing the device sends is missed. The
  /// device's acknowledgment is handed to `onAcknowledgment` as soon as it arrives, and isn't
  /// among the messages returned. The time is timed by the network's clock.
  ///
  /// ```swift
  /// let message = DirectMessage(to: lamp, command1: 0x19, command2: 0x00, data: nil, hasChecksum: false)
  /// let frames = try await network.send(message, collectingFor: .seconds(3)) { acknowledgment in
  ///   print(acknowledgment.summary)
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - message: The message.
  ///   - duration: How long to collect what the device sends after its acknowledgment.
  ///   - onAcknowledgment: Called with the device's acknowledgment.
  /// - Returns: The other messages from the device, in order.
  /// - Throws: ``SendRefusal`` before anything is sent; the modem's error, which
  ///   ``SendFailure`` reads as the device rejecting the message or not answering; or
  ///   `CancellationError`.
  public nonisolated func send(
    _ message: DirectMessage,
    collectingFor duration: Duration,
    onAcknowledgment: (ReceivedFrame) -> Void
  ) async throws -> [ReceivedFrame] {

    try await device(message.device).sendAsGiven(message, collectingFor: duration, onAcknowledgment: onAcknowledgment)

  }

  /// Records that a device answered, and the level it's at when it's known.
  ///
  /// - Parameters:
  ///   - device: The device.
  ///   - level: The level its status request would report, from `0x00` for off to `0xFF` for
  ///     fully on, or `nil` to leave the level as it is.
  func recordAnswer(of device: InsteonAddress, level: UInt8?) {

    if let level {

      devices[device, default: NetworkDeviceState()].level = level

    }

    markSeen(device)

  }

  // MARK: - Linking

  /// The coordinator that links devices to the modem and unlinks them, and keeps the
  /// ``registry``, the cache of ALL-Link databases and the network's ``snapshot()`` up to date as it does.
  ///
  /// Every coordinator a network hands out takes turns with the others, so one link or unlink
  /// runs at a time and the modem is in one linking mode at a time.
  ///
  /// ```swift
  /// let result = try await network.linking.link(lamp, as: .controller, group: 0, observer: prompter)
  /// ```
  public nonisolated var linking: DeviceLinkingCoordinator {

    DeviceLinkingCoordinator(network: self)

  }

  /// Records that a link with a device was made or removed: the copies of the device's and the
  /// modem's ALL-Link databases are forgotten, since both changed, and so are the modem's
  /// records the snapshot holds, until they're read again.
  ///
  /// - Parameters:
  ///   - device: The device.
  ///   - answered: Whether the device took part, so it answered at the current time.
  func recordLinkChange(of device: InsteonAddress, answered: Bool) async {

    await cache.invalidate(device)
    await cache.invalidateModem()
    modemRecords = nil

    if answered {

      markSeen(device)

    }

  }

  /// The modem's records in use for a device, read through the cache of ALL-Link databases, which reads the
  /// modem's ALL-Link database when it has no copy. The records read are kept for the
  /// snapshot.
  ///
  /// - Parameter device: The device.
  /// - Returns: The modem's records in use that name the device, in the modem's order.
  /// - Throws: The modem's errors.
  func modemLinks(of device: InsteonAddress) async throws -> [AllLinkRecord] {

    let records: [AllLinkRecord] = try await cache.modemRecords()

    modemRecords = records

    return records.filter { (record: AllLinkRecord) -> Bool in

      record.address == device && record.flags.contains(.inUse)

    }

  }

  /// Forgets a device removed from the network: its identity in the ``registry``, its state,
  /// the cached copy of its ALL-Link database, and the records that name it in the copy of
  /// the modem's ALL-Link database the snapshot holds.
  ///
  /// - Parameter device: The device.
  /// - Returns: The device as the registry knew it, or `nil` if it didn't.
  func forget(_ device: InsteonAddress) async -> RegisteredDevice? {

    let known: RegisteredDevice? = await registry.forget(device)

    devices[device] = nil
    await cache.invalidate(device)

    if let records = modemRecords {

      modemRecords = records.filter { (record: AllLinkRecord) -> Bool in record.address != device }

    }

    return known

  }

  /// Every device the network knows something about: those the ``registry`` knows, those with
  /// a state, and those whose ALL-Link database the network holds a cached copy of, in address
  /// order.
  func knownDevices() async -> [InsteonAddress] {

    let registered: [RegisteredDevice] = await registry.devices
    let copies: [InsteonAddress: AllLinkDatabaseCopy] = await cache.copies
    var addresses: Set<InsteonAddress> = Set(devices.keys)

    addresses.formUnion(registered.map(\.address))
    addresses.formUnion(copies.keys)

    return addresses.sorted { (first: InsteonAddress, second: InsteonAddress) -> Bool in

      first.bytes.lexicographicallyPrecedes(second.bytes)

    }

  }

  // MARK: - Changes

  /// The monitor that reads what the modem hears as events, and records in the ``registry``
  /// the identities devices report. It doesn't record when a device was heard.
  ///
  /// ```swift
  /// for await event in await network.monitor.changes() {
  ///   print(event)
  /// }
  /// ```
  public nonisolated var monitor: DeviceMonitor {

    DeviceMonitor(network: self)

  }

  /// Records the identity a device reported, such as in a broadcast the monitor heard, in the
  /// ``registry``. When the device was heard isn't recorded: a device's last-seen time is the
  /// time it last answered a command.
  ///
  /// - Parameters:
  ///   - identity: The identity the device reported.
  ///   - device: The device.
  func recordReportedIdentity(_ identity: ReportedIdentity, of device: InsteonAddress) async {

    await registry.record(identity, for: device)

  }

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
///   let role = entry.record.isController ? "controller" : "responder"
///   print(role, entry.record.group, entry.device?.info.displayName ?? "")
/// }
/// ```
public struct ModemDatabaseEntry: Hashable, Sendable {

  /// The record.
  public var record: LinkRecord

  /// The device the record names, with its identity and description, or `nil` if the
  /// registry doesn't know it.
  public var device: RegisteredDevice?

  /// Creates an entry.
  ///
  /// - Parameters:
  ///   - record: The record.
  ///   - device: The device the record names, if the registry knows it.
  public init(record: LinkRecord, device: RegisteredDevice?) {

    self.record = record
    self.device = device

  }

}

/// How many calls wait on an identification and haven't been canceled, counted from any task,
/// since a cancellation handler can't reach the network's actor.
final class IdentificationWaiters: @unchecked Sendable {

  // `lock` guards `count`.
  private let lock = NSLock()

  /// Starts at 1, the call that started the identification.
  private var count = 1

  /// Counts another call as waiting.
  ///
  /// - Returns: `false` if every call has stopped waiting, so the identification is being
  ///   canceled and mustn't be joined.
  func join() -> Bool {

    lock.withLock {

      guard count > 0 else {

        return false

      }

      count += 1

      return true

    }

  }

  /// Stops counting a canceled call as waiting.
  ///
  /// - Returns: `true` if it was the last call waiting, so the identification is to be canceled.
  func leave() -> Bool {

    lock.withLock {

      count -= 1

      return count == 0

    }

  }

}
