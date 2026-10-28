import InsteonModem
import InsteonProtocol

/// Writes and deletes records in the ALL-Link databases of the modem and its devices.
///
/// A device's records are written the way the developer guide describes for a linear
/// database: a record that already links the same devices in the same group is updated in
/// place, otherwise the first available record is reused, otherwise the record goes at the end
/// and the record after it becomes the new end. Each write is read back to check it.
struct DatabaseEditor: Sendable {

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

  /// The flags of a record in use, as in Insteon's own examples: `0xE2` for a controller
  /// record and `0xA2` for a responder record, which also set the product-dependent bit 5.
  static func flags(isController: Bool) -> AllLinkRecordFlags {

    AllLinkRecordFlags(rawValue: isController ? 0xE2 : 0xA2)

  }

  /// The addresses of a group's controller and responders, reading the modem's own address
  /// when the group includes it.
  func addresses(for group: AllLinkGroup) async throws -> Addresses {

    let endpoints = [group.controller] + group.responders.map(\.endpoint)

    guard endpoints.contains(.modem) else {

      return Addresses(modem: nil)

    }

    return Addresses(modem: try await modemAddress())

  }

  /// Writes a record into an endpoint's ALL-Link database, updating the record that links the
  /// same device in the same group and role if there is one.
  func write(_ record: AllLinkRecord, into endpoint: LinkEndpoint) async throws {

    switch endpoint {
    case .modem:
      let isController = record.flags.contains(.controller)

      try await modem.send(.manageAllLinkRecord(
        action: isController ? .modifyFirstControllerOrAdd : .modifyFirstResponderOrAdd,
        record: record
      ))
    case let .device(device):
      try await write(record, into: device)
    }

  }

  /// Deletes the records in an endpoint's ALL-Link database that link `address` in `group` in
  /// the given role.
  ///
  /// The modem finds a record to delete by its group and address alone, so where the modem
  /// both controls and responds to the same device in the same group, it deletes whichever
  /// record it finds first.
  func delete(
    group: AllLinkGroupNumber,
    address: InsteonAddress,
    isController: Bool,
    from endpoint: LinkEndpoint
  ) async throws {

    switch endpoint {
    case .modem:
      let record = AllLinkRecord(flags: Self.flags(isController: isController), group: group, address: address)

      do {

        try await modem.send(.manageAllLinkRecord(action: .deleteFirst, record: record))

      } catch ModemError.rejected(.manageAllLinkRecord) {

        // The modem NAKs a delete when it has no matching record, so it's already gone.

      }
    case let .device(device):
      let records = try await modem.readAllLinkDatabase(of: device, timeout: timeout)

      for response in records where response.record.flags.contains(.inUse) {

        let existing = response.record

        guard
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

        try await write(deleted, at: response.address, in: device)

      }
    }

  }

  // MARK: - Devices

  private func write(_ record: AllLinkRecord, into device: InsteonAddress) async throws {

    let records = try await modem.readAllLinkDatabase(of: device, timeout: timeout)

    let isController = record.flags.contains(.controller)

    if let existing = records.first(where: { response in

      response.record.flags.contains(.inUse)
        && response.record.group == record.group
        && response.record.address == record.address
        && response.record.flags.contains(.controller) == isController

    }) {

      if existing.record != record {

        try await write(record, at: existing.address, in: device)

      }

    } else if let available = records.first(where: { !$0.isEndOfDatabase && !$0.record.flags.contains(.inUse) }) {

      try await write(record, at: available.address, in: device)

    } else if let end = records.last, end.isEndOfDatabase, end.address > 8 {

      // The record below the end becomes the new end before the end is overwritten, so the
      // database always has an end even if the second write fails.
      try await write(Self.endOfDatabase, at: end.address - 8, in: device)
      try await write(record, at: end.address, in: device)

    } else {

      throw LinkingError.databaseFull(device)

    }

  }

  /// Writes a record at an address and reads it back.
  private func write(_ record: AllLinkRecord, at address: UInt16, in device: InsteonAddress) async throws {

    _ = try await modem.request(AllLinkDatabaseRequest.write(record, address: address).message(to: device), timeout: timeout)

    let written = try await modem.request(
      AllLinkDatabaseRequest.read(address: address).message(to: device),
      awaitingReply: { message in

        AllLinkRecordResponse(message).flatMap { $0.address == address ? $0 : nil }

      },
      timeout: timeout
    )

    guard written.record == record else {

      throw LinkingError.recordNotWritten(device, address: address)

    }

  }

  /// A record that has never been used, which marks the end of a database.
  private static let endOfDatabase = AllLinkRecord(flags: [], group: 0x00, address: InsteonAddress(0x00, 0x00, 0x00))

  // MARK: - The modem

  /// Reads the modem's own address, which devices' records use to link to it.
  private func modemAddress() async throws -> InsteonAddress {

    let replies = await modem.replies()

    try await modem.send(.getModemInfo)

    for await reply in replies {

      if case let .modemInfo(info) = reply {

        return info.address

      }

    }

    throw LinkingError.modemAddressUnavailable

  }

}
