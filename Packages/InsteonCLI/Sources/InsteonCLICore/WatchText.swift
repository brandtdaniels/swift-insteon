import InsteonProtocol

/// What `insteon watch` prints that doesn't need the catalog.
public enum WatchText {

  /// What `insteon watch` says when it starts, about which messages reach the modem.
  public static let startHint = [
    "Watching the modem. Press Control-C to stop.",
    "Only messages sent to the modem, and group broadcasts from devices it has responder records for, reach it. "
      + "To hear a device's buttons, link the modem as its responder: 'insteon link --responder', "
      + "or 'insteon link ADDRESS --two-way'."
  ]

  /// A SET Button Pressed broadcast, in words, such as
  /// `"1A.2B.3C SET button pressed (cmd1 0x01, links as a responder); identified as Dimmer Switch 2477D"`.
  ///
  /// - Parameters:
  ///   - pressed: The broadcast.
  ///   - productName: The product the catalog has for its identity, or `nil` if it has none
  ///     or wasn't loaded.
  /// - Returns: The line.
  public static func setButtonPressed(_ pressed: SetButtonPressed, productName: String?) -> String {

    let role: String = pressed.role.description
    let identity = productName
      ?? "category \(pressed.category), subcategory \(pressed.subcategory)"
        + (pressed.firmwareVersion.map { ", firmware \($0)" } ?? "")

    return "\(pressed.sender) SET button pressed (cmd1 \(Hex.byte(pressed.role.rawValue)), links as a \(role)); identified as \(identity)"

  }

}

/// The bytes a modem sent for a message, as `insteon watch --raw` prints them.
public enum RawFrame {

  /// The frame in hexadecimal, grouped by field, such as `"0250 1A2B3C 012041 8F 01 00"`.
  ///
  /// - Parameter message: The message.
  /// - Returns: The text.
  public static func text(of message: ReceivedMessage) -> String {

    let frame: [UInt8] = message.modemFrame
    let fields = [frame[0..<2], frame[2..<5], frame[5..<8], frame[8..<9], frame[9..<10], frame[10..<11], frame[11...]]

    return fields.filter { !$0.isEmpty }.map { $0.map(Self.digits).joined() }.joined(separator: " ")

  }

  /// A byte as two uppercase hexadecimal digits.
  private static func digits(_ byte: UInt8) -> String {

    String(Hex.byte(byte).dropFirst(2))

  }

}

/// How `insteon discover` found a Hub.
public enum DiscoveryMethod: String, Hashable, Sendable, CaseIterable {

  /// By asking every address on the local network.
  case local

  /// By asking Insteon Connect.
  case insteonConnect

  /// The way in words, as the FOUND BY column shows it: "local network" or "Insteon Connect".
  public var label: String {

    switch self {
    case .local: "local network"
    case .insteonConnect: "Insteon Connect"
    }

  }

}
