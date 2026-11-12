import InsteonDeviceCatalog
import InsteonProtocol

/// A command InsteonCore sends to a device only where the Insteon device catalog says it means
/// something harmless for that device, or, for Poke, never.
///
/// The four Set Operating Flags (cmd1 `0x20`) commands here can cut a device off from the
/// modem or leave it locked, depending on the device; what each cmd2 does comes from the
/// device's command set, and differs between devices. Each case is named by its cmd2. Each is
/// refused for a device the catalog doesn't know or gives no command set, and for a command set
/// that doesn't say what its cmd2 means. It's sent only where the device's command set names
/// that cmd2 for a flag or command it doesn't guard; a cmd2 the command set names only for a
/// flag or command it guards stays refused. Poke writes any byte of a device's memory and is
/// never sent. Every message InsteonCore sends, raw or not, is checked by its
/// bytes, and nothing forces one through. A raw serial command has no device to look up, so
/// ``SerialCommandPolicy`` refuses all of them in it. The catalog's guards add more commands
/// that are never sent to a device.
///
/// ```swift
/// if let protected = ProtectedCommand(command1: 0x20, command2: 0x0C) {
///   print(protected)   // setOperatingFlags0x0C
/// }
/// ```
public enum ProtectedCommand: Hashable, Sendable, CaseIterable {

  /// Set Operating Flags with cmd2 `0x00`.
  case setOperatingFlags0x00

  /// Set Operating Flags with cmd2 `0x0C`.
  case setOperatingFlags0x0C

  /// Set Operating Flags with cmd2 `0x0E`.
  case setOperatingFlags0x0E

  /// Set Operating Flags with cmd2 `0x19`.
  case setOperatingFlags0x19

  /// Poke One Byte (cmd1 `0x29`), with any cmd2, which writes a byte of a device's memory, its
  /// ALL-Link database included, at the address that Set Address MSB (`0x28`) and Peek One
  /// Byte (`0x2B`) choose. Those two write nothing, so they're sent.
  case poke

  /// Set Operating Flags' cmd1.
  static let setOperatingFlags: UInt8 = 0x20

  /// Poke One Byte's cmd1.
  static let pokeCommand1: UInt8 = 0x29

  /// The protected command a message's cmd1 and cmd2 send, if they send one.
  ///
  /// - Parameters:
  ///   - command1: The message's cmd1.
  ///   - command2: The message's cmd2.
  public init?(command1: UInt8, command2: UInt8) {

    if command1 == Self.pokeCommand1 {

      self = .poke

      return

    }

    guard command1 == Self.setOperatingFlags else {

      return nil

    }

    switch command2 {
    case 0x00:
      self = .setOperatingFlags0x00
    case 0x0C:
      self = .setOperatingFlags0x0C
    case 0x0E:
      self = .setOperatingFlags0x0E
    case 0x19:
      self = .setOperatingFlags0x19
    default:
      return nil
    }

  }

  /// The protected command a message's command sends, if it sends one.
  init?(_ command: Command) {

    self.init(command1: command.command1, command2: command.command2)

  }

  /// The Set Operating Flags cmd2, or `nil` for ``poke``, which is a cmd1 with any cmd2.
  public var command2: UInt8? {

    switch self {
    case .setOperatingFlags0x00:
      0x00
    case .setOperatingFlags0x0C:
      0x0C
    case .setOperatingFlags0x0E:
      0x0E
    case .setOperatingFlags0x19:
      0x19
    case .poke:
      nil
    }

  }

  /// The Set Operating Flags command, or `nil` for ``poke``, which is a cmd1 with any cmd2.
  var setOperatingFlagsCommand: Command? {

    command2.map { (command2: UInt8) -> Command in Command(command1: Self.setOperatingFlags, command2: command2) }

  }

  /// The Set Operating Flags commands of the protected commands.
  static let setOperatingFlagsCommands: Set<Command> = Set(allCases.compactMap(\.setOperatingFlagsCommand))

}

/// Why InsteonCore refused to send a message or write a serial command as it was given.
///
/// It's thrown before anything is sent, by the raw passthroughs:
/// ``DeviceNetwork/send(_:collectingFor:consent:onAcknowledgment:)`` and
/// ``ModemSession/write(rawCommand:forcing:collectingFor:clock:)``. Only
/// ``SendRefusal/serialCommand(_:)`` can be forced; ``canBeForced`` says so.
///
/// ```swift
/// do {
///   _ = try await network.send(message, collectingFor: .seconds(3)) { _ in }
/// } catch let refusal as SendRefusal {
///   print(refusal)
/// }
/// ```
public enum SendRefusal: Error, Hashable, Sendable {

  /// The message is a protected command, which isn't sent to the device: Poke, or Set
  /// Operating Flags with a cmd2 its command set doesn't name for a flag it doesn't guard.
  case protected(ProtectedCommand)

  /// The message is a protected Set Operating Flags whose cmd2 the device's command set gives
  /// to an operating flag it guards, so it isn't sent. The associated values are the command,
  /// the flag's label, and whether the cmd2 turns the flag on.
  case setsGuardedFlag(ProtectedCommand, label: String, setting: Bool)

  /// The Insteon device catalog marks the message's bytes as never sent to the device. The
  /// associated value is the product, as a sentence names it.
  case neverSentToDevice(product: String)

  /// The message writes a byte that holds operating flags the catalog guards, which only
  /// ``Device/writeSetting(_:to:button:)`` writes, once it has read the byte. The associated
  /// value is the label of a guarded flag in the byte.
  case writesGuardedFlags(label: String)

  /// The message is an extended Set (cmd1 `0x2E` with D2 other than `0x00`) to a device the
  /// catalog doesn't know or gives no command set, so which bits it writes can't be told.
  case extendedSetWithoutCommandSet

  /// The message is an extended Set whose selector, in D2, the device's command set doesn't
  /// list, so which bytes it writes can't be told. The associated value is the selector.
  case unlistedExtendedSet(selector: UInt8)

  /// The bytes don't start with Start of Text (`0x02`), as every serial command does.
  case notSerialCommand

  /// The bytes hold a Send Insteon Standard or Extended Message (`0x62`) or Send ALL-Link
  /// Command (`0x61`) that's cut short, which the next command's bytes could finish.
  case incompleteMessage

  /// ``SerialCommandPolicy/refusal(for:)`` refuses the serial command unless it's forced. The
  /// associated value is its reason, as a sentence.
  case serialCommand(String)

  /// The consent the send was given doesn't grant what the message does, so nothing is sent
  /// until it does. The associated value is the effect to grant, or `nil` for a message no
  /// entry of the device's command set describes. ``SendPolicy`` decides it.
  case needsConsent(CommandEffect?)

  /// Whether forcing the command would write it: only for ``serialCommand(_:)``.
  public var canBeForced: Bool {

    if case .serialCommand = self {

      return true

    }

    return false

  }

}
