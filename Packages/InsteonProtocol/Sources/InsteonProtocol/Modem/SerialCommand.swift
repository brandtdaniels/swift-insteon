/// A command sent from a host to an Insteon modem (IM), such as a PowerLinc Modem or the
/// modem inside an Insteon Hub.
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
  case sendAllLinkCommand(group: AllLinkGroupNumber, command: Command)

  /// Sends a standard-length Insteon message.
  case sendStandardMessage(StandardMessage)

  /// Sends an extended-length Insteon message.
  case sendExtendedMessage(ExtendedMessage)

  /// Sends an X10 unit address or command over the power line.
  case sendX10(X10Code)

  /// Puts the modem into ALL-Linking mode for a group.
  ///
  /// - Parameters:
  ///   - mode: The role the modem takes in the link, or ``AllLinkMode/delete`` to unlink.
  ///   - group: The ALL-Link group to link.
  case startAllLinking(mode: AllLinkMode, group: AllLinkGroupNumber)

  /// Takes the modem out of ALL-Linking mode.
  case cancelAllLinking

  /// Sets the device category the modem reports when it links with other devices.
  ///
  /// - Parameters:
  ///   - category: The device category.
  ///   - subcategory: The device subcategory.
  ///   - firmwareVersion: The firmware version to report, or `nil` for none, which the modem
  ///     sends as `0xFF`.
  case setHostDeviceCategory(category: DeviceCategory, subcategory: DeviceSubcategory, firmwareVersion: FirmwareVersion?)

  /// Resets the modem to factory defaults, erasing its entire ALL-Link database.
  ///
  /// The modem answers once it has erased its memory, which the Developer's Guide says takes
  /// about 20 seconds on a model with external EEPROM and about 2 seconds on one without.
  case resetModem

  /// Sets the cmd2 byte the modem sends in its ACKs to direct messages.
  case setAcknowledgementByte(UInt8)

  /// Requests the first record in the modem's ALL-Link database.
  ///
  /// The record follows the command's echo. The modem NAKs if the database is empty.
  case getFirstAllLinkRecord

  /// Requests the next record in the modem's ALL-Link database, after
  /// ``SerialCommand/getFirstAllLinkRecord``.
  ///
  /// The record follows the command's echo. The modem NAKs when there are no more records.
  case getNextAllLinkRecord

  /// Sets the modem's configuration flags.
  case setModemConfiguration(ModemConfiguration)

  /// Requests the ALL-Link record for the device that sent the last Insteon message, if that
  /// device is in the modem's ALL-Link database.
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

  /// Puts an RF modem into its power-saving sleep mode. Sending it any byte wakes it; wait at
  /// least 40 ms after waking it before sending a command, as the Developer's Guide says.
  case rfSleep

  /// Requests the modem's configuration flags.
  case getModemConfiguration

  /// Stops the modem from sending ALL-Link cleanup messages for the last ALL-Link command.
  case cancelCleanup

  /// Reads the 8-byte ALL-Link record at a database address.
  ///
  /// - Parameter address: The address of the record's first byte. Records are 8 bytes long,
  ///   so an address inside a record reads parts of two.
  case readDatabase(address: UInt16)

  /// Writes an 8-byte ALL-Link record at a database address.
  ///
  /// - Parameters:
  ///   - address: The address of the record's first byte. Records are 8 bytes long, so an
  ///     address inside a record overwrites parts of two.
  ///   - record: The record to write.
  case writeDatabase(address: UInt16, record: AllLinkRecord)

  /// Makes the modem beep.
  ///
  /// Insteon's command workbook shows later firmware taking a parameter byte, `0x00` for a
  /// beep and `0x01` for a double beep; this sends the form without one, as Insteon's PLM serial
  /// command table first gave it.
  case beep

  /// Sets the data the modem stores in the responder record its next ALL-Link creates.
  ///
  /// The three bytes become ``AllLinkRecord/data1``, ``AllLinkRecord/data2`` and
  /// ``AllLinkRecord/data3`` of the record ``SerialCommand/startAllLinking(mode:group:)``
  /// creates when the modem is the responder. Insteon's command table describes the data as being for the next
  /// link, so send this before each link that needs it.
  ///
  /// - Parameters:
  ///   - data1: The record's first data byte.
  ///   - data2: The record's second data byte.
  ///   - data3: The record's third data byte.
  case setResponderLinkData(data1: UInt8, data2: UInt8, data3: UInt8)

  /// Sets the modem's application retry count, which it reports back with
  /// ``SerialCommand/getModemConfiguration``.
  case setApplicationRetries(UInt8)

  /// Turns the modem's radio on or off.
  ///
  /// ``RadioSetting/enabled`` and ``RadioSetting/disabled`` are saved, so they outlast a power
  /// cycle. A modem with its radio off reaches devices only over the powerline, and one that
  /// has no powerline connection, such as the USB Adapter (2448A7), reaches none until its radio
  /// is turned back on.
  case setRadio(RadioSetting)

  /// Requests the state of the modem's radio, which the modem answers with
  /// ``ModemReply/radioStatus(_:)``. From later modem firmware; others NAK it.
  case readRadioStatus

  /// Requests one of the modem's diagnostic records, which it answers with
  /// ``ModemReply/diagnosticRecord(_:)``. From later modem firmware; others NAK it.
  ///
  /// - Parameter index: The record's index, a multiple of 8 from `0x00` through `0xF8`.
  case readDiagnostics(index: UInt8)

  /// Has the modem find, and optionally change or delete, a record in another device's
  /// ALL-Link database, which it answers with ``ModemReply/deviceRecordFound(address:record:)``.
  /// From later modem firmware; others NAK it.
  case manageDeviceRecord(DeviceRecordRequest)

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
    case .setResponderLinkData: .setResponderLinkData
    case .setApplicationRetries: .setApplicationRetries
    case .setRadio: .setRadio
    case .readRadioStatus: .readRadioStatus
    case .readDiagnostics: .readDiagnostics
    case .manageDeviceRecord: .manageDeviceRecord
    }

  }

  /// The bytes that follow the command number.
  public var parameters: [UInt8] {

    switch self {
    case let .sendAllLinkCommand(group, command):
      [group.rawValue] + command.bytes
    case let .sendStandardMessage(message):
      message.bytes
    case let .sendExtendedMessage(message):
      message.bytes
    case let .sendX10(code):
      code.bytes
    case let .startAllLinking(mode, group):
      [mode.rawValue, group.rawValue]
    case let .setHostDeviceCategory(category, subcategory, firmwareVersion):
      [category.rawValue, subcategory.rawValue, firmwareVersion?.rawValue ?? 0xFF]
    case let .setAcknowledgementByte(command2), let .setNegativeAcknowledgementByte(command2):
      [command2]
    case let .setApplicationRetries(retries), let .readDiagnostics(retries):
      [retries]
    case let .setRadio(setting):
      [setting.rawValue]
    case let .setResponderLinkData(data1, data2, data3):
      [data1, data2, data3]
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
    case let .manageDeviceRecord(request):
      request.bytes
    case .getModemInfo, .cancelAllLinking, .resetModem, .getFirstAllLinkRecord,
      .getNextAllLinkRecord, .getAllLinkRecordForSender, .ledOn, .ledOff, .rfSleep,
      .getModemConfiguration, .cancelCleanup, .beep, .readRadioStatus:
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
