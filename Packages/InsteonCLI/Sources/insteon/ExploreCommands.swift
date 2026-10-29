import InsteonCLICore
import InsteonModem
import InsteonProtocol

/// `insteon device ADDRESS send` and `insteon modem send`: messages and serial commands sent
/// as given, for exploring what the Insteon device catalog doesn't describe yet.
enum ExploreCommands {

  // MARK: - device ADDRESS send

  static func send(_ request: DirectMessageRequest, to device: InsteonAddress, modem: Modem) async throws {

    let command = Command(command1: request.command1, command2: request.command2)

    // Listening starts before the message, so nothing the device sends is missed.
    let replies = await modem.replies()
    let acknowledgment: ReceivedMessage

    do {

      if let data = request.userData {

        let message = extendedMessage(to: device, command: command, data: data, hasChecksum: request.hasChecksum)

        Output.note("Sending \(device) extended cmd1 \(Hex.byte(command.command1)) cmd2 \(Hex.byte(command.command2)), data \(Hex.pairs(message.userData.bytes))")
        acknowledgment = try await modem.request(message)

      } else {

        Output.note("Sending \(device) cmd1 \(Hex.byte(command.command1)) cmd2 \(Hex.byte(command.command2))")
        acknowledgment = try await modem.request(StandardMessage(to: device, command: command))

      }

    } catch ModemError.deviceRejected(_, let reason) {

      Output.line("NAK: \(reason.summary) (cmd2 \(Hex.byte(reason.rawValue)))")

      throw CommandFailure(description: "\(device) rejected the message.")

    }

    Output.line("ACK: \(RawFrame.text(of: acknowledgment))  \(WatchCommand.describe(acknowledgment))")

    let messages: [ModemReply] = await Replies.all(in: replies, within: .seconds(request.waitSeconds))
    var skippedAcknowledgment = false
    var count = 0

    for reply in messages {

      guard case let .messageReceived(message) = reply, message.sender == device else {

        continue

      }

      // The acknowledgment already printed comes through the stream too.
      if !skippedAcknowledgment, message == acknowledgment {

        skippedAcknowledgment = true
        continue

      }

      count += 1
      Output.line("\(RawFrame.text(of: message))  \(WatchCommand.describe(message))")

    }

    if count == 0 {

      Output.line("No other messages from \(device) in \(request.waitSeconds) s.")

    }

  }

  private static func extendedMessage(to device: InsteonAddress, command: Command, data: [UInt8], hasChecksum: Bool) -> ExtendedMessage {

    var userData = UserData()

    for (offset, byte) in data.prefix(UserData.count).enumerated() {

      userData[offset + 1] = byte

    }

    if hasChecksum {

      return ExtendedMessage(to: device, command: command, userData: userData)

    }

    return ExtendedMessage(to: device, command: command, userData: userData, integrity: UnprotectedIntegrity())

  }

  // MARK: - modem send

  static func send(_ request: RawSerialRequest, modem: Modem) async throws {

    let replies = await modem.replies()

    Output.note("Writing \(Hex.pairs(request.bytes)) to the modem")

    try await modem.write(rawCommand: request.bytes)

    let received: [ModemReply] = await Replies.all(in: replies, within: .seconds(request.waitSeconds))

    for reply in received {

      Output.line(text(of: reply))

    }

    if received.isEmpty {

      Output.line("The modem sent nothing in \(request.waitSeconds) s.")

    }

  }

  /// A reply in hexadecimal where its bytes are known, and as the package reads it.
  private static func text(of reply: ModemReply) -> String {

    switch reply {
    case let .echo(echo):
      let bytes: [UInt8] = [0x02, echo.number.rawValue] + echo.parameters + [echo.isAccepted ? 0x06 : 0x15]

      return "\(Hex.pairs(bytes))  \(Names.replyKind(reply))"
    case let .messageReceived(message):
      return "\(RawFrame.text(of: message))  \(WatchCommand.describe(message))"
    case .negativeAcknowledgment:
      return "15  NAK"
    default:
      return "\(Names.replyKind(reply)): \(reply)"
    }

  }

}

extension Replies {

  /// Everything that arrives within a time, in order. The time is waited out in full unless
  /// the modem closes first.
  static func all(in replies: AsyncStream<ModemReply>, within duration: Duration) async -> [ModemReply] {

    let collector = Task { () -> [ModemReply] in

      var collected: [ModemReply] = []

      for await reply in replies {

        collected.append(reply)

        if Task.isCancelled {

          break

        }

      }

      return collected

    }

    try? await Task.sleep(for: duration)
    collector.cancel()

    return await collector.value

  }

}
