import InsteonProtocol

/// The values a command set reads with an extended Get and writes with an extended Set (cmd1
/// `0x2E`, cmd2 `0x00`).
///
/// A Get has `0x00` in D2 and the button or group in D1; the device acknowledges, then replies
/// with the same command, `0x01` in D2 and the values in D3 through D14. A Set has a write's
/// selector in D2 and its values from D3.
///
/// ```swift
/// guard let settings = commands.extendedSettings, let rampRate = settings.write(named: "rampRate") else {
///   return
/// }
///
/// try await modem.request(ExtendedMessage(to: dimmer, command: ExtendedDirectCommand.getSet(), userData: settings.getUserData(button: 1)))
///
/// // Then, among the messages the modem receives:
/// if let values = settings.values(in: message) {
///   print(values["rampRate"] ?? 0)
/// }
///
/// let userData = try rampRate.userData(button: 1, values: ["rampRate": 0x1C])
/// try await modem.request(ExtendedMessage(to: dimmer, command: ExtendedDirectCommand.getSet(), userData: userData))
/// ```
public struct ExtendedSettings: Hashable, Sendable {

  /// Whether D1 of a Get chooses the button or group whose values the reply holds.
  public var isPerButton: Bool

  /// The values in a Get's reply.
  public var values: [SettingValue]

  /// The Set selectors.
  public var writes: [SettingWrite]

  /// Creates extended settings.
  ///
  /// - Parameters:
  ///   - isPerButton: Whether D1 of a Get chooses a button or group.
  ///   - values: The values in a Get's reply.
  ///   - writes: The Set selectors.
  public init(isPerButton: Bool, values: [SettingValue] = [], writes: [SettingWrite] = []) {

    self.isPerButton = isPerButton
    self.values = values
    self.writes = writes

  }

  /// The user data of a Get: the button or group in D1, `0x00` in D2.
  ///
  /// - Parameter button: The button or group, or `0x01` for the whole device.
  /// - Returns: The user data.
  public func getUserData(button: UInt8 = 0x01) -> UserData {

    var userData = UserData()
    userData[1] = button

    return userData

  }

  /// Reads the values from a Get's reply.
  ///
  /// - Parameter message: A message the modem received.
  /// - Returns: Each value by name, or `nil` unless the message is an extended direct reply
  ///   to a Get: cmd1 `0x2E`, cmd2 `0x00` and `0x01` in D2. Read D1 for the button or group.
  public func values(in message: ReceivedMessage) -> [SettingName: UInt8]? {

    guard
      message.flags.messageType == .direct,
      message.command == Command(command1: 0x2E, command2: 0x00),
      let userData = message.userData,
      userData[2] == 0x01
    else {

      return nil

    }

    return Dictionary(values.map { ($0.name, userData[$0.position]) }) { first, _ in first }

  }

  /// The write with a name.
  ///
  /// - Parameter name: The write's name, such as `"rampRate"`.
  /// - Returns: The write, or `nil` if there's none by that name.
  public func write(named name: SettingName) -> SettingWrite? {

    writes.first { $0.name == name }

  }

}

/// A value in a Get's reply.
public struct SettingValue: Hashable, Sendable {

  /// How to read a value's byte.
  public enum Kind: String, Hashable, Sendable {

    /// A number.
    case number

    /// A mask with one bit per button, button 1 in bit 0.
    case buttons

  }

  /// The value's name.
  public var name: SettingName

  /// What the value is.
  public var summary: String

  /// The user data byte that holds the value, from 3 through 14 for D3 through D14.
  public var position: Int

  /// How to read the byte.
  public var kind: Kind

  /// The values the byte can take, if the command set gives them.
  public var range: ClosedRange<UInt8>?

  /// Creates a value.
  ///
  /// - Parameters:
  ///   - name: The value's name.
  ///   - summary: What the value is.
  ///   - position: The user data byte that holds the value, from 3 through 14.
  ///   - kind: How to read the byte. Defaults to ``SettingValue/Kind/number``.
  ///   - range: The values the byte can take.
  public init(name: SettingName, summary: String, position: Int, kind: Kind = .number, range: ClosedRange<UInt8>? = nil) {

    precondition((3...14).contains(position), "A setting's value is in D3 through D14.")

    self.name = name
    self.summary = summary
    self.position = position
    self.kind = kind
    self.range = range

  }

}

/// An extended Set: a selector in D2, and the values it writes from D3.
public struct SettingWrite: Hashable, Sendable {

  /// One byte a write fills.
  public struct Byte: Hashable, Sendable {

    /// The user data byte, from 3 through 14 for D3 through D14.
    public var position: Int

    /// The name of the value that goes in it.
    public var value: SettingName

    /// Creates a byte of a write.
    ///
    /// - Parameters:
    ///   - position: The user data byte, from 3 through 14.
    ///   - value: The name of the value that goes in it.
    public init(position: Int, value: SettingName) {

      precondition((3...14).contains(position), "A setting's value is in D3 through D14.")

      self.position = position
      self.value = value

    }

  }

  /// The write's name.
  public var name: SettingName

  /// What the write sets.
  public var summary: String

  /// The selector, which goes in D2.
  public var selector: UInt8

  /// Whether D1 chooses the button or group the value is for. Otherwise D1 is `0x01`.
  public var isPerButton: Bool

  /// The bytes the write fills from D3.
  public var bytes: [Byte]

  /// Creates a write.
  ///
  /// - Parameters:
  ///   - name: The write's name.
  ///   - summary: What the write sets.
  ///   - selector: The selector, which goes in D2.
  ///   - isPerButton: Whether D1 chooses the button or group.
  ///   - bytes: The bytes the write fills from D3.
  public init(name: SettingName, summary: String, selector: UInt8, isPerButton: Bool, bytes: [Byte]) {

    self.name = name
    self.summary = summary
    self.selector = selector
    self.isPerButton = isPerButton
    self.bytes = bytes

  }

  /// The user data of the Set.
  ///
  /// - Parameters:
  ///   - button: The button or group, for a write that's per button. Ignored otherwise, when
  ///     D1 is `0x01`.
  ///   - values: The value for each of the write's bytes, by name.
  /// - Returns: The button in D1, the selector in D2 and the values from D3.
  /// - Throws: ``SettingWriteError/missingValue(_:)`` if a byte's value isn't given.
  public func userData(button: UInt8 = 0x01, values: [SettingName: UInt8]) throws(SettingWriteError) -> UserData {

    var userData = UserData()
    userData[1] = isPerButton ? button : 0x01
    userData[2] = selector

    for byte in bytes {

      guard let value = values[byte.value] else {

        throw .missingValue(byte.value)

      }

      userData[byte.position] = value

    }

    return userData

  }

}

/// Why an extended Set's user data couldn't be made.
public enum SettingWriteError: Error, Hashable, Sendable {

  /// The value for one of the write's bytes wasn't given.
  case missingValue(SettingName)

}
