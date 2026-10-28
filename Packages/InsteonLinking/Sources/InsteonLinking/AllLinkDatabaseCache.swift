import InsteonModem
import InsteonProtocol

/// Keeps copies of the ALL-Link databases of the modem and its devices, so each is read over
/// the network only when it has changed.
///
/// Reading a device's database takes a request for every record, so the cache keeps what it
/// read along with the device's ALL-Link database delta at the time. The delta is a byte the
/// device changes whenever its database does, and it arrives in the acknowledgement of a
/// status request. Before handing back a copy, the cache asks for the delta again: one
/// standard message instead of a read. A device whose delta has changed is read again.
///
/// The modem's own database has no delta every modem reports, so the cache reads it once
/// and keeps it until ``AllLinkDatabaseCache/invalidateModem()``. ``Linker`` and ``Unlinker``
/// invalidate it whenever they change the modem's records.
///
/// ```swift
/// let cache = AllLinkDatabaseCache(modem: modem)
/// let linker = Linker(modem: modem, cache: cache)
///
/// try await linker.link(group)
/// let records = try await cache.records(of: lamp)   // No read: the linker kept it up to date.
/// ```
///
/// The copies live in memory for as long as the cache does.
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
  /// - Throws: The modem's errors, such as `ModemError.deviceRejected` from an i2cs device
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

  /// Replaces a device's copy with records written to it, at the device's delta after the
  /// writes, so the next request doesn't read the database again. If the delta can't be read,
  /// the copy is forgotten instead.
  ///
  /// - Parameters:
  ///   - records: The device's records as they now are.
  ///   - device: The device.
  func store(_ records: [AllLinkRecordResponse], of device: InsteonAddress) async {

    do {

      devices[device] = DeviceDatabase(delta: try await databaseDelta(of: device), records: records)

    } catch {

      devices[device] = nil

    }

  }

  /// The device's ALL-Link database delta, which its acknowledgement of a status request
  /// carries in cmd1.
  private func databaseDelta(of device: InsteonAddress) async throws -> UInt8 {

    let acknowledgement = try await modem.request(
      StandardMessage(to: device, command: StandardDirectCommand.statusRequest()),
      timeout: timeout
    )

    return acknowledgement.command.command1

  }

}
