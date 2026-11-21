import Foundation
import InsteonDeviceCatalog
import InsteonHubPro
import InsteonLinking
import InsteonModem
import InsteonProtocol

/// What a backup reader is doing, so a front end can show progress.
public enum BackupProgress: Hashable, Sendable {
  /// The reader is asking the modem about itself and reading its ALL-Link database.
  case readingModem
  /// The reader is reading a device, the `position` of `total`, counting from 1.
  case readingDevice(InsteonAddress, position: Int, total: Int)
  /// A device has no ALL-Link database in the backup, for the reason given.
  case deviceUnreadable(InsteonAddress, BackupUnreadable)
}

/// Reads a modem's network, or a Hub Pro's device list, into a ``HomeBackup``.
///
/// Every request a reader sends is a read: the modem's information and ALL-Link database, each
/// device's ID Request and Light Status Request, and the ALL-Link database it reports. It never
/// writes to a modem or a device.
///
/// A device that doesn't answer is in the backup with the reason, so a person is told which
/// devices the backup doesn't cover. Canceling the task stops the reading and throws
/// `CancellationError`, and nothing is returned.
///
/// ```swift
/// let backup = try await HomeBackupReader.read(network: network, createdAt: Date()) { progress in
///   print(progress)
/// }
/// ```
public enum HomeBackupReader {

  /// Reads the modem's database and the database of each device it knows.
  ///
  /// The devices are the ones the registry knows and the ones the modem's records name, except
  /// the modem itself. A device that isn't in the registry is asked for its identity first.
  ///
  /// - Parameters:
  ///   - network: The network to read.
  ///   - createdAt: When the backup is taken.
  ///   - progress: Called before each step. Defaults to doing nothing.
  /// - Returns: The backup.
  /// - Throws: The modem's errors when the modem can't be read, `ModemError.connectionClosed`
  ///   when it goes away while devices are read, and `CancellationError`.
  public static func read(
    network: DeviceNetwork,
    createdAt: Date,
    progress: @Sendable (BackupProgress) -> Void = { _ in }
  ) async throws -> HomeBackup {

    progress(.readingModem)

    let info: ModemInfo = try await network.modemInfo()
    let entries: [ModemDatabaseEntry] = try await network.modemDatabase()
    let modem: BackupModem = BackupModem(address: info.address, identity: BackupIdentity(ReportedIdentity(category: info.category, subcategory: info.subcategory, firmwareVersion: info.firmwareVersion)), allLinkDatabase: entries.map { BackupRecord($0.record) })

    var addresses: Set<InsteonAddress> = Set(entries.filter(\.record.isInUse).map(\.record.address))

    for device in await network.registry.devices {

      addresses.insert(device.address)

    }

    addresses.remove(info.address)

    let ordered: [InsteonAddress] = addresses.sorted { (first: InsteonAddress, second: InsteonAddress) -> Bool in first.bytes.lexicographicallyPrecedes(second.bytes) }
    var devices: [BackupDevice] = []

    for (index, address) in ordered.enumerated() {

      try Task.checkCancellation()

      progress(.readingDevice(address, position: index + 1, total: ordered.count))

      let device: BackupDevice = try await read(address, network: network)

      if let unreadable = device.unreadable {

        progress(.deviceUnreadable(address, unreadable))

      }

      devices.append(device)

    }

    return HomeBackup(createdAt: createdAt, source: .modem, modem: modem, devices: devices)

  }

  /// Reads a Hub Pro's device list: each device's address, name, type and identity, and the
  /// Hub Pro's modem address. A Hub Pro doesn't give out ALL-Link databases, so each device is
  /// marked with that reason.
  ///
  /// - Parameters:
  ///   - network: The Hub Pro's network.
  ///   - createdAt: When the backup is taken.
  /// - Returns: The backup.
  /// - Throws: What reading the Hub Pro's list throws, and `CancellationError`.
  public static func read(hubPro network: HubProNetwork, createdAt: Date) async throws -> HomeBackup {

    try await network.open()
    try Task.checkCancellation()

    let listing: [HubProListedDevice] = await network.listing()
    var devices: [BackupDevice] = []

    for listed in listing where !listed.isModem {

      let registered: RegisteredDevice? = await network.registry.device(listed.address)

      devices.append(BackupDevice(
        address: listed.address,
        name: listed.name,
        type: listed.deviceType,
        identity: registered.map { BackupIdentity($0.identity) },
        unreadable: BackupUnreadable(reason: .unavailableFromSource)
      ))

    }

    let modem: BackupModem? = listing.first(where: \.isModem).map { (listed: HubProListedDevice) -> BackupModem in

      BackupModem(address: listed.address, unreadable: BackupUnreadable(reason: .unavailableFromSource))

    }

    return HomeBackup(createdAt: createdAt, source: .hubPro, modem: modem, devices: devices)

  }

  /// Builds a backup from what a network last learned, without sending anything.
  ///
  /// A device whose ALL-Link database the snapshot doesn't hold is in the backup as not cached.
  ///
  /// - Parameters:
  ///   - snapshot: What the network knows.
  ///   - modem: The modem's address and the identity it reported, or `nil` if the address isn't
  ///     known.
  ///   - catalog: The catalog that names the devices' products, or `nil`.
  ///   - createdAt: When the backup is taken.
  /// - Returns: The backup, from a service as its source.
  public static func backup(from snapshot: NetworkSnapshot, modem: (address: InsteonAddress, identity: ReportedIdentity?)?, catalog: DeviceCatalog?, createdAt: Date) async -> HomeBackup {

    let registry: DeviceRegistry = DeviceRegistry(catalog: catalog, snapshot: snapshot.registry)
    let records: [BackupRecord]? = snapshot.modemDatabase.map { (records: [AllLinkRecord]) -> [BackupRecord] in records.map { BackupRecord(LinkRecord($0)) } }

    var addresses: Set<InsteonAddress> = Set(snapshot.registry.identities.keys).union(snapshot.devices.keys)

    for record in snapshot.modemDatabase ?? [] where record.flags.contains(.inUse) {

      addresses.insert(record.address)

    }

    if let modem {

      addresses.remove(modem.address)

    }

    var devices: [BackupDevice] = []

    for address in addresses {

      let state: NetworkDeviceState? = snapshot.devices[address]
      let identity: ReportedIdentity? = snapshot.registry.identities[address]
      let description: RegisteredDevice? = await registry.device(address)
      let engine: BackupEngine? = (state?.engine ?? description?.info.engine).map(BackupEngine.init)

      if let copy = state?.allLinkDatabase, copy.hasIntactChecksums {

        devices.append(BackupDevice(address: address, type: description?.info.displayName, identity: identity.map(BackupIdentity.init), engine: engine, allLinkDatabase: BackupDatabase(copy)))

      } else {

        devices.append(BackupDevice(address: address, type: description?.info.displayName, identity: identity.map(BackupIdentity.init), engine: engine, unreadable: BackupUnreadable(reason: .notCached)))

      }

    }

    let backupModem: BackupModem? = modem.map { (info: (address: InsteonAddress, identity: ReportedIdentity?)) -> BackupModem in

      let identity: BackupIdentity? = info.identity.map(BackupIdentity.init)

      if let records {

        return BackupModem(address: info.address, identity: identity, allLinkDatabase: records)

      }

      return BackupModem(address: info.address, identity: identity, unreadable: BackupUnreadable(reason: .notCached))

    }

    return HomeBackup(createdAt: createdAt, source: .service, modem: backupModem, devices: devices)

  }

  // MARK: - One device

  private static func read(_ address: InsteonAddress, network: DeviceNetwork) async throws -> BackupDevice {

    var registered: RegisteredDevice? = await network.registry.device(address)

    if registered == nil {

      do {

        _ = try await network.identify(address)
        registered = await network.registry.device(address)

      } catch {

        if let unreadable = try unreadable(for: error) {

          return BackupDevice(address: address, unreadable: unreadable)

        }

      }

    }

    let engine: BackupEngine? = await ((network.state(of: address)?.engine) ?? registered?.info.engine).map(BackupEngine.init)
    let identity: BackupIdentity? = registered.map { BackupIdentity($0.identity) }
    let type: String? = registered?.info.displayName

    do {

      var database: LinkDatabase = try await network.allLinkDatabase(of: address)

      if !database.hasIntactChecksums {

        // A damaged reading isn't kept, so asking again reads the device again.
        database = try await network.allLinkDatabase(of: address)

      }

      let damaged: Int = database.records.filter { (record: LinkRecord) -> Bool in !record.hasIntactChecksum }.count

      if damaged > 0 {

        return BackupDevice(address: address, type: type, identity: identity, engine: engine, unreadable: BackupUnreadable(reason: .damagedRecords, detail: "\(damaged) of \(database.records.count) records failed their checksum"))

      }

      return BackupDevice(address: address, type: type, identity: identity, engine: engine, allLinkDatabase: BackupDatabase(database))

    } catch {

      guard let unreadable = try unreadable(for: error) else {

        throw error

      }

      return BackupDevice(address: address, type: type, identity: identity, engine: engine, unreadable: unreadable)

    }

  }

  /// The reason a device has no database, or `nil` for an error that ends the backup.
  ///
  /// - Throws: `CancellationError`, which ends the backup.
  private static func unreadable(for error: any Error) throws -> BackupUnreadable? {

    if error is CancellationError {

      throw error

    }

    switch error {
    case ModemError.deviceTimedOut, ModemError.timedOut:
      return BackupUnreadable(reason: .noAnswer)
    case ModemError.deviceRejected:
      return BackupUnreadable(reason: .rejectedModem)
    case ModemError.connectionClosed:
      return nil
    default:
      return BackupUnreadable(reason: .failed)
    }

  }

}

extension BackupDatabase {

  /// The database as a backup keeps it.
  ///
  /// - Parameter database: A device's database.
  init(_ database: LinkDatabase) {

    self.init(delta: database.delta, records: database.records.map { BackupRecord($0) })

  }

  /// The database as a copy the network held keeps it.
  ///
  /// - Parameter copy: A copy of a device's database.
  init(_ copy: AllLinkDatabaseCopy) {

    self.init(LinkDatabase(copy))

  }

}
