import InsteonProtocol

/// A payload byte with a fixed value.
public struct FixedPayloadByte: Hashable, Sendable {

  /// The byte's position in the payload, counted from 1 for the byte after the command number.
  public var position: Int

  /// The byte's value.
  public var value: UInt8

  /// Creates a fixed byte.
  ///
  /// - Parameters:
  ///   - position: The byte's position, from 1 through 14.
  ///   - value: The byte's value.
  public init(position: Int, value: UInt8) {

    precondition((1...UserData.count).contains(position), "Payload positions are 1 through \(UserData.count).")

    self.position = position
    self.value = value

  }

}

/// A serial command a modem's command set describes: the command number a host sends after Start
/// of Text (`0x02`), the payload the number fixes the length of, and the echo that answers it.
///
/// Commands that differ only by a control byte, such as the link code of Start ALL-Linking, are
/// separate entries told apart by their fixed bytes, because their effects differ.
///
/// ```swift
/// guard let cancel = commands.serialCommand(named: "cancelAllLinking") else {
///   return
/// }
///
/// print(cancel.number, cancel.effect?.strictness == .readOnly)
/// ```
public struct DeviceSerialCommand: Hashable, Sendable {

  /// The command's name.
  public var name: SettingName

  /// What the command does.
  public var summary: String

  /// How sure the catalog is of the command.
  public var verification: Verification

  /// The command number, the byte after `0x02`.
  public var number: UInt8

  /// The command's fixed payload bytes. A frame matches the command only when its payload holds
  /// these values.
  public var fixedBytes: [FixedPayloadByte]

  /// The values the caller gives, and the payload bytes each goes in.
  public var parameters: [MessageField]

  /// The values the modem returns after the command number and before the ACK or NAK, numbered
  /// from 1 as the payload is. Empty when the echo only repeats the payload.
  public var reply: [MessageField]

  /// Whether an app may send the command, or `nil` if the catalog gives no guard.
  /// ``CommandGuard/never`` marks one an app never sends.
  public var sendGuard: CommandGuard?

  /// What the command does to the modem, or `nil` if the catalog doesn't say, which reads as
  /// ``CommandEffect/destructive``.
  public var effect: CommandEffect?

  /// Whether sending the command twice leaves the modem as sending it once does, or `nil` if
  /// the catalog doesn't say, which reads as `false`. The catalog's JSON calls it `idempotent`.
  public var isIdempotent: Bool?

  /// Creates a serial command.
  ///
  /// - Parameters:
  ///   - name: The command's name.
  ///   - summary: What the command does.
  ///   - number: The command number.
  ///   - fixedBytes: The command's fixed payload bytes. Defaults to none.
  ///   - parameters: The values the caller gives. Defaults to none.
  ///   - reply: The values the modem returns. Defaults to none.
  ///   - verification: How sure the catalog is of the command. Defaults to ``Verification/documented``.
  ///   - sendGuard: Whether an app may send the command. Defaults to `nil`.
  ///   - effect: What the command does to the modem. Defaults to `nil`.
  ///   - isIdempotent: Whether sending the command twice leaves the modem as sending it once
  ///     does. Defaults to `nil`.
  public init(
    name: SettingName,
    summary: String,
    number: UInt8,
    fixedBytes: [FixedPayloadByte] = [],
    parameters: [MessageField] = [],
    reply: [MessageField] = [],
    verification: Verification = .documented,
    sendGuard: CommandGuard? = nil,
    effect: CommandEffect? = nil,
    isIdempotent: Bool? = nil
  ) {

    self.name = name
    self.summary = summary
    self.verification = verification
    self.number = number
    self.fixedBytes = fixedBytes
    self.parameters = parameters
    self.reply = reply
    self.sendGuard = sendGuard
    self.effect = effect
    self.isIdempotent = isIdempotent

  }

}
