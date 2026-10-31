import InsteonModem
import InsteonProtocol

/// Writes and deletes records in the ALL-Link databases of the modem and its devices.
///
/// A device's records are written the way the Insteon Developer's Guide describes for a linear
/// database: records that already link the same device in the same group and role are updated
/// in place, otherwise the first record no longer in use is reused, otherwise the record goes
/// at the end and the record after it becomes the new end. Each write is read back to check
/// it. Each device's database is read once, then kept up to date as records are written. With
/// a cache, databases are read through it, and a device's copy is forgotten once its database
/// changes, so the device stays the source of truth.
struct DatabaseEditor {

  /// The addresses of a group's endpoints.
  struct Addresses: Sendable {

    /// The modem's address, read only when a group includes the modem.
    let modem: InsteonAddress?

    func address(of endpoint: LinkEndpoint) -> InsteonAddress {

      switch endpoint {
      case let .device(address):
        return address
      case .modem:
        guard let modem else {

          preconditionFailure("The modem's address is read for every group that includes the modem.")

        }

        return modem
      }

    }

  }

  let modem: any LinkingModem

  let timeout: Duration

  let cache: AllLinkDatabaseCache?

  /// The device databases read so far, kept up to date with every write.
  private var databases: [InsteonAddress: [AllLinkRecordResponse]] = [:]

  init(modem: any LinkingModem, timeout: Duration, cache: AllLinkDatabaseCache?) {

    self.modem = modem
    self.timeout = timeout
    self.cache = cache

  }

  /// The flags of a record in use: `0xE2` for a controller
  /// record and `0xA2` for a responder record, which also set the product-dependent bit 5.
  static func flags(isController: Bool) -> AllLinkRecordFlags {

    AllLinkRecordFlags(rawValue: isController ? 0xE2 : 0xA2)

  }

  /// The address of the lowest record in a device's database. Insteon's Data Base Format
  /// sheet places device records from `0x0FFF` down to `0x0300`.
  static let lowestRecordAddress: UInt16 = 0x0307

  /// A record that has never been used, which marks the end of a database.
  private static let endOfDatabase = AllLinkRecord(flags: [], group: 0x00, address: InsteonAddress(0x00, 0x00, 0x00))

  /// The addresses of a group's controller and responders, reading the modem's own address
  /// when the group includes it.
  func addresses(for group: AllLinkGroup) async throws -> Addresses {

    let endpoints = [group.controller] + group.responders.map(\.endpoint)

    guard endpoints.contains(.modem) else {

      return Addresses(modem: nil)

    }

    return Addresses(modem: try await modem.modemInfo().address)

  }

  /// Writes a record into an endpoint's ALL-Link database.
  ///
  /// A responder record updates the records that link the same device in the same group. A
  /// controller record is added only when there's none: an existing one holds data the
  /// controller keeps for itself, such as the modem's copy of the responder's category or a
  /// keypad's button number, so it stays as it is.
  mutating func write(_ record: AllLinkRecord, into endpoint: LinkEndpoint) async throws {

    switch endpoint {
    case .modem:
      try await writeToModem(record)
    case let .device(device):
      try await write(record, into: device)
    }

  }

  /// Deletes the records in an endpoint's ALL-Link database that link `address` in `group` in
  /// the given role.
  mutating func delete(
    group: AllLinkGroupNumber,
    address: InsteonAddress,
    isController: Bool,
    from endpoint: LinkEndpoint
  ) async throws {

    switch endpoint {
    case .modem:
      try await deleteFromModem(group: group, address: address, isController: isController)
    case let .device(device):
      var records = try await database(of: device)
      var deletedAny = false

      for index in records.indices {

        let existing = records[index].record

        guard
          existing.flags.contains(.inUse),
          existing.group == group,
          existing.address == address,
          existing.flags.contains(.controller) == isController
        else {

          continue

        }

        // Clearing the in-use bit deletes a record, and leaving the used-before bit set keeps
        // it from ending the database.
        var deleted = existing
        deleted.flags.remove(.inUse)

        try await write(deleted, at: records[index].address, in: device)
        records[index].record = deleted
        deletedAny = true

      }

      if deletedAny {

        await store(records, of: device)

      }
    }

  }

  // MARK: - Devices

  private mutating func write(_ record: AllLinkRecord, into device: InsteonAddress) async throws {

    let original = try await database(of: device)
    var records = original
    let isController = record.flags.contains(.controller)

    let matches = records.indices.filter { index in

      let existing = records[index].record

      return existing.flags.contains(.inUse)
        && existing.group == record.group
        && existing.address == record.address
        && existing.flags.contains(.controller) == isController

    }

    if !matches.isEmpty {

      guard !isController else {

        return

      }

      for index in matches where !Self.isSame(records[index].record, record) {

        try await write(record, at: records[index].address, in: device)
        records[index].record = record

      }

    } else if let index = records.firstIndex(where: { !$0.isEndOfDatabase && !$0.record.flags.contains(.inUse) }) {

      try await write(record, at: records[index].address, in: device)
      records[index].record = record

    } else if let end = records.last, end.isEndOfDatabase, end.address >= Self.lowestRecordAddress + 8 {

      // The record below the end becomes the new end before the end is overwritten, so the
      // database always has an end even if the second write fails.
      let newEnd = end.address - 8

      try await write(Self.endOfDatabase, at: newEnd, in: device)
      try await write(record, at: end.address, in: device)

      records[records.count - 1].record = record
      records.append(AllLinkRecordResponse(sender: device, address: newEnd, record: Self.endOfDatabase))

    } else {

      throw LinkingError.databaseFull(device)

    }

    if records != original {

      await store(records, of: device)

    }

  }

  /// Whether two records are the same but for the flags a device may change on its own, such
  /// as its smart hop count.
  private static func isSame(_ record: AllLinkRecord, _ other: AllLinkRecord) -> Bool {

    var record = record, other = other
    record.flags.subtract(.deviceMaintained)
    other.flags.subtract(.deviceMaintained)

    return record == other

  }

  /// Writes a record at an address and reads it back.
  private func write(_ record: AllLinkRecord, at address: UInt16, in device: InsteonAddress) async throws {

    _ = try await modem.request(AllLinkDatabaseRequest.write(record, address: address).message(to: device), timeout: timeout)

    let written = try await modem.readAllLinkRecord(of: device, at: address, timeout: timeout)

    guard Self.isSame(written.record, record) else {

      throw LinkingError.recordNotWritten(device, address: address)

    }

  }

  /// A device's database, read the first time it's needed.
  private mutating func database(of device: InsteonAddress) async throws -> [AllLinkRecordResponse] {

    if let records = databases[device] {

      return records

    }

    let records = if let cache {

      try await cache.records(of: device)

    } else {

      try await modem.readAllLinkDatabase(of: device, timeout: timeout)

    }

    databases[device] = records

    return records

  }

  /// Keeps a device's records as they are after a write, and forgets the cache's copy, which
  /// is read again from the device next time.
  private mutating func store(_ records: [AllLinkRecordResponse], of device: InsteonAddress) async {

    databases[device] = records
    await cache?.invalidate(device)

  }

  // MARK: - The modem

  private func writeToModem(_ record: AllLinkRecord) async throws {

    let isController = record.flags.contains(.controller)

    if isController {

      let existing = try await modem.allLinkRecords(group: record.group, device: record.address)

      guard !existing.contains(where: { $0.flags.contains(.controller) }) else {

        return

      }

    }

    try await modem.send(.manageAllLinkRecord(
      action: isController ? .modifyFirstControllerOrAdd : .modifyFirstResponderOrAdd,
      record: record
    ))

    await cache?.invalidateModem()

  }

  private func deleteFromModem(group: AllLinkGroupNumber, address: InsteonAddress, isController: Bool) async throws {

    let existing = try await modem.allLinkRecords(group: group, device: address)

    guard existing.contains(where: { $0.flags.contains(.controller) == isController }) else {

      return

    }

    // The modem deletes the first record matching a group and address whatever its role, so
    // every match is deleted and those of the other role are added back.
    let key = AllLinkRecord(flags: [], group: group, address: address)
    let otherRole: [AllLinkRecord] = existing.filter { (record: AllLinkRecord) -> Bool in record.flags.contains(.controller) != isController }

    do {

      for _ in existing {

        try await modem.send(.manageAllLinkRecord(action: .deleteFirst, record: key))

      }

      for record in otherRole {

        try await modem.send(.manageAllLinkRecord(action: Self.addAction(for: record), record: record))

      }

    } catch {

      // A record of the other role that's gone is a link the caller didn't ask to remove, so
      // each one that's gone is added back once more, in a task of its own that canceling this
      // one doesn't reach.
      let modem: any LinkingModem = modem
      let missing: [AllLinkRecord] = await Task { () async -> [AllLinkRecord] in

        await Self.restore(otherRole, group: group, address: address, on: modem)

      }.value

      // Some records changed, before the failure and since.
      await cache?.invalidateModem()

      if !missing.isEmpty {

        throw ModemRecordsNotRestored(records: missing, cause: error)

      }

      throw error

    }

    await cache?.invalidateModem()

  }

  /// The action that adds a record to the modem's database in its role.
  private static func addAction(for record: AllLinkRecord) -> AllLinkRecordAction {

    record.flags.contains(.controller) ? .modifyFirstControllerOrAdd : .modifyFirstResponderOrAdd

  }

  /// Adds back each record that isn't in the modem's database as it was. If the database
  /// can't be read, each one is added: adding updates a record of the same role in place.
  ///
  /// - Returns: The records that couldn't be added back.
  private static func restore(_ records: [AllLinkRecord], group: AllLinkGroupNumber, address: InsteonAddress, on modem: any LinkingModem) async -> [AllLinkRecord] {

    guard !records.isEmpty else {

      return []

    }

    let remaining: [AllLinkRecord]? = try? await modem.allLinkRecords(group: group, device: address)
    var missing: [AllLinkRecord] = []

    for record in records where !(remaining?.contains(record) ?? false) {

      do {

        try await modem.send(.manageAllLinkRecord(action: addAction(for: record), record: record))

      } catch {

        missing.append(record)

      }

    }

    return missing

  }

}
