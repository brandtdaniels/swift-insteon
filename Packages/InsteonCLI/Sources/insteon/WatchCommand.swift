import Foundation
import InsteonCLICore
import InsteonDeviceCatalog
import InsteonModem
import InsteonProtocol

/// `insteon watch`: prints what the modem hears until Control-C.
enum WatchCommand {

  static func run(_ options: WatchOptions, modem: Modem, names: ProductNames) async {

    var interpreter = DeviceEventInterpreter<ContinuousClock.Instant>(catalog: names.catalog ?? DeviceCatalog(profiles: []))
    let replies = await modem.replies()
    let timeFormatter = DateFormatter()
    timeFormatter.locale = Locale(identifier: "en_US_POSIX")
    timeFormatter.dateFormat = "HH:mm:ss"

    for line in WatchText.startHint {

      Output.note(line)

    }

    // The stream finishes when Control-C cancels this task, or when the modem closes.
    for await reply in replies {

      let time = timeFormatter.string(from: Date())

      guard case let .messageReceived(message) = reply else {

        if let text = describe(reply) {

          Output.line("\(time)  \(text)")

        } else if options.printsRawReplies {

          Output.line("\(time)  raw  modem reply: \(Names.replyKind(reply))")

        }

        continue

      }

      if options.printsRawReplies {

        Output.line("\(time)  raw  \(RawFrame.text(of: message))")

      }

      var events = interpreter.events(from: message, at: .now)

      // A SET Button Pressed broadcast says why it came, along with the identity it reports.
      // The interpreter reports its identity only the first time, so a repeat of the
      // broadcast isn't printed again.
      if let pressed = SetButtonPressed(message) {

        let isNew: Bool = events.contains { event in

          if case .identified = event { true } else { false }

        }

        if isNew {

          let profile = names.catalog?.profile(category: pressed.category, subcategory: pressed.subcategory, firmwareVersion: pressed.firmwareVersion)

          Output.line("\(time)  \(WatchText.setButtonPressed(pressed, productName: profile?.displayName))")

        }

        events.removeAll { event in

          if case .identified = event { true } else { false }

        }

      }

      for event in events {

        Output.line("\(time)  \(describe(event))")

      }

      // Broadcasts and cleanups are the interpreter's to report, and it leaves out repeats;
      // other messages, such as acknowledgments, are printed as they are, and every message
      // is when its bytes are.
      switch message.flags.messageType {
      case .broadcast, .allLinkBroadcast, .allLinkCleanup:
        if options.printsRawReplies, events.isEmpty, SetButtonPressed(message) == nil {

          Output.line("\(time)  \(describe(message))")

        }
      default:
        if events.isEmpty {

          Output.line("\(time)  \(describe(message))")

        }
      }

    }

  }

  private static func describe(_ event: DeviceEvent) -> String {

    switch event {
    case let .identified(device, profile?):
      return "\(device) identified as \(profile.displayName)"
    case let .identified(device, nil):
      return "\(device) reported an identity the Insteon device catalog doesn't have"
    case let .groupCommand(command, eventName?):
      return "\(command.controller) group \(command.group): \(eventName)"
    case let .groupCommand(command, nil):
      let name = StandardDirectCommand.name(command1: command.command1).map { " (\($0))" } ?? ""

      return "\(command.controller) group \(command.group): cmd1 \(Hex.byte(command.command1))\(name)"
    case let .heartbeat(command):
      return "\(command.controller) heartbeat, group \(command.group)"
    case let .heartbeatBroadcast(heartbeat):
      return "\(heartbeat.sender) heartbeat, battery level \(Hex.byte(heartbeat.batteryLevel))"
    case let .statusChanged(device):
      return "\(device) status changed; ask with 'insteon device \(device) status'"
    }

  }

  /// A message from a device in words, such as its type and command.
  static func describe(_ message: ReceivedMessage) -> String {

    let name = StandardDirectCommand.name(command1: message.command.command1).map { " (\($0))" } ?? ""
    let type: String = message.flags.messageType.name
    let extended = message.userData == nil ? "" : " extended"

    return "\(message.sender) to \(message.destination): \(type)\(extended), "
      + "cmd1 \(Hex.byte(message.command.command1))\(name) cmd2 \(Hex.byte(message.command.command2))"

  }

  /// What the modem reported on its own, or `nil` for replies to the host's commands.
  private static func describe(_ reply: ModemReply) -> String? {

    switch reply {
    case let .allLinkingCompleted(link):
      "ALL-Linking completed with \(link.address) in group \(link.group), modem \(Names.mode(link.mode))"
    case let .buttonEvent(event):
      "Modem button: \(event)"
    case .userReset:
      "The modem was reset to factory defaults with its SET button"
    case let .allLinkCleanupFailed(group, address):
      "\(address) didn't acknowledge the ALL-Link cleanup for group \(group)"
    case let .x10Received(code):
      "X10: \(code)"
    default:
      nil
    }

  }

}
