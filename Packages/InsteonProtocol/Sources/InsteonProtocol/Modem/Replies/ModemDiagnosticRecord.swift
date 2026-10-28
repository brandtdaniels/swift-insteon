/// A troubled exchange a modem recorded, reported in reply to
/// ``SerialCommand/readDiagnostics(index:)``.
///
/// Later modem firmware keeps the last 32 distinct exchanges that went wrong: NAKs, messages
/// that took all three hops, Success Reports with errors, and messages from the modem that no
/// device acknowledged.
public struct ModemDiagnosticRecord: Hashable, Sendable {

  /// The message's sender: the modem's own address for a message the modem sent.
  public var sender: InsteonAddress

  /// The message's recipient.
  public var recipient: InsteonAddress

  /// The message's flags.
  public var flags: MessageFlags

  /// How many times the record's exchange went wrong.
  public var count: UInt8

  /// A running total the modem keeps across records.
  public var totalCount: UInt16

  /// Creates a record.
  ///
  /// - Parameters:
  ///   - sender: The message's sender.
  ///   - recipient: The message's recipient.
  ///   - flags: The message's flags.
  ///   - count: How many times the exchange went wrong.
  ///   - totalCount: The modem's running total.
  public init(sender: InsteonAddress, recipient: InsteonAddress, flags: MessageFlags, count: UInt8, totalCount: UInt16) {

    self.sender = sender
    self.recipient = recipient
    self.flags = flags
    self.count = count
    self.totalCount = totalCount

  }

  /// Whether the record is empty: the modem has nothing recorded at its index.
  public var isEmpty: Bool {

    sender == InsteonAddress(0, 0, 0) && recipient == InsteonAddress(0, 0, 0) && count == 0

  }

}

extension ModemDiagnosticRecord {

  /// Decodes a record from its 10 bytes: the sender, the recipient, the flags, the count and
  /// the two bytes of the running total, high byte first.
  init(_ bytes: [UInt8]) {

    self.init(
      sender: InsteonAddress(bytes[0], bytes[1], bytes[2]),
      recipient: InsteonAddress(bytes[3], bytes[4], bytes[5]),
      flags: MessageFlags(rawValue: bytes[6]),
      count: bytes[7],
      totalCount: UInt16(highByte: bytes[8], lowByte: bytes[9])
    )

  }

}
