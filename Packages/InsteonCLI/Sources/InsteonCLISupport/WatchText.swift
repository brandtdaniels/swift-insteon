import InsteonCore

/// What `insteon watch` prints for what a `DeviceMonitor` heard.
public enum WatchText {

  /// What `insteon watch` says when it starts, about which messages reach the modem.
  public static let startHint = [
    "Watching the modem. Press Control-C to stop.",
    "Only messages sent to the modem, and group broadcasts from devices it has responder records for, reach it. "
      + "To hear a device's buttons, link the modem as its responder: 'insteon link --responder', "
      + "or 'insteon link ADDRESS --two-way'."
  ]

  /// An event in words, as `insteon watch` prints it after the time, such as
  /// `"1A.2B.3C group 1: wet"`. Raw bytes and replies start with `raw`.
  ///
  /// - Parameter event: The event.
  /// - Returns: The line.
  public static func line(for event: DeviceMonitorEvent) -> String {

    switch event {
    case let .identified(device, productName?):
      return "\(device) identified as \(productName)"
    case let .identified(device, nil):
      return "\(device) reported an identity the Insteon device catalog doesn't have"
    case let .setButtonPressed(press):
      return setButtonPressed(press)
    case let .groupCommand(command):
      if let event = command.event {

        return "\(command.device) group \(command.group): \(event)"

      }

      return "\(command.device) group \(command.group): cmd1 \(Hex.byte(command.command1))\(named(command.commandName))"
    case let .heartbeat(device, group):
      return "\(device) heartbeat, group \(group)"
    case let .heartbeatBroadcast(device, batteryLevel):
      return "\(device) heartbeat, battery level \(Hex.byte(batteryLevel))"
    case let .statusChanged(device):
      return "\(device) status changed; ask with 'insteon device \(device) status'"
    case let .message(summary):
      return message(summary)
    case let .modem(notice):
      return modem(notice)
    case let .rawMessage(frame):
      return "raw  \(RawFrame.text(of: frame))"
    case let .rawReply(kind):
      return "raw  modem reply: \(kind)"
    }

  }

  /// A SET Button Pressed broadcast, in words, such as
  /// `"1A.2B.3C SET button pressed (cmd1 0x01, links as a responder); identified as Dimmer Switch 2477D"`.
  ///
  /// - Parameter press: The broadcast, with the product the catalog has for its identity.
  /// - Returns: The line.
  public static func setButtonPressed(_ press: DeviceSetButtonPress) -> String {

    let identity: ReportedIdentity = press.identity
    let product: String = press.productName
      ?? "category \(identity.category), subcategory \(identity.subcategory)"
        + (identity.firmwareVersion.map { ", firmware \($0)" } ?? "")

    return "\(press.device) SET button pressed (cmd1 \(Hex.byte(press.command1)), links as a \(press.role)); identified as \(product)"

  }

  /// A message from a device in words, its type and command, such as
  /// `"1A.2B.3C to 11.22.33: ACK, cmd1 0x11 (Light On) cmd2 0xFF"`.
  ///
  /// - Parameter summary: The message.
  /// - Returns: The text.
  public static func message(_ summary: DeviceMessageSummary) -> String {

    let extended: String = summary.isExtended ? " extended" : ""

    return "\(summary.sender) to \(summary.destination): \(summary.type)\(extended), "
      + "cmd1 \(Hex.byte(summary.command1))\(named(summary.commandName)) cmd2 \(Hex.byte(summary.command2))"

  }

  /// What the modem reported on its own, in words.
  ///
  /// - Parameter notice: The notice.
  /// - Returns: The text.
  public static func modem(_ notice: ModemNotice) -> String {

    switch notice {
    case let .allLinkingCompleted(device, group, modemRole):
      "ALL-Linking completed with \(device) in group \(group), modem \(modemRole ?? "unknown")"
    case let .buttonEvent(event):
      "Modem button: \(event)"
    case .userReset:
      "The modem was reset to factory defaults with its SET button"
    case let .allLinkCleanupFailed(device, group):
      "\(device) didn't acknowledge the ALL-Link cleanup for group \(group)"
    case let .x10Received(code):
      "X10: \(code)"
    }

  }

  /// A command's name in parentheses after a space, or nothing.
  private static func named(_ name: String?) -> String {

    name.map { " (\($0))" } ?? ""

  }

}

/// The bytes a modem sent for a message, as `insteon watch --raw` prints them.
public enum RawFrame {

  /// The frame in hexadecimal, grouped by field, such as `"0250 1A2B3C 012041 8F 01 00"`.
  ///
  /// - Parameter frame: The bytes the modem sent for the message, from its start of text.
  /// - Returns: The text.
  public static func text(of frame: [UInt8]) -> String {

    let bounds: [Int] = [0, 2, 5, 8, 9, 10, 11]
    var fields: [ArraySlice<UInt8>] = []

    for (index, start) in bounds.enumerated() where start < frame.count {

      let end: Int = index + 1 < bounds.count ? min(bounds[index + 1], frame.count) : frame.count

      fields.append(frame[start..<end])

    }

    return fields.map { $0.map(Self.digits).joined() }.joined(separator: " ")

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
