import InsteonCore

/// Where a command's lines go: progress and errors, and results.
public protocol CommandOutput: Sendable {

  /// Writes a line of progress, a prompt or an error.
  func note(_ text: String)

  /// Writes a line of results.
  func line(_ text: String)

}

/// What `insteon modem send` writes serial commands through: ``ModemSession``.
public protocol RawCommandWriting: Sendable {

  /// Writes a serial command as given and collects what the modem sends, calling `onWriting`
  /// once the command is allowed and just before its bytes are written, never for a refused one.
  func writeRaw(_ bytes: [UInt8], forcing: Bool, collectingFor duration: Duration, onWriting: @Sendable () -> Void) async throws -> [RawModemReply]

}

extension ModemSession: RawCommandWriting {

  public func writeRaw(_ bytes: [UInt8], forcing: Bool, collectingFor duration: Duration, onWriting: @Sendable () -> Void) async throws -> [RawModemReply] {

    try await write(rawCommand: bytes, forcing: forcing, collectingFor: duration, onWriting: onWriting)

  }

}

/// What `insteon device ADDRESS send` sends messages through: ``DeviceNetwork``.
public protocol DirectMessageSending: Sendable {

  /// Sends a message as given and collects what the device sends, calling `onSending` once
  /// the message is allowed and just before it is sent, never for a refused one.
  func sendDirect(
    _ message: DirectMessage,
    collectingFor duration: Duration,
    consent: SendConsent,
    onSending: @Sendable () -> Void,
    onAcknowledgment: @Sendable (ReceivedFrame) -> Void
  ) async throws -> [ReceivedFrame]

}

extension DeviceNetwork: DirectMessageSending {

  public func sendDirect(
    _ message: DirectMessage,
    collectingFor duration: Duration,
    consent: SendConsent,
    onSending: @Sendable () -> Void,
    onAcknowledgment: @Sendable (ReceivedFrame) -> Void
  ) async throws -> [ReceivedFrame] {

    try await send(message, collectingFor: duration, consent: consent, onSending: onSending, onAcknowledgment: onAcknowledgment)

  }

}

/// `insteon modem send` and `insteon device ADDRESS send`: what they print, and in what order.
///
/// A line that says bytes are going out is printed once the send is allowed, so a refused send
/// prints only its refusal.
public enum RawSendFlow {

  /// Runs `insteon modem send`.
  ///
  /// - Parameters:
  ///   - request: The command.
  ///   - modem: What writes the command.
  ///   - output: Where the lines go.
  /// - Throws: A ``CommandFailure`` saying why a refused command wasn't written, or the
  ///   modem's error.
  public static func modemSend(_ request: RawSerialRequest, through modem: some RawCommandWriting, output: some CommandOutput) async throws {

    let received: [RawModemReply]

    do {

      received = try await modem.writeRaw(request.bytes, forcing: request.isForced, collectingFor: .seconds(request.waitSeconds)) {

        output.note("Writing \(Hex.pairs(request.bytes)) to the modem")

      }

    } catch let refusal as SendRefusal {

      throw CommandFailure(description: SendRefusalText.sentence(refusal, from: .modemSend))

    }

    for reply in received {

      output.line(text(of: reply))

    }

    if received.isEmpty {

      output.line("The modem sent nothing in \(request.waitSeconds) s.")

    }

  }

  /// Runs `insteon device ADDRESS send`.
  ///
  /// - Parameters:
  ///   - request: The message.
  ///   - device: The device.
  ///   - network: What sends the message.
  ///   - output: Where the lines go.
  /// - Throws: A ``CommandFailure`` saying why a refused message wasn't sent or that the
  ///   device rejected it, or the modem's error.
  public static func deviceSend(_ request: DirectMessageRequest, to device: InsteonAddress, through network: some DirectMessageSending, output: some CommandOutput) async throws {

    let message = DirectMessage(
      to: device,
      command1: request.command1,
      command2: request.command2,
      data: request.userData,
      hasChecksum: request.hasChecksum
    )

    let messages: [ReceivedFrame]

    do {

      // Listening starts before the message, so nothing the device sends is missed.
      messages = try await network.sendDirect(
        message,
        collectingFor: .seconds(request.waitSeconds),
        consent: request.consent,
        onSending: {

          output.note(sendingLine(for: message, to: device))

        },
        onAcknowledgment: { (acknowledgment: ReceivedFrame) -> Void in

          output.line("ACK: \(text(of: acknowledgment))")

        }
      )

    } catch let refusal as SendRefusal {

      throw CommandFailure(description: SendRefusalText.sentence(refusal, from: .deviceSend))

    } catch {

      guard case let .deviceRejected(_, reason)? = SendFailure(error) else {

        throw error

      }

      output.line("NAK: \(reason.summary) (cmd2 \(Hex.byte(reason.rawValue)))")

      throw CommandFailure(description: "\(device) rejected the message.")

    }

    for frame in messages {

      output.line(text(of: frame))

    }

    if messages.isEmpty {

      output.line("No other messages from \(device) in \(request.waitSeconds) s.")

    }

  }

  private static func sendingLine(for message: DirectMessage, to device: InsteonAddress) -> String {

    if let data = message.userData {

      return "Sending \(device) extended cmd1 \(Hex.byte(message.command1)) cmd2 \(Hex.byte(message.command2)), data \(Hex.pairs(data))"

    }

    return "Sending \(device) cmd1 \(Hex.byte(message.command1)) cmd2 \(Hex.byte(message.command2))"

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
