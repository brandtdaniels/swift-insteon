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

  /// A refusal as one sentence, with the reason the message isn't sent.
  ///
  /// - Parameters:
  ///   - refusal: The refusal.
  ///   - passthrough: The passthrough that refused it.
  /// - Returns: The sentence.
  public static func sentence(_ refusal: SendRefusal, from passthrough: Passthrough) -> String {

    switch refusal {
    case let .protected(command):
      return sentence(command, from: passthrough)
    case let .neverSentToDevice(product):
      return "The Insteon device catalog marks this message as one never sent to \(product); insteon never sends it."
    case let .writesGuardedFlags(label):
      return "This message writes the byte that holds \(label), which only 'insteon device ADDRESS set' changes, once it has read the byte; insteon never sends it as given."
    case .extendedSetWithoutCommandSet:
      return "Without the device's catalog entry, insteon can't tell which bits an extended Set writes, such as a programming lock's, so it doesn't send one as given; run 'insteon device ADDRESS id' first, so the identity cache knows the device."
    case .notSerialCommand:
      return "A serial command starts with 02."
    case .incompleteMessage:
      return "The bytes hold a message to a device or a group that's cut short, which the next command's bytes could finish; insteon modem send never writes it."
    case let .serialCommand(reason):
      return "\(reason) Pass --force to send it anyway."
    }

  }

  /// Why a protected command isn't sent, as one sentence.
  ///
  /// - Parameters:
  ///   - command: The command.
  ///   - passthrough: The passthrough that refused it.
  /// - Returns: The sentence.
  public static func sentence(_ command: ProtectedCommand, from passthrough: Passthrough) -> String {

    let consequence: String

    switch command {
    case .programmingLockOn:
      consequence = "Turning the programming lock on would stop the device's SET button from linking it"
    case .radioOff:
      consequence = "Turning radio off would cut the device off the network"
    case .powerlineOff:
      consequence = "Turning powerline off would cut the device off the network"
    case .checksumOn:
      consequence = "Requiring a checksum in every message would cut the device off from a modem that doesn't send one"
    case .poke:
      consequence = "Poke One Byte writes any byte of a device's memory, its ALL-Link database included"
    }

    switch (passthrough, command) {
    case (.modemSend, _):
      return "\(consequence); insteon modem send never writes it."
    case (.deviceSend, .poke):
      return "\(consequence); insteon never sends it."
    case (.deviceSend, _):
      return "\(consequence); insteon sends it only to a device whose catalog entry gives the byte another meaning."
    }

  }

}
