/// A command sent from a host to an INSTEON modem (IM), such as a PowerLinc Modem or the
/// modem inside an INSTEON Hub.
///
/// Each command encodes to ``SerialCommand/startOfText``, its ``SerialCommand/number`` and
/// its parameters:
///
/// ```swift
/// let lamp = InsteonAddress(0xAA, 0xBB, 0xCC)
/// let message = StandardMessage(to: lamp, command: StandardDirectCommand.on(level: 0xFF))
///
/// SerialCommand.sendStandardMessage(message).hexString  // "0262AABBCC0F11FF"
/// ```
public enum SerialCommand: Hashable, Sendable {

  /// Requests the modem's address, device category and firmware version.
  case getModemInfo

  /// Sends a command to every device in one of the modem's ALL-Link groups.
  ///
  /// The modem broadcasts the command, then sends ALL-Link cleanup messages to each member of
  /// the group in turn.
  ///
  /// - Parameters:
  ///   - group: The ALL-Link group to address.
  ///   - command: The command to send. Its cmd2 is usually `0x00`, or `0xFF` for a full-on
  ///     level.
  case sendAllLinkCommand(group: UInt8, command: Command)

  /// Sends a standard-length INSTEON message.
  case sendStandardMessage(StandardMessage)

  /// Sends an extended-length INSTEON message.
  case sendExtendedMessage(ExtendedMessage)

  /// Sends an X10 unit address or command over the power line.
  case sendX10(X10Code)

  /// Puts the modem into ALL-Linking mode for a group.
  ///
  /// - Parameters:
  ///   - mode: The role the modem takes in the link, or ``AllLinkMode/delete`` to unlink.
  ///   - group: The ALL-Link group to link.
  case startAllLinking(mode: AllLinkMode, group: UInt8)

  /// Takes the modem out of ALL-Linking mode.
  case cancelAllLinking

  /// Sets the device category the modem reports when it links with other devices.
  ///
  /// - Parameters:
  ///   - category: The device category.
  ///   - subcategory: The device subcategory.
  ///   - firmwareVersion: The firmware version to report, or `0xFF` for none.
  case setHostDeviceCategory(category: UInt8, subcategory: UInt8, firmwareVersion: UInt8)

  /// Resets the modem to factory defaults, erasing its ALL-Link database.
  case resetModem

  /// Sets the cmd2 byte the modem sends in its ACKs to direct messages.
  case setAcknowledgementByte(UInt8)

  /// Requests the first record in the modem's ALL-Link database.
  case getFirstAllLinkRecord

  /// Requests the next record in the modem's ALL-Link database.
  case getNextAllLinkRecord

  /// Sets the modem's configuration flags.
  case setModemConfiguration(ModemConfiguration)

  /// Requests the ALL-Link record for the device that sent the last INSTEON message.
  case getAllLinkRecordForSender

  /// Turns the modem's LED on.
  ///
  /// The modem NAKs this unless ``ModemConfiguration/disableAutomaticLED`` is set, giving the
  /// host control of the LED.
  case ledOn

  /// Turns the modem's LED off.
  ///
  /// The modem NAKs this unless ``ModemConfiguration/disableAutomaticLED`` is set, giving the
  /// host control of the LED.
  case ledOff

  /// Finds, adds, changes or deletes a record in the modem's ALL-Link database.
  ///
  /// - Parameters:
  ///   - action: What to do with the record.
  ///   - record: The record to find, write or delete.
  case manageAllLinkRecord(action: AllLinkRecordAction, record: AllLinkRecord)

  /// Sets the cmd2 byte the modem sends in its NAKs to direct messages.
  case setNegativeAcknowledgementByte(UInt8)

  /// Sets the cmd1 and cmd2 bytes the modem sends in its ACKs to direct messages.
  case setAcknowledgementBytes(Command)

  /// Puts the modem's RF transceiver to sleep until it receives another command.
  case rfSleep

  /// Requests the modem's configuration flags.
  case getModemConfiguration

  /// Stops the modem from sending ALL-Link cleanup messages for the last ALL-Link command.
  case cancelCleanup

  /// Reads the 8-byte ALL-Link record at a database address.
  ///
  /// - Parameter address: The record's address in the modem's database.
  case readDatabase(address: UInt16)

  /// Writes an 8-byte ALL-Link record at a database address.
  ///
  /// - Parameters:
  ///   - address: The record's address in the modem's database.
  ///   - record: The record to write.
  case writeDatabase(address: UInt16, record: AllLinkRecord)

  /// Makes the modem beep.
  case beep

  /// Sets how many times the modem retries a direct message that isn't acknowledged.
  case setApplicationRetries(UInt8)

  /// The byte that starts every serial command: `0x02`.
  public static let startOfText: UInt8 = 0x02

  /// The command's number.
  public var number: SerialCommandNumber {

    switch self {
    case .getModemInfo: .getModemInfo
    case .sendAllLinkCommand: .sendAllLinkCommand
    case .sendStandardMessage, .sendExtendedMessage: .sendMessage
    case .sendX10: .sendX10
    case .startAllLinking: .startAllLinking
    case .cancelAllLinking: .cancelAllLinking
    case .setHostDeviceCategory: .setHostDeviceCategory
    case .resetModem: .resetModem
    case .setAcknowledgementByte: .setAcknowledgementByte
    case .getFirstAllLinkRecord: .getFirstAllLinkRecord
    case .getNextAllLinkRecord: .getNextAllLinkRecord
    case .setModemConfiguration: .setModemConfiguration
    case .getAllLinkRecordForSender: .getAllLinkRecordForSender
    case .ledOn: .ledOn
    case .ledOff: .ledOff
    case .manageAllLinkRecord: .manageAllLinkRecord
    case .setNegativeAcknowledgementByte: .setNegativeAcknowledgementByte
    case .setAcknowledgementBytes: .setAcknowledgementBytes
    case .rfSleep: .rfSleep
    case .getModemConfiguration: .getModemConfiguration
    case .cancelCleanup: .cancelCleanup
    case .readDatabase: .readDatabase
    case .writeDatabase: .writeDatabase
    case .beep: .beep
    case .setApplicationRetries: .setApplicationRetries
    }

  }

  /// The bytes that follow the command number.
  public var parameters: [UInt8] {

    switch self {
    case let .sendAllLinkCommand(group, command):
      [group] + command.bytes
    case let .sendStandardMessage(message):
      message.bytes
    case let .sendExtendedMessage(message):
      message.bytes
    case let .sendX10(code):
      code.bytes
    case let .startAllLinking(mode, group):
      [mode.rawValue, group]
    case let .setHostDeviceCategory(category, subcategory, firmwareVersion):
      [category, subcategory, firmwareVersion]
    case let .setAcknowledgementByte(command2), let .setNegativeAcknowledgementByte(command2):
      [command2]
    case let .setApplicationRetries(retries):
      [retries]
    case let .setModemConfiguration(configuration):
      [configuration.rawValue]
    case let .manageAllLinkRecord(action, record):
      [action.rawValue] + record.bytes
    case let .setAcknowledgementBytes(command):
      command.bytes
    case let .readDatabase(address):
      address.bigEndianBytes
    case let .writeDatabase(address, record):
      address.bigEndianBytes + record.bytes
    case .getModemInfo, .cancelAllLinking, .resetModem, .getFirstAllLinkRecord,
      .getNextAllLinkRecord, .getAllLinkRecordForSender, .ledOn, .ledOff, .rfSleep,
      .getModemConfiguration, .cancelCleanup, .beep:
      []
    }

  }

}

// MARK: - ByteEncodable

extension SerialCommand: ByteEncodable {

  /// The command's bytes: ``SerialCommand/startOfText``, the number and the parameters.
  public var bytes: [UInt8] {

    [Self.startOfText, number.rawValue] + parameters

  }

}

extension UInt16 {

  /// The value's two bytes, most significant first.
  var bigEndianBytes: [UInt8] {

    [UInt8(self >> 8), UInt8(self & 0xFF)]

  }

}
