import InsteonCore

/// What `insteon device ADDRESS send` and `insteon modem send` say when InsteonCore refuses to
/// send a message as it's given.
public enum SendRefusalText {

  /// The raw passthrough that refused a message, which says what the refusal means: `device
  /// ADDRESS send` checks a message against the device's catalog entry, and `modem send` has
  /// no device to look up.
  public enum Passthrough: Hashable, Sendable {

    /// `insteon device ADDRESS send`.
    case deviceSend

    /// `insteon modem send`.
    case modemSend

  }

  /// A refusal as one sentence, with the reason the message isn't sent. What a protected Set
  /// Operating Flags does comes from the device's catalog entry, so the sentence names the
  /// guarded flag the entry gives its cmd2 to, or else says only what the protocol does.
  ///
  /// - Parameters:
  ///   - refusal: The refusal.
  ///   - passthrough: The passthrough that refused it.
  /// - Returns: The sentence.
  public static func sentence(_ refusal: SendRefusal, from passthrough: Passthrough) -> String {

    switch refusal {
    case let .protected(command):
      return sentence(command, from: passthrough)
    case let .setsGuardedFlag(command, label, setting):
      guard passthrough == .deviceSend, let command2 = command.command2 else {

        return sentence(command, from: passthrough)

      }

      return "Set Operating Flags \(Hex.byte(command2)) turns this device's '\(label)' flag \(setting ? "on" : "off"), a flag its catalog entry guards; insteon never sends it as given."
    case let .neverSentToDevice(product):
      return "The Insteon device catalog marks this message as one never sent to \(product); insteon never sends it."
    case let .writesGuardedFlags(label):
      return "This message writes the byte that holds \(label), which only 'insteon device ADDRESS set' changes, once it has read the byte; insteon never sends it as given."
    case let .unlistedExtendedSet(selector):
      let hex: String = String(selector, radix: 16, uppercase: true)
      return "The device's catalog entry lists no extended Set with selector \(hex.count == 1 ? "0" : "")\(hex), so which bytes it writes can't be told; insteon doesn't send it as given."
    case .extendedSetWithoutCommandSet:
      return "Without the device's catalog entry, insteon can't tell which bits an extended Set writes, so it doesn't send one as given; run 'insteon device ADDRESS id' first, so the identity cache knows the device."
    case .notSerialCommand:
      return "A serial command starts with 02."
    case .incompleteMessage:
      return "The bytes hold a message to a device or a group that's cut short, which the next command's bytes could finish; insteon modem send never writes it."
    case let .serialCommand(reason):
      return "\(reason) Pass --force to send it anyway."
    }

  }

  /// Why a protected command isn't sent, as one sentence that says only what the protocol does,
  /// since what a Set Operating Flags cmd2 does depends on the device.
  ///
  /// - Parameters:
  ///   - command: The command.
  ///   - passthrough: The passthrough that refused it.
  /// - Returns: The sentence.
  public static func sentence(_ command: ProtectedCommand, from passthrough: Passthrough) -> String {

    guard let command2 = command.command2 else {

      let consequence: String = "Poke One Byte writes any byte of a device's memory, its ALL-Link database included"

      switch passthrough {
      case .modemSend:
        return "\(consequence); insteon modem send never writes it."
      case .deviceSend:
        return "\(consequence); insteon never sends it."
      }

    }

    let consequence: String = "Set Operating Flags \(Hex.byte(command2)) can cut a device off from the modem or lock it, depending on the device"

    switch passthrough {
    case .modemSend:
      return "\(consequence); insteon modem send has no device's catalog entry to check, so it never writes it."
    case .deviceSend:
      return "\(consequence); insteon sends it only to a device whose catalog entry names the cmd2 for a flag or command it doesn't guard."
    }

  }

}
