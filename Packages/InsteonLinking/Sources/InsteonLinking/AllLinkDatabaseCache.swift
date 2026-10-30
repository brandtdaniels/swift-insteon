import InsteonModem
import InsteonProtocol

/// Keeps copies of the ALL-Link databases of the modem and its devices, so each is read over
/// the network only when it has changed.
///
/// The databases in the modem and the devices are the source of truth; a copy is only ever
/// what was last read from them. Reading a device's database takes a request for every
/// record, so the cache keeps what it read along with the device's ALL-Link database delta at
/// the time. The delta is a byte the device changes whenever its database does, and it
/// arrives in the acknowledgment of a status request. Before handing back a copy, the cache
/// asks for the delta again: one standard message instead of a read. A device whose delta has
/// changed is read again. ``Linker`` and ``Unlinker`` forget a device's copy whenever they
/// change its database, so it's read again rather than guessed.
///
/// The modem's own database has no delta every modem reports, so the cache reads it once
/// and keeps it until ``AllLinkDatabaseCache/invalidateModem()``, which ``Linker`` and
/// ``Unlinker`` call whenever they change the modem's records. Since something else, such as
/// the modem's SET button, can change it too, the linker always asks the modem itself before
/// changing it; the copy is for an app to read.
///
/// ```swift
/// let cache = AllLinkDatabaseCache(modem: modem)
/// let linker = Linker(modem: modem, cache: cache)
///
/// let records = try await cache.records(of: lamp)   // Reads the lamp's database.
/// try await linker.link(group)                      // Checks the delta instead of reading it.
/// ```
///
/// A delta is one byte, so a database that changed a multiple of 256 times between two
/// requests looks unchanged. Give a linker or unlinker a cache that reads through the same
/// modem, and use one linker or unlinker at a time with a cache, since two changing the same
/// device at once can each write into the same free record. The copies live in memory for as
/// long as the cache does.
public actor AllLinkDatabaseCache {

  /// A device's database as it was read, and its delta at the time.
  private struct DeviceDatabase {

    let delta: UInt8

    let records: [AllLinkRecordResponse]

  }

  /// The modem the databases are read through.
  public let modem: any LinkingModem

  /// How long to wait for each request to a device.
  public let timeout: Duration

  private var devices: [InsteonAddress: DeviceDatabase] = [:]

  private var modemDatabase: [AllLinkRecord]?

  /// Creates an empty cache.
  ///
  /// - Parameters:
  ///   - modem: The modem the databases are read through.
  ///   - timeout: How long to wait for each request to a device. Defaults to
  ///     `Modem.defaultExtendedRequestTimeout`, since a database is read with extended
  ///     messages.
  public init(modem: any LinkingModem, timeout: Duration = Modem.defaultExtendedRequestTimeout) {

    self.modem = modem
    self.timeout = timeout

  }

  /// A device's ALL-Link database, read again only if it has changed since the last read.
  ///
  /// The device is asked for its database delta first. If it matches the delta the copy was
  /// read at, the copy is returned; otherwise the database is read again. The delta is asked
  /// for before the read, so a change made while the database is being read shows up as a
  /// changed delta next time.
  ///
  /// - Parameter device: The device whose database to return.
  /// - Returns: The device's records in its order, ending with the record that marks the end
  ///   of the database, as `Modem.readAllLinkDatabase(of:timeout:)` returns them.
  /// - Throws: The modem's errors, such as `ModemError.deviceRejected` from an i2CS device
  ///   that isn't linked to the modem.
  public func records(of device: InsteonAddress) async throws -> [AllLinkRecordResponse] {

    let delta = try await databaseDelta(of: device)

    if let database = devices[device], database.delta == delta {

      return database.records

    }

    let records = try await modem.readAllLinkDatabase(of: device, timeout: timeout)
    devices[device] = DeviceDatabase(delta: delta, records: records)

    return records

  }

  /// The modem's own ALL-Link database, read the first time it's needed.
  ///
  /// - Returns: The modem's records, in its order.
  /// - Throws: The modem's errors.
  public func modemRecords() async throws -> [AllLinkRecord] {

    if let modemDatabase {

      return modemDatabase

    }

    let records = try await modem.allLinkRecords()
    modemDatabase = records

    return records

  }

  /// The modem's links with a device: the records in use in the modem's own ALL-Link
  /// database that name it, in the modem's order.
  ///
  /// A controller record is a link in which the modem controls the device, in one of the
  /// modem's groups; a responder record is one in which the modem responds to the device, in
  /// one of the device's groups. The modem's database is read the first time it's needed, as
  /// ``AllLinkDatabaseCache/modemRecords()`` reads it.
  ///
  /// ```swift
  /// let links = try await cache.modemLinks(of: lamp)
  /// let groups = links.filter { $0.flags.contains(.controller) }.map(\.group)
  /// ```
  ///
  /// - Parameter device: The device.
  /// - Returns: The modem's records in use for the device, or an empty array if it has none.
  /// - Throws: The modem's errors.
  public func modemLinks(of device: InsteonAddress) async throws -> [AllLinkRecord] {

    let records: [AllLinkRecord] = try await modemRecords()

    return records.filter { (record: AllLinkRecord) -> Bool in

      record.address == device && record.flags.contains(.inUse)

    }

  }

  /// Forgets a device's database, so it's read again the next time it's needed.
  ///
  /// - Parameter device: The device whose copy to forget.
  public func invalidate(_ device: InsteonAddress) {

    devices[device] = nil

  }

  /// Forgets the modem's database, so it's read again the next time it's needed.
  public func invalidateModem() {

    modemDatabase = nil

  }

  /// The device's ALL-Link database delta, which its acknowledgment of a status request
  /// carries in cmd1.
  private func databaseDelta(of device: InsteonAddress) async throws -> UInt8 {

    let acknowledgment = try await modem.request(
      StandardMessage(to: device, command: StandardDirectCommand.statusRequest()),
      timeout: timeout
    )

    return acknowledgment.command.command1

  }

}
