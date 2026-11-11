import InsteonCore

/// What the `insteon` command says when InsteonCore stops short of sending a message because
/// the command didn't grant what the message does, in the protocol's terms.
public enum ConsentText {

  /// What a message does, as a clause that follows "a message that".
  ///
  /// An effect this package doesn't know reads as destructive, as InsteonCore reads it.
  ///
  /// - Parameter effect: The effect, or `nil` for a message no catalog entry describes.
  /// - Returns: Such as `"changes a setting the device keeps"`.
  public static func clause(_ effect: CommandEffect?) -> String {

    switch reading(effect) {
    case nil:
      "no entry of the device's catalog describes"
    case .readOnly?:
      "asks for state"
    case .configuration?:
      "changes a setting the device keeps"
    case .link?:
      "puts the device in or out of ALL-Linking mode, or adds an ALL-Link record"
    case .actuation?:
      "changes what the device does at once"
    default:
      "removes or overwrites ALL-Link records, memory or counters, restores factory settings, or leaves the device unable to communicate with the modem"
    }

  }

  /// The sentence `insteon device ADDRESS send` ends with when it needs more consent.
  ///
  /// - Parameter effect: The effect to grant, or `nil` for a message no entry describes.
  /// - Returns: The sentence, which names `--force` for the effects it grants.
  public static func deviceSend(_ effect: CommandEffect?) -> String {

    switch reading(effect) {
    case .destructive?:
      "The Insteon device catalog describes this message as one that \(clause(effect)); pass --force to send it."
    case nil:
      "No entry of the device's catalog describes this message; insteon device ADDRESS send sends it."
    default:
      "The Insteon device catalog describes this message as one that \(clause(effect)); insteon device ADDRESS send sends it."
    }

  }

  /// An effect as InsteonCore reads it: one this package doesn't know is destructive.
  private static func reading(_ effect: CommandEffect?) -> CommandEffect? {

    guard let effect, effect.strictness == .destructive else {

      return effect

    }

    return .destructive

  }

}
