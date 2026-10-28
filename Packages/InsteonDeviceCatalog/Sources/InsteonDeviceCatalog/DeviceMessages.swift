import InsteonProtocol

/// A standard direct command a command set describes: cmd1, and a fixed cmd2 or a value the
/// caller puts in cmd2.
///
/// ```swift
/// guard let setHeat = commands.standardCommand(named: "setHeatSetpoint") else {
///   return
/// }
///
/// let command = try setHeat.command(.number(68))
/// try await modem.request(StandardMessage(to: thermostat, command: command))
/// ```
public struct DeviceStandardCommand: Hashable, Sendable {

  /// What goes in a standard command's cmd2.
  public enum Command2: Hashable, Sendable {

    /// A fixed byte.
    case fixed(UInt8)

    /// A value the caller gives.
    case parameter(MessageField)

  }

  /// The command's name.
  public var name: SettingName

  /// What the command does.
  public var summary: String

  /// The command's cmd1.
  public var command1: UInt8

  /// What goes in cmd2.
  public var command2: Command2

  /// The value the acknowledgement carries in cmd2, if any.
  public var reply: MessageField?

  /// A value one more standard direct message with the same cmd1 may carry after the
  /// acknowledgement, when the device has it, such as a second setpoint.
  public var followUp: MessageField?

  /// The operating flag that, while set, has the command sent as an extended message, with
  /// ``DeviceStandardCommand/protectedUserData(for:)``.
  public var extendedWhen: SettingName?

  /// Creates a standard command.
  ///
  /// - Parameters:
  ///   - name: The command's name.
  ///   - summary: What the command does.
  ///   - command1: The command's cmd1.
  ///   - command2: What goes in cmd2.
  ///   - reply: The value the acknowledgement carries in cmd2.
  ///   - followUp: A value one more message with the same cmd1 may carry.
  ///   - extendedWhen: The operating flag that has the command sent as an extended message.
  public init(
    name: SettingName,
    summary: String,
    command1: UInt8,
    command2: Command2,
    reply: MessageField? = nil,
    followUp: MessageField? = nil,
    extendedWhen: SettingName? = nil
  ) {

    self.name = name
    self.summary = summary
    self.command1 = command1
    self.command2 = command2
    self.reply = reply
    self.followUp = followUp
    self.extendedWhen = extendedWhen

  }

  /// The command's cmd1 and cmd2.
  ///
  /// - Parameter value: The value for cmd2, for a command that takes one. Ignored otherwise.
  /// - Returns: The command.
  /// - Throws: ``FieldError/missingValue(_:)`` if the command takes a value and none is given,
  ///   or another ``FieldError`` if the value doesn't fit.
  public func command(_ value: FieldValue? = nil) throws(FieldError) -> Command {

    switch command2 {
    case let .fixed(byte):
      return Command(command1: command1, command2: byte)
    case let .parameter(field):
      guard let value else {

        throw .missingValue(field.name)

      }

      return Command(command1: command1, command2: try field.encoded(value, over: [0x00])[0])
    }

  }

  /// Reads the value the acknowledgement carries.
  ///
  /// Acknowledgements carry only cmd1, so read only the acknowledgement of this command: the
  /// one that answers its request. Another command with the same cmd1 is acknowledged the same
  /// way.
  ///
  /// - Parameter message: A message the modem received.
  /// - Returns: The value, or `nil` unless the command has a reply and the message is an
  ///   acknowledgement with the command's cmd1.
  public func reply(in message: ReceivedMessage) -> FieldValue? {

    guard let reply, message.flags.messageType == .directAcknowledgement, message.command.command1 == command1 else {

      return nil

    }

    return reply.value(command2: message.command.command2, userData: nil)

  }

  /// Reads the value a message after the acknowledgement carries.
  ///
  /// - Parameter message: A message the modem received.
  /// - Returns: The value, or `nil` unless the command has a follow-up and the message is a
  ///   standard direct message with the command's cmd1.
  public func followUp(in message: ReceivedMessage) -> FieldValue? {

    guard let followUp, message.flags.messageType == .direct, !message.flags.isExtended, message.command.command1 == command1 else {

      return nil

    }

    return followUp.value(command2: message.command.command2, userData: nil)

  }

  /// The command as an extended message, for a device whose
  /// ``DeviceStandardCommand/extendedWhen`` flag is set.
  ///
  /// - Parameters:
  ///   - device: The device to send it to.
  ///   - value: The value for cmd2, for a command that takes one. Ignored otherwise.
  /// - Returns: The message, with ``DeviceStandardCommand/protectedUserData(for:)`` and no
  ///   integrity bytes.
  /// - Throws: ``FieldError`` if the command takes a value and it's missing or doesn't fit.
  public func extendedMessage(to device: InsteonAddress, value: FieldValue? = nil) throws(FieldError) -> ExtendedMessage {

    let standard = try command(value)

    return ExtendedMessage(to: device, command: standard, userData: Self.protectedUserData(for: standard), integrity: UnprotectedIntegrity())

  }

  /// The user data that sends a command as an extended message, for a device whose
  /// ``DeviceStandardCommand/extendedWhen`` flag is set: cmd1 and cmd2 again in D1 and D2, and
  /// `0x00` after, with no integrity bytes.
  ///
  /// - Parameter command: The command.
  /// - Returns: The user data.
  public static func protectedUserData(for command: Command) -> UserData {

    var userData = UserData()
    userData[1] = command.command1
    userData[2] = command.command2

    return userData

  }

}

/// How an extended message's user data is protected.
public enum MessageIntegrity: String, Hashable, Sendable {

  /// Not at all: `UnprotectedIntegrity`.
  case unprotected = "none"

  /// A checksum in D14: `ChecksumIntegrity`.
  case checksum

  /// A CRC in D13 and D14: `CRCIntegrity`.
  case crc

  /// The scheme that seals user data this way.
  public var scheme: any UserDataIntegrity {

    switch self {
    case .unprotected: UnprotectedIntegrity()
    case .checksum: ChecksumIntegrity()
    case .crc: CRCIntegrity()
    }

  }

  /// Whether user data's integrity bytes match its contents.
  ///
  /// - Parameters:
  ///   - userData: The user data.
  ///   - command: The command it came with.
  /// - Returns: Whether sealing the user data leaves it unchanged.
  public func isIntact(_ userData: UserData, for command: Command) -> Bool {

    scheme.seal(userData, for: command) == userData

  }

}

/// A user data byte with a fixed value.
public struct FixedUserDataByte: Hashable, Sendable {

  /// The byte's position, from 1 through 14 for D1 through D14.
  public var position: Int

  /// The byte's value.
  public var value: UInt8

  /// Creates a fixed byte.
  ///
  /// - Parameters:
  ///   - position: The byte's position, from 1 through 14.
  ///   - value: The byte's value.
  public init(position: Int, value: UInt8) {

    precondition((1...UserData.count).contains(position), "User data positions are 1 through \(UserData.count).")

    self.position = position
    self.value = value

  }

}

/// An extended direct command a command set describes, and the extended reply that answers it.
///
/// ```swift
/// guard let readStatus = commands.extendedCommand(named: "readStatus") else {
///   return
/// }
///
/// try await modem.request(try readStatus.message(to: thermostat))
///
/// // Then, among the messages the modem receives:
/// if let values = readStatus.reply?.values(in: message) {
///   print(values["temperature"] ?? .number(0))
/// }
/// ```
public struct DeviceExtendedCommand: Hashable, Sendable {

  /// The command's name.
  public var name: SettingName

  /// What the command does.
  public var summary: String

  /// The command's cmd1 and cmd2.
  public var command: Command

  /// Whether D1 chooses a button or group.
  public var isPerButton: Bool

  /// The command's fixed user data bytes. The rest are `0x00`, apart from its parameters and
  /// integrity bytes.
  public var fixedBytes: [FixedUserDataByte]

  /// The values the caller gives.
  public var parameters: [MessageField]

  /// How the command's user data is protected.
  public var integrity: MessageIntegrity

  /// The extended reply that answers the command, if any.
  public var reply: DeviceExtendedReply?

  /// Creates an extended command.
  ///
  /// - Parameters:
  ///   - name: The command's name.
  ///   - summary: What the command does.
  ///   - command: The command's cmd1 and cmd2.
  ///   - isPerButton: Whether D1 chooses a button or group.
  ///   - fixedBytes: The command's fixed user data bytes.
  ///   - parameters: The values the caller gives.
  ///   - integrity: How the command's user data is protected.
  ///   - reply: The extended reply that answers the command.
  public init(
    name: SettingName,
    summary: String,
    command: Command,
    isPerButton: Bool = false,
    fixedBytes: [FixedUserDataByte] = [],
    parameters: [MessageField] = [],
    integrity: MessageIntegrity = .unprotected,
    reply: DeviceExtendedReply? = nil
  ) {

    self.name = name
    self.summary = summary
    self.command = command
    self.isPerButton = isPerButton
    self.fixedBytes = fixedBytes
    self.parameters = parameters
    self.integrity = integrity
    self.reply = reply

  }

  /// The command's user data, before its integrity bytes are filled in.
  ///
  /// - Parameters:
  ///   - button: The button or group, for a command that's per button. Ignored otherwise.
  ///   - values: The value of each parameter, by name.
  /// - Returns: The user data.
  /// - Throws: ``FieldError/missingValue(_:)`` if a parameter's value isn't given, or another
  ///   ``FieldError`` if a value doesn't fit.
  public func userData(button: UInt8 = 0x01, values: [SettingName: FieldValue] = [:]) throws(FieldError) -> UserData {

    var userData = UserData()

    for byte in fixedBytes {

      userData[byte.position] = byte.value

    }

    if isPerButton {

      userData[1] = button

    }

    for parameter in parameters {

      guard let value = values[parameter.name] else {

        throw .missingValue(parameter.name)

      }

      let positions = parameter.positions
      let bytes = try parameter.encoded(value, over: positions.map { userData[$0] })

      for (position, byte) in zip(positions, bytes) {

        userData[position] = byte

      }

    }

    return userData

  }

  /// The command as an extended direct message, with its integrity bytes filled in.
  ///
  /// - Parameters:
  ///   - device: The device to send it to.
  ///   - button: The button or group, for a command that's per button. Ignored otherwise.
  ///   - values: The value of each parameter, by name.
  /// - Returns: The message.
  /// - Throws: ``FieldError`` if a parameter's value is missing or doesn't fit.
  public func message(to device: InsteonAddress, button: UInt8 = 0x01, values: [SettingName: FieldValue] = [:]) throws(FieldError) -> ExtendedMessage {

    ExtendedMessage(to: device, command: command, userData: try userData(button: button, values: values), integrity: integrity.scheme)

  }

}

/// The extended direct message that answers a ``DeviceExtendedCommand``.
public struct DeviceExtendedReply: Hashable, Sendable {

  /// The reply's cmd1 and cmd2.
  public var command: Command

  /// The bytes that tell the reply apart from others with the same command.
  public var match: [FixedUserDataByte]

  /// How the reply's user data is protected.
  public var integrity: MessageIntegrity

  /// The values the reply carries.
  public var values: [MessageField]

  /// Creates a reply.
  ///
  /// - Parameters:
  ///   - command: The reply's cmd1 and cmd2.
  ///   - match: The bytes that tell the reply apart.
  ///   - integrity: How the reply's user data is protected.
  ///   - values: The values the reply carries.
  public init(command: Command, match: [FixedUserDataByte] = [], integrity: MessageIntegrity = .unprotected, values: [MessageField]) {

    self.command = command
    self.match = match
    self.integrity = integrity
    self.values = values

  }

  /// Reads the values from the reply.
  ///
  /// - Parameter message: A message the modem received.
  /// - Returns: Each value by name, or `nil` unless the message is an extended direct message
  ///   with the reply's command and match bytes, and its integrity bytes are intact.
  public func values(in message: ReceivedMessage) -> [SettingName: FieldValue]? {

    guard
      message.flags.messageType == .direct,
      message.command == command,
      let userData = message.userData,
      match.allSatisfy({ userData[$0.position] == $0.value }),
      integrity.isIntact(userData, for: command)
    else {

      return nil

    }

    return Dictionary(values.compactMap { field in field.value(command2: message.command.command2, userData: userData).map { (field.name, $0) } }) { first, _ in first }

  }

}

/// A standard direct message a device sends on its own, such as a thermostat's report of a
/// new temperature.
public struct DeviceDirectMessage: Hashable, Sendable {

  /// The message's name.
  public var name: SettingName

  /// What the message reports.
  public var summary: String

  /// The message's cmd1.
  public var command1: UInt8

  /// The value it carries in cmd2.
  public var value: MessageField

  /// Creates a direct message.
  ///
  /// - Parameters:
  ///   - name: The message's name.
  ///   - summary: What the message reports.
  ///   - command1: The message's cmd1.
  ///   - value: The value it carries in cmd2.
  public init(name: SettingName, summary: String, command1: UInt8, value: MessageField) {

    self.name = name
    self.summary = summary
    self.command1 = command1
    self.value = value

  }

  /// Reads the value from a message.
  ///
  /// - Parameter message: A message the modem received.
  /// - Returns: The value, or `nil` unless the message is a standard direct message with the
  ///   message's cmd1.
  public func value(in message: ReceivedMessage) -> FieldValue? {

    guard message.flags.messageType == .direct, !message.flags.isExtended, message.command.command1 == command1 else {

      return nil

    }

    return value.value(command2: message.command.command2, userData: nil)

  }

}
