import InsteonProtocol

/// A command a Hub 2242 runs itself, sent in its short form rather than as a serial command
/// for its modem.
///
/// The Insteon Hub Developer's Guide gives the short form as `/0?<cmd1><group>=I=0`: the
/// command in hex, then the group in decimal. Send it with ``Hub/send(_:)``.
///
/// ```swift
/// try await hub.send(.groupCommand(command1: 0x11, group: 0x01))   // GET /0?1101=I=0
/// try await hub.send(.startLinking(group: 0x01))                  // GET /0?0901=I=0
/// try await hub.send(.cancelLinking)                              // GET /0?08=I=0
/// ```
public enum HubShortCommand: Hashable, Sendable {

  /// Sends a command to an ALL-Link group, such as On (`0x11`), Off (`0x13`) or Start
  /// Brighten or Dim (`0x17`).
  case groupCommand(command1: UInt8, group: AllLinkGroupNumber)

  /// Puts the Hub's modem into linking mode for a group (`0x09`).
  case startLinking(group: AllLinkGroupNumber)

  /// Puts the Hub's modem into unlinking mode for a group (`0x0A`).
  case startUnlinking(group: AllLinkGroupNumber)

  /// Takes the Hub's modem out of linking or unlinking mode (`0x08`).
  case cancelLinking

  /// The command as the short form's query names it: the command in hex, then the group in
  /// decimal, with at least two digits.
  var text: String {

    switch self {
    case let .groupCommand(command1, group):
      command1.hexDigits + Self.decimal(group)
    case let .startLinking(group):
      "09" + Self.decimal(group)
    case let .startUnlinking(group):
      "0A" + Self.decimal(group)
    case .cancelLinking:
      "08"
    }

  }

  private static func decimal(_ group: AllLinkGroupNumber) -> String {

    group.rawValue < 10 ? "0\(group.rawValue)" : "\(group.rawValue)"

  }

}
