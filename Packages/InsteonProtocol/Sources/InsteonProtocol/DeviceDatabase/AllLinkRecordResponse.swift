/// A record a device sends from its ALL-Link database, in reply to an
/// ``AllLinkDatabaseRequest``.
///
/// The response is an extended ``ExtendedDirectCommand/readWriteAllLinkDatabase`` message with
/// D2 `0x01`: D3 and D4 hold the record's address and D6 through D13 hold the record. An i2cs
/// device puts a checksum in D14, which ``AllLinkRecordResponse/hasIntactChecksum`` checks;
/// older devices may not, so a record from one of them can fail the check and still be whole.
public struct AllLinkRecordResponse: Hashable, Sendable {

  /// The device whose database holds the record.
  public var sender: InsteonAddress

  /// The record's address in the device's database.
  public var address: UInt16

  /// The record.
  public var record: AllLinkRecord

  /// Whether D14 holds the checksum of cmd1, cmd2 and D1 through D13, as an i2cs device sends
  /// it. A record from an i2cs device that fails the check was damaged on the way; read it
  /// again.
  public var hasIntactChecksum: Bool

  /// Creates a record response.
  ///
  /// - Parameters:
  ///   - sender: The device whose database holds the record.
  ///   - address: The record's address.
  ///   - record: The record.
  ///   - hasIntactChecksum: Whether D14 held the response's checksum. Defaults to `true`.
  public init(
    sender: InsteonAddress,
    address: UInt16,
    record: AllLinkRecord,
    hasIntactChecksum: Bool = true
  ) {

    self.sender = sender
    self.address = address
    self.record = record
    self.hasIntactChecksum = hasIntactChecksum

  }

  /// Reads a record response from a received message.
  ///
  /// - Parameter message: A message the modem received.
  /// - Returns: `nil` unless the message is an extended direct message with cmd1 `0x2F`,
  ///   cmd2 `0x00` and D2 `0x01`.
  public init?(_ message: ReceivedMessage) {

    guard
      message.flags.messageType == .direct,
      message.command == ExtendedDirectCommand.readWriteAllLinkDatabase.command,
      let data = message.userData,
      data[2] == 0x01
    else {

      return nil

    }

    self.init(
      sender: message.sender,
      address: UInt16(highByte: data[3], lowByte: data[4]),
      record: AllLinkRecord(data.bytes, at: 5),
      hasIntactChecksum: ChecksumIntegrity().isIntact(data, for: message.command)
    )

  }

  /// Whether the record marks the end of the database: one that has never been used, so
  /// ``AllLinkRecordFlags/usedBefore`` is clear. The device sends no records after it.
  public var isEndOfDatabase: Bool {

    !record.flags.contains(.usedBefore)

  }

}
