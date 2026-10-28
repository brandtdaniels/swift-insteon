/// A record a device sends from its ALL-Link database, in reply to an
/// ``AllLinkDatabaseRequest``.
///
/// The response is an extended ``ExtendedDirectCommand/readWriteAllLinkDatabase`` message with
/// D2 `0x01`: D3 and D4 hold the record's address and D6 through D13 hold the record.
public struct AllLinkRecordResponse: Hashable, Sendable {

  /// The device whose database holds the record.
  public var sender: InsteonAddress

  /// The record's address in the device's database.
  public var address: UInt16

  /// The record.
  public var record: AllLinkRecord

  /// Creates a record response.
  ///
  /// - Parameters:
  ///   - sender: The device whose database holds the record.
  ///   - address: The record's address.
  ///   - record: The record.
  public init(sender: InsteonAddress, address: UInt16, record: AllLinkRecord) {

    self.sender = sender
    self.address = address
    self.record = record

  }

  /// Reads a record response from a received message.
  ///
  /// - Parameter message: A message the modem received.
  /// - Returns: `nil` unless the message is an extended direct message with cmd1 `0x2F` and
  ///   D2 `0x01`.
  public init?(_ message: ReceivedMessage) {

    guard
      message.flags.messageType == .direct,
      message.command.command1 == 0x2F,
      let data = message.userData,
      data[2] == 0x01
    else {

      return nil

    }

    self.init(
      sender: message.sender,
      address: UInt16(highByte: data[3], lowByte: data[4]),
      record: AllLinkRecord(
        flags: AllLinkRecordFlags(rawValue: data[6]),
        group: AllLinkGroupNumber(rawValue: data[7]),
        address: InsteonAddress(data[8], data[9], data[10]),
        data1: data[11],
        data2: data[12],
        data3: data[13]
      )
    )

  }

  /// Whether the record marks the end of the database: one that has never been used, so
  /// ``AllLinkRecordFlags/usedBefore`` is clear. The device sends no records after it.
  public var isEndOfDatabase: Bool {

    !record.flags.contains(.usedBefore)

  }

}
