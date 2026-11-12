import InsteonCore

/// What the `insteon` command says when InsteonCore stops short of sending a message because
/// the command didn't grant what the message does, in the protocol's terms.
public enum ConsentText {

  /// What a message does, as a clause that follows "a message that".
  ///
  /// An effect this package doesn't know reads as destructive, as InsteonCore reads it.
  ///
  /// - Parameters:
  ///   - effect: The effect, or `nil` for a message no catalog entry describes.
  ///   - addressee: What the message is for: `"device"` or `"modem"`. Defaults to `"device"`.
  /// - Returns: Such as `"changes a setting the device keeps"`.
  public static func clause(_ effect: CommandEffect?, of addressee: String = "device") -> String {

    switch reading(effect) {
    case nil:
      "no entry of the \(addressee)'s catalog describes"
    case .readOnly?:
      "asks for state"
    case .configuration?:
      "changes a setting the \(addressee) keeps"
    case .link?:
      "puts the \(addressee) in or out of ALL-Linking mode, or adds an ALL-Link record"
    case .actuation?:
      "changes what the \(addressee) does at once"
    default:
      "removes or overwrites ALL-Link records, memory or counters, restores factory settings, or leaves the \(addressee) unable to communicate with \(addressee == "modem" ? "its host" : "the modem")"
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

  /// The sentence `insteon modem send` ends with when it needs more consent.
  ///
  /// - Parameter effect: The effect to grant, or `nil` for a command no entry describes.
  /// - Returns: The sentence, which names `--force`.
  public static func modemSend(_ effect: CommandEffect?) -> String {

    switch reading(effect) {
    case nil:
      "No entry of the modem's catalog describes this command, or the catalog has no entry for the modem; pass --force to send it."
    default:
      "The modem's catalog entry describes this command as one that \(clause(effect, of: "modem")); pass --force to send it."
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
