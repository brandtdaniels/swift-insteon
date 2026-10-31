import InsteonProtocol

/// A command InsteonCore never sends to any device, whatever the Insteon device catalog says
/// about the device, and whether or not the catalog knows it.
///
/// The four Set Operating Flags (cmd1 `0x20`) commands here cut a device off from the modem or
/// leave it locked, and Poke writes any byte of a device's memory. Every message InsteonCore
/// sends, raw or not, is checked against them by its bytes; nothing forces one through. The
/// catalog can name more commands that are never sent to a device, but never fewer.
///
/// ```swift
/// if let protected = ProtectedCommand(command1: 0x20, command2: 0x0C) {
///   print(protected)   // radioOff
/// }
/// ```
public enum ProtectedCommand: Hashable, Sendable, CaseIterable {

  /// Set Operating Flags with cmd2 `0x00`, which turns a device's programming lock on, so its
  /// SET button doesn't link it.
  case programmingLockOn

  /// Set Operating Flags with cmd2 `0x0C`, which turns a dual-band device's radio off, so it
  /// can't hear the modem by radio.
  case radioOff

  /// Set Operating Flags with cmd2 `0x0E`, which turns a dual-band device's powerline off, so
  /// it can't hear the modem over the powerline.
  case powerlineOff

  /// Set Operating Flags with cmd2 `0x19`, which makes a device require a checksum in every
  /// message, so a modem that doesn't send one can't reach it.
  case checksumOn

  /// Set Address MSB (cmd1 `0x28`) or Poke One Byte (cmd1 `0x29`), with any cmd2, which
  /// together write any byte of a device's memory, its ALL-Link database included.
  case poke

  /// Set Operating Flags' cmd1.
  static let setOperatingFlags: UInt8 = 0x20

  /// The cmd1s of Set Address MSB and Poke One Byte.
  static let pokeCommand1s: Set<UInt8> = [0x28, 0x29]

  /// The protected command a message's cmd1 and cmd2 send, if they send one.
  ///
  /// - Parameters:
  ///   - command1: The message's cmd1.
  ///   - command2: The message's cmd2.
  public init?(command1: UInt8, command2: UInt8) {

    if Self.pokeCommand1s.contains(command1) {

      self = .poke

      return

    }

    guard command1 == Self.setOperatingFlags else {

      return nil

    }

    switch command2 {
    case 0x00:
      self = .programmingLockOn
    case 0x0C:
      self = .radioOff
    case 0x0E:
      self = .powerlineOff
    case 0x19:
      self = .checksumOn
    default:
      return nil
    }

  }

  /// The protected command a message's command sends, if it sends one.
  init?(_ command: Command) {

    self.init(command1: command.command1, command2: command.command2)

  }

  /// The Set Operating Flags command, or `nil` for ``poke``, which is a cmd1 with any cmd2.
  var setOperatingFlagsCommand: Command? {

    switch self {
    case .programmingLockOn:
      Command(command1: Self.setOperatingFlags, command2: 0x00)
    case .radioOff:
      Command(command1: Self.setOperatingFlags, command2: 0x0C)
    case .powerlineOff:
      Command(command1: Self.setOperatingFlags, command2: 0x0E)
    case .checksumOn:
      Command(command1: Self.setOperatingFlags, command2: 0x19)
    case .poke:
      nil
    }

  }

  /// The Set Operating Flags commands of the protected commands.
  static let setOperatingFlagsCommands: Set<Command> = Set(allCases.compactMap(\.setOperatingFlagsCommand))

}

/// Why InsteonCore refused to send a message or write a serial command as it was given.
///
/// It's thrown before anything is sent, by the raw passthroughs:
/// ``DeviceNetwork/send(_:collectingFor:onAcknowledgment:)`` and
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

  /// The message is a command never sent to any device.
  case protected(ProtectedCommand)

  /// The Insteon device catalog marks the message's bytes as never sent to the device. The
  /// associated value is the product, as a sentence names it.
  case neverSentToDevice(product: String)

  /// The message writes a byte that holds operating flags the catalog guards, which only
  /// ``Device/writeSetting(_:to:button:)`` writes, once it has read the byte. The associated
  /// value is the label of a guarded flag in the byte.
  case writesGuardedFlags(label: String)

  /// The bytes don't start with Start of Text (`0x02`), as every serial command does.
  case notSerialCommand

  /// The bytes hold a Send Insteon Standard or Extended Message (`0x62`) or Send ALL-Link
  /// Command (`0x61`) that's cut short, which the next command's bytes could finish.
  case incompleteMessage

  /// ``SerialCommandPolicy/refusal(for:)`` refuses the serial command unless it's forced. The
  /// associated value is its reason, as a sentence.
  case serialCommand(String)

  /// Whether forcing the command would write it: only for ``serialCommand(_:)``.
  public var canBeForced: Bool {

    if case .serialCommand = self {

      return true

    }

    return false

  }

}
