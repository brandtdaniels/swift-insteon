/// What a ``ExtendedDirectCommand/readWriteAllLinkDatabase`` message asks of a device's ALL-Link
/// database, encoded as its user data.
///
/// A device's records are 8 bytes long and are numbered by addresses that count down by 8. The
/// device answers each read with an ``AllLinkRecordResponse``.
///
/// ```swift
/// let message = AllLinkDatabaseRequest.read(address: 0x0000).message(to: device)
/// ```
public enum AllLinkDatabaseRequest: Hashable, Sendable {

  /// Reads every record, starting with the first (D2 `0x00`, D5 `0x00`).
  ///
  /// The device sends a response for each record, ending with the one that marks the end of
  /// its database.
  case readAll

  /// Reads the record at `address` (D2 `0x00`, D5 `0x01`).
  ///
  /// Address `0x0000` reads the first record, whatever its address in the device's memory.
  case read(address: UInt16)

  /// Writes `record` at `address` (D2 `0x02`, D5 `0x08`, the record's length).
  case write(AllLinkRecord, address: UInt16)

  /// The request's user data: D2 selects reading or writing, D3 and D4 hold the address, D5
  /// holds the number of records to read or bytes to write, and D6 through D13 hold the
  /// record to write. D1 and D14 are unused.
  public var userData: UserData {

    // D1 through D5, then the record to write.
    let header: [UInt8], record: [UInt8]

    switch self {
    case .readAll:
      header = [0x00, 0x00, 0x00, 0x00, 0x00]
      record = []
    case let .read(address):
      header = [0x00, 0x00] + address.bigEndianBytes + [0x01]
      record = []
    case let .write(written, address):
      record = written.bytes
      header = [0x00, 0x02] + address.bigEndianBytes + [UInt8(record.count)]
    }

    var userData = UserData()

    for (index, byte) in (header + record).enumerated() {

      userData[index + 1] = byte

    }

    return userData

  }

  /// The extended message that sends the request to a device, sealed with a checksum, which
  /// i2CS devices require.
  ///
  /// - Parameter device: The device whose database to read or write.
  /// - Returns: The message.
  public func message(to device: InsteonAddress) -> ExtendedMessage {

    ExtendedMessage(to: device, command: ExtendedDirectCommand.readWriteAllLinkDatabase, userData: userData)

  }

}
