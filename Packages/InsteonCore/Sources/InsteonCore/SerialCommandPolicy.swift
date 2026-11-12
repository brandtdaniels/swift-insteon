import InsteonDeviceCatalog
import InsteonProtocol

/// Which serial commands a raw passthrough, such as `insteon modem send`, writes to the modem,
/// with or without being forced. ``ModemSession/write(rawCommand:forcing:collectingFor:clock:onWriting:)``
/// enforces it.
///
/// Three things decide, in this order. The byte floor and the command's framing refuse bytes
/// whatever the modem is: ``refusal(of:forcing:)`` says why. Then what the command does to the
/// modem decides, as ``decision(of:commands:forcing:)`` reads it from the modem's command set
/// and from what InsteonCore's own flows declare, through ``SendPolicy``.
///
/// ```swift
/// if let refusal = SerialCommandPolicy.refusal(of: bytes, forcing: false) {
///   print(refusal.canBeForced ? "Refused unless forced." : "Never written.")
/// }
///
/// switch SerialCommandPolicy.decision(of: bytes, commands: modemCommands, forcing: false) {
/// case .transmit: print("Written.")
/// case let .needsConsent(effect): print("Needs --force:", effect?.rawValue ?? "undescribed")
/// case let .refuse(refusal): print("Never written:", refusal)
/// }
/// ```
public enum SerialCommandPolicy {

  /// What `insteon modem send` grants a command: what a flow does without asking, link and
  /// actuation, and with `forcing` also configuration, destructive and a command no entry
  /// describes.
  ///
  /// - Parameter forcing: Whether the person passed `--force`.
  /// - Returns: The consent.
  public static func consent(forcing: Bool) -> SendConsent {

    forcing
      ? SendConsent(effects: [.configuration, .link, .actuation, .destructive], allowsUndescribed: true)
      : SendConsent(effects: [.link, .actuation])

  }

  /// Whether a serial command is written, needs the person's consent, or is never written.
  ///
  /// ``refusal(of:forcing:)`` refuses first: the byte floor, a command cut short, and without
  /// `forcing` a command that can't be framed or that writes to a device. A command the
  /// modem's command set marks as never sent is refused whatever is granted. Otherwise the
  /// command's effect decides. It is the strictest effect of the entries of the modem's command
  /// set whose number and fixed payload bytes the command matches, and the effect InsteonCore's
  /// own flows declare for the same bytes, whichever is stricter. A command neither describes
  /// is undescribed. ``consent(forcing:)`` is what is granted.
  ///
  /// - Parameters:
  ///   - bytes: The command's bytes, starting with `0x02`.
  ///   - commands: The modem's command set, or `nil` if the catalog gives the modem none or
  ///     doesn't know it.
  ///   - forcing: Whether the person passed `--force`.
  /// - Returns: The decision.
  public static func decision(of bytes: [UInt8], commands: CommandSet?, forcing: Bool) -> SendDecision {

    var refusal: SendRefusal? = refusal(of: bytes, forcing: forcing)

    if refusal == nil, bytes.count >= 2, CommandSetSafety.isSerialNeverSent(number: bytes[1], payload: Array(bytes.dropFirst(2)), in: commands) {

      refusal = .neverSentToModem

    }

    var effect: CommandEffect?

    if refusal == nil, bytes.count >= 2, case let .described(described, _) = CommandSetSafety.serialEffect(number: bytes[1], payload: Array(bytes.dropFirst(2)), in: commands) {

      effect = described

    }

    return SendPolicy.decision(effect: effect, declaredEffect: SerialFlowEffects.declaredEffect(of: bytes), refusal: refusal, consent: consent(forcing: forcing))

  }

  /// Whether bytes start the way every serial command does, with Start of Text (`0x02`).
  ///
  /// - Parameter bytes: The bytes.
  /// - Returns: `true` if the first byte is `0x02`.
  public static func isSerialCommand(_ bytes: [UInt8]) -> Bool {

    bytes.first == SerialCommand.startOfText

  }

  /// Why bytes aren't written to the modem, or `nil` if they are.
  ///
  /// Bytes are never written, forced or not, when ``neverWritten(_:)`` says why. Otherwise
  /// they're refused, unless `forcing` is `true`, when ``refusal(for:)`` says why.
  ///
  /// - Parameters:
  ///   - bytes: The command's bytes, starting with `0x02`.
  ///   - forcing: Whether to write a command that's refused only unless it's forced.
  /// - Returns: The refusal, or `nil`.
  public static func refusal(of bytes: [UInt8], forcing: Bool) -> SendRefusal? {

    if let refusal: SendRefusal = neverWritten(bytes) {

      return refusal

    }

    guard !forcing, let reason: String = refusal(for: bytes) else {

      return nil

    }

    return .serialCommand(reason)

  }

  /// Why bytes are never written to the modem, forced or not, or `nil` if they may be.
  ///
  /// Bytes that don't start with `0x02` aren't a serial command. Every Send Insteon Standard
  /// or Extended Message (`0x62`) and Send ALL-Link Command (`0x61`) the bytes hold, wherever
  /// it starts, is read for its cmd1 and cmd2, and one that carries a ``ProtectedCommand`` is
  /// refused, as is one cut short, which the next command's bytes could finish.
  ///
  /// - Parameter bytes: The bytes.
  /// - Returns: The refusal, or `nil`.
  public static func neverWritten(_ bytes: [UInt8]) -> SendRefusal? {

    guard isSerialCommand(bytes) else {

      return .notSerialCommand

    }

    for start in bytes.indices where bytes[start] == SerialCommand.startOfText && start + 1 < bytes.count {

      // A message is 02 62 ADDRESS(3) FLAGS CMD1 CMD2, and a group command 02 61 GROUP CMD1
      // CMD2; the command bytes are counted from 02.
      let commandOffset: Int

      switch bytes[start + 1] {
      case SerialCommandNumber.sendMessage.rawValue:
        commandOffset = 6
      case SerialCommandNumber.sendAllLinkCommand.rawValue:
        commandOffset = 3
      default:
        continue
      }

      guard start + commandOffset + 1 < bytes.count else {

        return .incompleteMessage

      }

      if let protected = ProtectedCommand(command1: bytes[start + commandOffset], command2: bytes[start + commandOffset + 1]) {

        return .protected(protected)

      }

    }

    return nil

  }

  /// Why a serial command is refused unless it's forced, or `nil` if it isn't.
  ///
  /// A command that doesn't start with `0x02` is always refused, so this isn't asked about it:
  /// ask ``isSerialCommand(_:)`` first, or ask ``refusal(of:forcing:)``, which also refuses
  /// what ``neverWritten(_:)`` does. One whose number the package doesn't know is refused,
  /// since the modem's answer can't be read. What a command does to the modem is not judged
  /// here: ``decision(of:commands:forcing:)`` reads it from the modem's command set.
  ///
  /// A command must also have the length its number calls for, counting `0x02`: Send Insteon
  /// Standard or Extended Message (`0x62`) has 8 bytes, or 22 when bit 4 of its flags says
  /// it's extended, and Beep (`0x77`) has 2 or 3.
  ///
  /// A message to a device that writes its ALL-Link database (Read/Write ALL-Link Database, `0x2F`), its
  /// operating flags (Set Operating Flags, `0x20`) or its settings (Extended Set/Get, `0x2E`
  /// with D2 other than `0x00`). A ``Device`` sends those, checked against its command set.
  ///
  /// - Parameter bytes: The command's bytes, starting with `0x02`.
  /// - Returns: The reason, as a sentence.
  public static func refusal(for bytes: [UInt8]) -> String? {

    guard bytes.count >= 2 else {

      return "A serial command needs its number after 0x02."

    }

    let number: UInt8 = bytes[1]

    guard let known: SerialCommandNumber = SerialCommandNumber(rawValue: number) else {

      return "\(hexByte(number)) isn't a serial command the package knows, so the modem's answer can't be read."

    }

    if let reason: String = lengthRefusal(for: bytes, number: known) {

      return reason

    }

    return contentRefusal(for: bytes, number: known)

  }

  /// Why a command doesn't have the length its number calls for, counting `0x02`.
  private static func lengthRefusal(for bytes: [UInt8], number: SerialCommandNumber) -> String? {

    let name: String = "Serial command " + hexByte(number.rawValue)
    let count: Int = bytes.count

    switch number {
    case .sendMessage:
      guard count >= 6 else {

        return "\(name) needs a device's address and message flags after its number."

      }

      let isExtended: Bool = bytes[5] & 0x10 != 0
      let expected: Int = isExtended ? 22 : 8

      guard count == expected else {

        let kind: String = isExtended ? "an extended message (flags bit 4 set)" : "a standard message"

        return "\(name) with \(kind) has \(expected) bytes, counting 02, not \(count)."

      }

      return nil
    case .beep:
      return count == 2 || count == 3 ? nil : "\(name) has 2 or 3 bytes, counting 02, not \(count)."
    default:
      guard let expected: Int = number.commandLength, count != expected else {

        return nil

      }

      return "\(name) has \(expected) bytes, counting 02, not \(count)."
    }

  }

  /// Why a command of the right length is refused for what it does.
  private static func contentRefusal(for bytes: [UInt8], number: SerialCommandNumber) -> String? {

    switch number {
    case .sendMessage:
      // A message is 02 62 ADDRESS(3) FLAGS CMD1 CMD2, then D1 to D14 when it's extended.
      let command1: UInt8 = bytes[6]
      let isExtended: Bool = bytes.count == 22

      if command1 == 0x2F {

        return "Read/Write ALL-Link Database (0x2F) can change a device's ALL-Link database. Use 'insteon device ADDRESS send' for it."

      }

      if command1 == 0x20 {

        return "Set Operating Flags (0x20) changes a device's settings. Use 'insteon device ADDRESS set' for it."

      }

      if command1 == 0x2E && isExtended && bytes[9] != 0x00 {

        return "Extended Set/Get (0x2E) with D2 other than 0x00 changes a device's settings. Use 'insteon device ADDRESS set' for it."

      }

      return nil
    default:
      return nil
    }

  }

  /// A byte as `0x` and two uppercase digits, such as `0x0F`.
  private static func hexByte(_ value: UInt8) -> String {

    let digits: String = String(value, radix: 16, uppercase: true)

    return "0x" + (digits.count < 2 ? "0" + digits : digits)

  }

}
