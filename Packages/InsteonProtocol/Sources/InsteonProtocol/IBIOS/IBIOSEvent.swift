/// An event IBIOS reports to the host, identified by its handle.
///
/// IBIOS reports each event in an ``IBIOSReply/eventReport(_:)``, and the SALad program a
/// PowerLinc Controller ships with also reports the INSTEON message behind events
/// ``IBIOSEvent/messageForMe`` through ``IBIOSEvent/enrollmentMessage`` in an
/// ``IBIOSReply/messageReceived(_:message:)``. Handles this type doesn't name keep their
/// number.
public struct IBIOSEvent: RawRepresentable, Hashable, Sendable {

  /// The event's handle.
  public var rawValue: UInt8

  /// Creates an event from its handle.
  ///
  /// - Parameter rawValue: The event's handle.
  public init(rawValue: UInt8) {

    self.rawValue = rawValue

  }

  /// The SALad program started (`0x00`), as it does at power-up.
  public static let initialized = IBIOSEvent(rawValue: 0x00)

  /// A new INSTEON message addressed to this device arrived (`0x01`).
  public static let messageForMe = IBIOSEvent(rawValue: 0x01)

  /// A new INSTEON message addressed to another device arrived (`0x02`).
  public static let messageForOthers = IBIOSEvent(rawValue: 0x02)

  /// A repeat of a message already received arrived on a later hop (`0x03`).
  public static let duplicateMessage = IBIOSEvent(rawValue: 0x03)

  /// The device acknowledged a direct message this device sent (`0x04`).
  public static let sendAcknowledged = IBIOSEvent(rawValue: 0x04)

  /// A direct message this device sent wasn't acknowledged after five retries (`0x05`).
  public static let sendNotAcknowledged = IBIOSEvent(rawValue: 0x05)

  /// A message arrived from a device this one isn't linked to, with its contents masked
  /// (`0x06`).
  public static let unknownSender = IBIOSEvent(rawValue: 0x06)

  /// A message arrived during enrollment, with its contents unmasked (`0x07`).
  public static let enrollmentMessage = IBIOSEvent(rawValue: 0x07)

  /// An X10 byte arrived (`0x08`).
  public static let x10Received = IBIOSEvent(rawValue: 0x08)

  /// An X10 extended message byte arrived (`0x09`).
  public static let x10ExtendedReceived = IBIOSEvent(rawValue: 0x09)

  /// The SET button was tapped (`0x0A`).
  public static let buttonTapped = IBIOSEvent(rawValue: 0x0A)

  /// The SET button is being held (`0x0B`).
  public static let buttonHeld = IBIOSEvent(rawValue: 0x0B)

  /// The SET button was released (`0x0C`).
  public static let buttonReleased = IBIOSEvent(rawValue: 0x0C)

}

extension IBIOSEvent: CustomStringConvertible {

  /// The handle in hexadecimal, such as `"0x01"`.
  public var description: String {

    "0x" + rawValue.hexDigits

  }

}
