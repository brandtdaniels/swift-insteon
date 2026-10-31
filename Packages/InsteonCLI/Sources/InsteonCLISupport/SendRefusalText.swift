import InsteonCore

/// What `insteon device ADDRESS send` and `insteon modem send` say when InsteonCore refuses to
/// send a message as it's given.
public enum SendRefusalText {

  /// A refusal as one sentence, with the reason the message isn't sent.
  ///
  /// - Parameter refusal: The refusal.
  /// - Returns: The sentence.
  public static func sentence(_ refusal: SendRefusal) -> String {

    switch refusal {
    case let .protected(command):
      return sentence(command)
    case let .neverSentToDevice(product):
      return "The Insteon device catalog marks this message as one never sent to \(product); insteon never sends it."
    case let .writesGuardedFlags(label):
      return "This message writes the byte that holds \(label), which only 'insteon device ADDRESS set' changes, once it has read the byte; insteon never sends it as given."
    case .extendedSetWithoutCommandSet:
      return "Without the device's catalog entry, insteon can't tell which bits an extended Set writes, such as a programming lock's, so it doesn't send one as given; run 'insteon device ADDRESS id' first, so the identity cache knows the device."
    case .notSerialCommand:
      return "A serial command starts with 02."
    case .incompleteMessage:
      return "The bytes hold a message to a device or a group that's cut short, which the next command's bytes could finish; insteon never sends it."
    case let .serialCommand(reason):
      return "\(reason) Pass --force to send it anyway."
    }

  }

  /// Why a protected command isn't sent, as one sentence.
  ///
  /// - Parameter command: The command.
  /// - Returns: The sentence.
  public static func sentence(_ command: ProtectedCommand) -> String {

    switch command {
    case .programmingLockOn:
      return "Turning the programming lock on would stop the device's SET button from linking it; insteon sends it only to a device whose catalog entry gives the byte another meaning."
    case .radioOff:
      return "Turning radio off would cut the device off the network; insteon sends it only to a device whose catalog entry gives the byte another meaning."
    case .powerlineOff:
      return "Turning powerline off would cut the device off the network; insteon sends it only to a device whose catalog entry gives the byte another meaning."
    case .checksumOn:
      return "Requiring a checksum in every message would cut the device off from a modem that doesn't send one; insteon sends it only to a device whose catalog entry gives the byte another meaning."
    case .poke:
      return "Poke One Byte writes any byte of a device's memory, its ALL-Link database included; insteon never sends it."
    }

  }

}
