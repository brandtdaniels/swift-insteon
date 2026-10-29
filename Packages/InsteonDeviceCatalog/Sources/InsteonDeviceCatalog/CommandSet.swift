import InsteonProtocol

/// The settings and messages a family of products shares, as the catalog describes them, in
/// Insteon's own message types: operating flags read with Get Operating Flags and set with Set
/// Operating Flags, values read and written with extended Get and Set, other standard and
/// extended direct commands, and the direct messages the products send on their own.
///
/// A profile names the command set each of its identities uses, so an app reads and changes a
/// device's settings from the catalog rather than from code written for the product:
///
/// ```swift
/// guard let commands = catalog.commandSet(category: category, subcategory: subcategory, firmwareVersion: version),
///       let beep = commands.operatingFlag(named: "keyBeep"),
///       let turnOff = beep.command(setting: false) else {
///   return
/// }
///
/// let reply = try await modem.request(StandardMessage(to: keypad, command: beep.readCommand))
/// print(beep.isSet(in: reply) ?? false)
/// try await modem.request(StandardMessage(to: keypad, command: turnOff))
/// ```
///
/// An i2CS device expects Set Operating Flags and extended Set as extended messages with a
/// checksum in D14.
///
/// A thermostat's commands and reports work the same way:
///
/// ```swift
/// guard let setHeat = commands.standardCommand(named: "setHeatSetpoint") else {
///   return
/// }
///
/// try await modem.request(StandardMessage(to: thermostat, command: try setHeat.command(.number(68))))
///
/// // Then, among the messages the modem receives:
/// if let (report, value) = commands.directMessage(in: message) {
///   print(report.name, value)   // temperatureReport number(70.5)
/// }
/// ```
public struct CommandSet: Hashable, Sendable, Identifiable {

  /// The command set's identifier, which profiles name.
  public var id: CommandSetID

  /// What people call the command set, such as the product family it comes from.
  public var name: String

  /// Which products use the command set, and what sets it apart. The catalog's JSON calls it
  /// `description`.
  public var summary: String

  /// Bits of a Get Operating Flags reply, and the commands that change them.
  public var operatingFlags: [OperatingFlag]

  /// Get Operating Flags queries whose whole reply is a value.
  public var readings: [OperatingReading]

  /// Set Operating Flags commands whose effect no documented bit shows.
  public var flagCommands: [OperatingFlagCommand]

  /// The values read and written with extended Get and Set, or `nil` if the catalog doesn't
  /// describe them.
  public var extendedSettings: ExtendedSettings?

  /// Standard direct commands beyond the operating flags.
  public var standardCommands: [DeviceStandardCommand]

  /// Extended direct commands beyond extended Get and Set with cmd2 `0x00`.
  public var extendedCommands: [DeviceExtendedCommand]

  /// Standard direct messages the products send on their own.
  public var directMessages: [DeviceDirectMessage]

  /// The flag, value or bit that's true when the device displays Celsius, for values in
  /// ``FieldUnit/displayDegrees``, or `nil` if the command set doesn't say how to tell.
  public var celsiusIndicator: SettingName?

  /// What the products' ALL-Link groups are, which profiles' groups name in
  /// ``DeviceProfile/Group/type``.
  public var groupTypes: [GroupType]

  /// Names for the values of settings whose raw values mean something else, such as ramp
  /// rates, which ``LinkDataByte/table`` names.
  public var valueTables: [ValueTable]

  /// Where Insteon's documents disagree, and which one the command set follows.
  public var notes: [String]

  /// The documents the command set comes from.
  public var sources: [String]

  /// Creates a command set.
  ///
  /// - Parameters:
  ///   - id: The command set's identifier.
  ///   - name: What people call the command set.
  ///   - summary: Which products use the command set.
  ///   - operatingFlags: Bits of a Get Operating Flags reply.
  ///   - readings: Get Operating Flags queries whose whole reply is a value.
  ///   - flagCommands: Set Operating Flags commands with no documented bit.
  ///   - extendedSettings: The values read and written with extended Get and Set.
  ///   - standardCommands: Standard direct commands beyond the operating flags.
  ///   - extendedCommands: Extended direct commands beyond extended Get and Set.
  ///   - directMessages: Standard direct messages the products send on their own.
  ///   - celsiusIndicator: The flag, value or bit that's true when the device displays Celsius.
  ///   - groupTypes: What the products' ALL-Link groups are.
  ///   - valueTables: Names for the values of settings.
  ///   - notes: Where Insteon's documents disagree.
  ///   - sources: The documents the command set comes from.
  public init(
    id: CommandSetID,
    name: String,
    summary: String,
    operatingFlags: [OperatingFlag] = [],
    readings: [OperatingReading] = [],
    flagCommands: [OperatingFlagCommand] = [],
    extendedSettings: ExtendedSettings? = nil,
    standardCommands: [DeviceStandardCommand] = [],
    extendedCommands: [DeviceExtendedCommand] = [],
    directMessages: [DeviceDirectMessage] = [],
    celsiusIndicator: SettingName? = nil,
    groupTypes: [GroupType] = [],
    valueTables: [ValueTable] = [],
    notes: [String] = [],
    sources: [String] = []
  ) {

    self.id = id
    self.name = name
    self.summary = summary
    self.operatingFlags = operatingFlags
    self.readings = readings
    self.flagCommands = flagCommands
    self.extendedSettings = extendedSettings
    self.standardCommands = standardCommands
    self.extendedCommands = extendedCommands
    self.directMessages = directMessages
    self.celsiusIndicator = celsiusIndicator
    self.groupTypes = groupTypes
    self.valueTables = valueTables
    self.notes = notes
    self.sources = sources

  }

  /// The operating flag with a name.
  ///
  /// - Parameter name: The flag's name, such as `"keyBeep"`.
  /// - Returns: The flag, or `nil` if the command set has none by that name.
  public func operatingFlag(named name: SettingName) -> OperatingFlag? {

    operatingFlags.first { $0.name == name }

  }

  /// The standard command with a name.
  ///
  /// - Parameter name: The command's name, such as `"setHeatSetpoint"`.
  /// - Returns: The command, or `nil` if the command set has none by that name.
  public func standardCommand(named name: SettingName) -> DeviceStandardCommand? {

    standardCommands.first { $0.name == name }

  }

  /// The extended command with a name.
  ///
  /// - Parameter name: The command's name, such as `"readStatus"`.
  /// - Returns: The command, or `nil` if the command set has none by that name.
  public func extendedCommand(named name: SettingName) -> DeviceExtendedCommand? {

    extendedCommands.first { $0.name == name }

  }

  /// The group type with a name.
  ///
  /// - Parameter name: The group type's name, such as a profile group's
  ///   ``DeviceProfile/Group/type``.
  /// - Returns: The group type, or `nil` if the command set has none by that name.
  public func groupType(named name: SettingName) -> GroupType? {

    groupTypes.first { $0.name == name }

  }

  /// The value table with a name.
  ///
  /// - Parameter name: The table's name, such as `"rampRate"`.
  /// - Returns: The table, or `nil` if the command set has none by that name.
  public func valueTable(named name: SettingName) -> ValueTable? {

    valueTables.first { $0.name == name }

  }

  /// Reads a message the device sent on its own.
  ///
  /// - Parameter message: A message the modem received.
  /// - Returns: The direct message it is and the value it carries, or `nil` if it's none of
  ///   the command set's direct messages.
  public func directMessage(in message: ReceivedMessage) -> (message: DeviceDirectMessage, value: FieldValue)? {

    for directMessage in directMessages {

      if let value = directMessage.value(in: message) {

        return (directMessage, value)

      }

    }

    return nil

  }

}

/// A command set's identifier, such as `"keypadLinc"`.
public struct CommandSetID: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {

  /// The identifier.
  public let rawValue: String

  /// Creates an identifier.
  ///
  /// - Parameter rawValue: The identifier.
  public init(rawValue: String) {

    self.rawValue = rawValue

  }

  /// Creates an identifier from a string literal.
  ///
  /// - Parameter value: The identifier.
  public init(stringLiteral value: String) {

    self.init(rawValue: value)

  }

  /// The identifier.
  public var description: String { rawValue }

}

/// The name of a flag, reading, value, group type or value table in a command set, such as
/// `"rampRate"`.
public struct SettingName: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {

  /// The name.
  public let rawValue: String

  /// Creates a name.
  ///
  /// - Parameter rawValue: The name.
  public init(rawValue: String) {

    self.rawValue = rawValue

  }

  /// Creates a name from a string literal.
  ///
  /// - Parameter value: The name.
  public init(stringLiteral value: String) {

    self.init(rawValue: value)

  }

  /// The name.
  public var description: String { rawValue }

}

/// A bit of a Get Operating Flags reply, and the Set Operating Flags commands that change it.
public struct OperatingFlag: Hashable, Sendable {

  /// The flag's name, which says what the bit means when it's 1.
  public var name: SettingName

  /// What the flag means when its bit is 1.
  public var summary: String

  /// How sure the catalog is of the flag.
  public var verification: Verification

  /// The Get Operating Flags request whose reply holds the bit.
  public var query: OperatingFlagsRequest

  /// The bit's mask in the reply's cmd2.
  public var bit: UInt8

  /// The Set Operating Flags cmd2 that sets the bit to 1, if there's one.
  public var on: UInt8?

  /// The Set Operating Flags cmd2 that sets the bit to 0, if there's one.
  public var off: UInt8?

  /// The operating flag that, while set, has the Set Operating Flags commands sent as extended
  /// messages, with ``DeviceStandardCommand/protectedUserData(for:)``.
  public var extendedWhen: SettingName?

  /// What a settings page calls the flag, such as `"Beep on button press"`, if the command set
  /// says.
  public var label: String?

  /// The heading a settings page shows the flag under, if the command set says.
  public var section: SettingSection?

  /// Whether a settings page keeps the flag out of sight unless asked.
  public var isAdvanced: Bool

  /// Whether the bit is 1 as the device leaves the factory, if a document gives it. The
  /// catalog's JSON calls it `default`.
  public var defaultValue: Bool?

  /// The standard command, in the command set's ``CommandSet/standardCommands``, that sets the
  /// bit, for a flag Set Operating Flags doesn't set.
  public var onCommand: SettingName?

  /// The standard command, in the command set's ``CommandSet/standardCommands``, that clears
  /// the bit.
  public var offCommand: SettingName?

  /// Creates an operating flag.
  ///
  /// - Parameters:
  ///   - name: The flag's name.
  ///   - summary: What the flag means when its bit is 1.
  ///   - query: The request whose reply holds the bit.
  ///   - bit: The bit's mask in the reply's cmd2.
  ///   - on: The Set Operating Flags cmd2 that sets the bit to 1.
  ///   - off: The Set Operating Flags cmd2 that sets the bit to 0.
  ///   - extendedWhen: The operating flag that has the Set Operating Flags commands sent as
  ///     extended messages.
  ///   - verification: How sure the catalog is of the flag. Defaults to ``Verification/documented``.
  ///   - label: What a settings page calls the flag. Defaults to `nil`.
  ///   - section: The heading a settings page shows the flag under. Defaults to `nil`.
  ///   - isAdvanced: Whether a settings page keeps the flag out of sight unless asked.
  ///     Defaults to `false`.
  ///   - defaultValue: Whether the bit is 1 as the device leaves the factory. Defaults to `nil`.
  ///   - onCommand: The standard command that sets the bit. Defaults to `nil`.
  ///   - offCommand: The standard command that clears the bit. Defaults to `nil`.
  public init(
    name: SettingName,
    summary: String,
    query: OperatingFlagsRequest,
    bit: UInt8,
    on: UInt8? = nil,
    off: UInt8? = nil,
    extendedWhen: SettingName? = nil,
    verification: Verification = .documented,
    label: String? = nil,
    section: SettingSection? = nil,
    isAdvanced: Bool = false,
    defaultValue: Bool? = nil,
    onCommand: SettingName? = nil,
    offCommand: SettingName? = nil
  ) {

    self.name = name
    self.summary = summary
    self.verification = verification
    self.query = query
    self.bit = bit
    self.on = on
    self.off = off
    self.extendedWhen = extendedWhen
    self.label = label
    self.section = section
    self.isAdvanced = isAdvanced
    self.defaultValue = defaultValue
    self.onCommand = onCommand
    self.offCommand = offCommand

  }

  /// The command that reads the flag: Get Operating Flags with the flag's query.
  public var readCommand: StandardDirectCommand {

    .getOperatingFlags(query)

  }

  /// Whether the bit is set in the acknowledgment of ``OperatingFlag/readCommand``.
  ///
  /// - Parameter acknowledgment: The device's acknowledgment.
  /// - Returns: Whether the bit is 1, or `nil` if the message isn't an acknowledgment of
  ///   Get Operating Flags.
  public func isSet(in acknowledgment: ReceivedMessage) -> Bool? {

    guard acknowledgment.flags.messageType == .directAcknowledgment, acknowledgment.command.command1 == 0x1F else {

      return nil

    }

    return acknowledgment.command.command2 & bit != 0

  }

  /// The command that sets the bit.
  ///
  /// - Parameter value: The value to set the bit to.
  /// - Returns: Set Operating Flags with the cmd2 for the value, or `nil` if the command set
  ///   doesn't give one.
  public func command(setting value: Bool) -> StandardDirectCommand? {

    (value ? on : off).map { .setOperatingFlags(flag: $0) }

  }

}

/// A Get Operating Flags request whose whole reply is a value, such as the ALL-Link database's
/// delta.
public struct OperatingReading: Hashable, Sendable {

  /// The reading's name.
  public var name: SettingName

  /// What the reading is.
  public var summary: String

  /// How sure the catalog is of the reading.
  public var verification: Verification

  /// The Get Operating Flags request.
  public var query: OperatingFlagsRequest

  /// What a settings page calls the reading, such as `"CRC errors"`, if the command set says.
  public var label: String?

  /// The heading a settings page shows the reading under, if the command set says.
  public var section: SettingSection?

  /// Whether a settings page keeps the reading out of sight unless asked.
  public var isAdvanced: Bool

  /// Creates a reading.
  ///
  /// - Parameters:
  ///   - name: The reading's name.
  ///   - summary: What the reading is.
  ///   - query: The Get Operating Flags request.
  ///   - verification: How sure the catalog is of the reading. Defaults to ``Verification/documented``.
  ///   - label: What a settings page calls the reading. Defaults to `nil`.
  ///   - section: The heading a settings page shows the reading under. Defaults to `nil`.
  ///   - isAdvanced: Whether a settings page keeps the reading out of sight unless asked.
  ///     Defaults to `false`.
  public init(
    name: SettingName,
    summary: String,
    query: OperatingFlagsRequest,
    verification: Verification = .documented,
    label: String? = nil,
    section: SettingSection? = nil,
    isAdvanced: Bool = false
  ) {

    self.name = name
    self.summary = summary
    self.verification = verification
    self.query = query
    self.label = label
    self.section = section
    self.isAdvanced = isAdvanced

  }

}

/// A Set Operating Flags command whose effect no documented bit shows.
public struct OperatingFlagCommand: Hashable, Sendable {

  /// The command's name.
  public var name: SettingName

  /// What the command does.
  public var summary: String

  /// How sure the catalog is of the command.
  public var verification: Verification

  /// The command: Set Operating Flags with its cmd2.
  public var command: StandardDirectCommand

  /// The operating flag that, while set, has the command sent as an extended message, with
  /// ``DeviceStandardCommand/protectedUserData(for:)``.
  public var extendedWhen: SettingName?

  /// Creates a flag command.
  ///
  /// - Parameters:
  ///   - name: The command's name.
  ///   - summary: What the command does.
  ///   - command2: The Set Operating Flags cmd2.
  ///   - extendedWhen: The operating flag that has the command sent as an extended message.
  ///   - verification: How sure the catalog is of the command. Defaults to ``Verification/documented``.
  public init(name: SettingName, summary: String, command2: UInt8, extendedWhen: SettingName? = nil, verification: Verification = .documented) {

    self.name = name
    self.summary = summary
    self.verification = verification
    self.command = .setOperatingFlags(flag: command2)
    self.extendedWhen = extendedWhen

  }

}
