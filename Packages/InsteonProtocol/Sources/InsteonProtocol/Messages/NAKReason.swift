/// Why a device rejected a direct or ALL-Link cleanup message: the cmd2 of its NAK.
///
/// The codes count down from `0xFF`. Devices with an i1 or i2 ``InsteonEngine`` use `0xFD`
/// through `0xFF`; i2CS devices use the full set below and read `0xFD` and `0xFF` slightly
/// differently, as each code's documentation notes. i3 devices add `0xF8`. Any other value is
/// reserved.
///
/// ```swift
/// if message.flags.messageType == .directNegativeAcknowledgment,
///    NAKReason(rawValue: message.command.command2) == .notLinked {
///   // Link the devices first.
/// }
/// ```
public struct NAKReason: RawRepresentable, Hashable, Sendable {

  /// The code carried in the NAK's cmd2.
  public var rawValue: UInt8

  /// Creates a reason from its code.
  ///
  /// - Parameter rawValue: The code carried in the NAK's cmd2.
  public init(rawValue: UInt8) {

    self.rawValue = rawValue

  }

  /// The sender isn't linked to the device (`0xFF`).
  ///
  /// i1 and i2 devices mean the sender isn't in the ALL-Link group; i2CS devices mean its
  /// address isn't in their ALL-Link database.
  public static let notLinked = NAKReason(rawValue: 0xFF)

  /// The device detected no load (`0xFE`).
  public static let noLoad = NAKReason(rawValue: 0xFE)

  /// The device didn't accept the command (`0xFD`).
  ///
  /// i1 and i2 devices mean the command is unknown; i2CS devices also send it when an extended
  /// message's checksum is wrong.
  public static let invalidCommand = NAKReason(rawValue: 0xFD)

  /// The device is still searching its ALL-Link database, and answers once the search
  /// finishes (`0xFC`, i2CS).
  public static let databaseSearchPending = NAKReason(rawValue: 0xFC)

  /// A value in the command is out of range (`0xFB`, i2CS).
  public static let illegalValue = NAKReason(rawValue: 0xFB)

  /// Group 0 was asked to send a group command, which it can't (`0xFA`, i2CS).
  public static let groupZeroCommand = NAKReason(rawValue: 0xFA)

  /// The device's ALL-Link database is full (`0xF9`, i2CS).
  public static let databaseFull = NAKReason(rawValue: 0xF9)

  /// The device has no hardware to carry out the command (`0xF8`, i3).
  public static let noHardware = NAKReason(rawValue: 0xF8)

}

extension NAKReason {

  /// The reason in words, as a clause about the device that sent the NAK, such as
  /// `"it isn't linked to the modem"`; a reserved code reads as `"NAK reason 0xF0"`.
  ///
  /// ```swift
  /// print("The device rejected the command: \(reason.summary).")
  /// ```
  public var summary: String {

    switch self {
    case .notLinked: "it isn't linked to the modem"
    case .noLoad: "it has no load connected"
    case .invalidCommand: "it doesn't support the command"
    case .databaseSearchPending: "it's still searching its ALL-Link database"
    case .illegalValue: "a value is out of range"
    case .groupZeroCommand: "the command isn't allowed for group 0"
    case .databaseFull: "its ALL-Link database is full"
    case .noHardware: "it lacks the hardware for the command"
    default: "NAK reason 0x" + rawValue.hexDigits
    }

  }

}
