import InsteonCLISupport
import InsteonCore

/// `insteon device ADDRESS send` and `insteon modem send`: messages and serial commands sent
/// as given, for exploring what the Insteon device catalog doesn't describe yet, through
/// InsteonCore's `ModemSession`.
enum ExploreCommands {

  // MARK: - device ADDRESS send

  static func send(_ request: DirectMessageRequest, to device: InsteonAddress, modem: ModemSession) async throws {

    let message = DirectMessage(
      to: device,
      command1: request.command1,
      command2: request.command2,
      data: request.userData,
      hasChecksum: request.hasChecksum
    )

    if let data = message.userData {

      Output.note("Sending \(device) extended cmd1 \(Hex.byte(message.command1)) cmd2 \(Hex.byte(message.command2)), data \(Hex.pairs(data))")

    } else {

      Output.note("Sending \(device) cmd1 \(Hex.byte(message.command1)) cmd2 \(Hex.byte(message.command2))")

    }

    let messages: [ReceivedFrame]

    do {

      // Listening starts before the message, so nothing the device sends is missed.
      messages = try await modem.send(message, collectingFor: .seconds(request.waitSeconds)) { (acknowledgment: ReceivedFrame) -> Void in

        Output.line("ACK: \(text(of: acknowledgment))")

      }

    } catch {

      guard case let .deviceRejected(_, reason)? = SendFailure(error) else {

        throw error

      }

      Output.line("NAK: \(reason.summary) (cmd2 \(Hex.byte(reason.rawValue)))")

      throw CommandFailure(description: "\(device) rejected the message.")

    }

    for frame in messages {

      Output.line(text(of: frame))

    }

    if messages.isEmpty {

      Output.line("No other messages from \(device) in \(request.waitSeconds) s.")

    }

  }

  // MARK: - modem send

  static func send(_ request: RawSerialRequest, modem: ModemSession) async throws {

    Output.note("Writing \(Hex.pairs(request.bytes)) to the modem")

    let received: [RawModemReply] = try await modem.write(rawCommand: request.bytes, collectingFor: .seconds(request.waitSeconds))

    for reply in received {

      Output.line(text(of: reply))

    }

    if received.isEmpty {

      Output.line("The modem sent nothing in \(request.waitSeconds) s.")

    }

  }

  /// A message from a device: its frame in hexadecimal, and what it says.
  private static func text(of frame: ReceivedFrame) -> String {

    "\(RawFrame.text(of: frame.frame))  \(WatchText.message(frame.summary))"

  }

  /// A reply in hexadecimal where its bytes are known, and as the package reads it.
  private static func text(of reply: RawModemReply) -> String {

    switch reply {
    case let .echo(bytes, kind):
      return "\(Hex.pairs(bytes))  \(kind)"
    case let .message(frame):
      return text(of: frame)
    case .negativeAcknowledgment:
      return "15  NAK"
    case let .other(kind, description):
      return "\(kind): \(description)"
    }

  }

}
