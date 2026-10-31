/// Turns the bytes an Insteon modem sends into ``ModemReply`` values.
///
/// The parser keeps any incomplete reply until the rest of its bytes arrive, so feed it bytes
/// as you receive them, in any chunk size. A NAK byte (`0x15`) where a reply would start is
/// reported as ``ModemReply/negativeAcknowledgment``. Other bytes that don't start a
/// recognizable reply are skipped until the next start byte (`0x02`), NAK bytes among them,
/// and so is a start byte whose reply doesn't end in an ACK or NAK where one is expected.
///
/// A NAK to ``SerialCommand/getModemInfo``, ``SerialCommand/getModemConfiguration`` or
/// ``SerialCommand/readRadioStatus`` is reported once more bytes arrive, since until then it
/// can't be told apart from a reply whose data starts with `0x15`. A frame that starts right
/// after the NAK ends it, so the frame's bytes are never read as the reply's data. If no more
/// bytes are coming, ``ModemReplyParser/finishPendingReply()`` reports it.
///
/// ```swift
/// var parser = ModemReplyParser()
///
/// for reply in parser.parse(bytesFromModem) {
///   if case let .messageReceived(message) = reply {
///     // Handle a message from a device.
///   }
/// }
/// ```
public struct ModemReplyParser: ReplyParser, Hashable, Sendable {

  private var reader = FrameReader<ModemFraming>()

  /// Creates a parser with no pending bytes.
  public init() {}

  /// Adds bytes received from the modem and returns every reply they complete.
  ///
  /// - Parameter bytes: The next bytes received from the modem.
  /// - Returns: The replies completed by these bytes, oldest first.
  public mutating func parse(_ bytes: some Sequence<UInt8>) -> [ModemReply] {

    reader.read(bytes)

  }

  /// Reports a NAK to ``SerialCommand/getModemInfo``, ``SerialCommand/getModemConfiguration``
  /// or ``SerialCommand/readRadioStatus`` that's waiting for more bytes, along with any
  /// replies after it.
  ///
  /// The NAK (such as `02 60 15`) begins the same way as a reply whose data starts with
  /// `0x15`, so ``ModemReplyParser/parse(_:)`` waits for more bytes before reporting it. Call
  /// this once no more bytes are coming, for example when the reply has timed out.
  ///
  /// - Returns: The NAK's echo and the replies after it, or no replies if the pending bytes
  ///   don't start with such a NAK. Those bytes are kept.
  public mutating func finishPendingReply() -> [ModemReply] {

    let number = reader.takeShortNegativeAcknowledgment { byte -> SerialCommandNumber? in

      // Only these commands' NAKs are held back.
      switch SerialCommandNumber(rawValue: byte) {
      case .getModemInfo: .getModemInfo
      case .getModemConfiguration: .getModemConfiguration
      case .readRadioStatus: .readRadioStatus
      default: nil
      }

    }

    guard let number else {

      return []

    }

    return [.echo(CommandEcho(number: number, parameters: [], isAccepted: false))] + parse([])

  }

}

/// The frames of the Insteon modem (IM) serial protocol.
private enum ModemFraming: Framing {

  static let negativeAcknowledgment: ModemReply = .negativeAcknowledgment

  /// A host command's reply ends in an ACK or NAK, and so do the diagnostic and device record
  /// reports (`0x5A` and `0x5B`). Anything else means its start byte didn't begin a reply.
  static func isReply(_ frame: ArraySlice<UInt8>) -> Bool {

    let number = frame[frame.startIndex + 1]
    let endsInAnswer = frame.last.map { ControlByte.isAnswer($0) } == true

    if number == 0x5A || number == 0x5B {

      return endsInAnswer

    }

    return SerialCommandNumber(rawValue: number) == nil || endsInAnswer

  }

  /// The total length of the frame at the start of `bytes`, which starts with `0x02`.
  static func frameLength(of bytes: [UInt8]) -> FrameLength {

    guard bytes.count >= 2 else {

      return .needMoreBytes

    }

    switch bytes[1] {
    case 0x50: return .complete(11)
    case 0x51: return .complete(25)
    case 0x52: return .complete(4)
    case 0x53: return .complete(10)
    case 0x54: return .complete(3)
    case 0x55: return .complete(2)
    case 0x56: return .complete(7)
    case 0x57: return .complete(10)
    case 0x58: return .complete(3)
    case 0x59: return .complete(12)
    case 0x5A, 0x5B: return .complete(13)
    default:
      guard let number = SerialCommandNumber(rawValue: bytes[1]) else {

        return .unrecognized

      }

      return replyLength(to: number, in: bytes)
    }

  }

  /// The length of the modem's reply to a host command: the echo, or the data for commands
  /// that return data, then an ACK or NAK.
  private static func replyLength(to number: SerialCommandNumber, in bytes: [UInt8]) -> FrameLength {

    switch number {
    case .getModemInfo, .getModemConfiguration, .readRadioStatus:
      // A NAK can follow the number directly, but the data's first byte can also be 0x15, so
      // a full-length reply that ends in an ACK or NAK takes precedence.
      let dataLength = number == .getModemConfiguration ? 6 : 9

      // Unless the next frame starts right after the NAK: reading on would take that frame's
      // bytes as the reply's data, and its ACK-like byte as the reply's ACK. A reply whose
      // data happens to start the same way is then read as a NAK, so the command is sent
      // again rather than a made-up reply accepted.
      if bytes.count >= 5, bytes[2] == ControlByte.negativeAcknowledgment, bytes[3] == ControlByte.startOfText, startsFrame(bytes[4]) {

        return .complete(3)

      }

      guard bytes.count >= dataLength else {

        return bytes.count >= 3 && bytes[2] != ControlByte.negativeAcknowledgment ? .complete(dataLength) : .needMoreBytes

      }

      return .complete(ControlByte.isAnswer(bytes[dataLength - 1]) ? dataLength : 3)
    case .sendMessage:
      // The echoed message's flags say whether user data follows.
      guard bytes.count >= 6 else {

        return .needMoreBytes

      }

      return .complete(MessageFlags(rawValue: bytes[5]).isExtended ? 23 : 9)
    case .beep:
      // Later firmware echoes a parameter byte, which the form without one lacks.
      guard bytes.count >= 3 else {

        return .needMoreBytes

      }

      return .complete(ControlByte.isAnswer(bytes[2]) ? 3 : 4)
    default:
      // The rest are answered with their echo: the command as written, then an ACK or NAK.
      // Only 0x62 and 0x77 have no single length, and both are handled above.
      return .complete((number.commandLength ?? 2) + 1)
    }

  }

  /// Whether a number after a start byte begins a frame the modem sends: a report of its own,
  /// `0x50` through `0x5B`, or the reply to a host command.
  private static func startsFrame(_ number: UInt8) -> Bool {

    (0x50...0x5B).contains(number) || SerialCommandNumber(rawValue: number) != nil

  }

  static func decode(_ frame: [UInt8]) -> ModemReply {

    let body = Array(frame.dropFirst(2))

    switch frame[1] {
    case 0x50, 0x51:
      return .messageReceived(ReceivedMessage(reportedBytes: body))
    case 0x52:
      return .x10Received(X10Code(rawX10: body[0], flag: body[1]))
    case 0x53:
      // The other device's identity is valid only when the modem became its controller, and
      // its firmware byte is 0xFF from a device that answers the Product Data Request.
      let isController = body[0] == AllLinkMode.controller.rawValue

      return .allLinkingCompleted(AllLinkingCompleted(
        linkCode: body[0],
        group: AllLinkGroupNumber(rawValue: body[1]),
        address: address(body, at: 2),
        category: isController ? DeviceCategory(rawValue: body[5]) : nil,
        subcategory: isController ? DeviceSubcategory(rawValue: body[6]) : nil,
        firmwareVersion: isController && body[7] != 0xFF ? FirmwareVersion(rawValue: body[7]) : nil
      ))
    case 0x54:
      return .buttonEvent(ModemButtonEvent(rawValue: body[0]))
    case 0x55:
      return .userReset
    case 0x56:
      return .allLinkCleanupFailed(group: AllLinkGroupNumber(rawValue: body[1]), address: address(body, at: 2))
    case 0x57:
      return .allLinkRecord(AllLinkRecord(body, at: 0))
    case 0x58:
      return .allLinkCleanupStatus(isComplete: body[0] == ControlByte.acknowledgment)
    case 0x59:
      return .databaseRecord(address: UInt16(highByte: body[0], lowByte: body[1]), record: AllLinkRecord(body, at: 2))
    case 0x5A:
      return .diagnosticRecord(ModemDiagnosticRecord(body))
    case 0x5B:
      return .deviceRecordFound(address: UInt16(highByte: body[0], lowByte: body[1]), record: AllLinkRecord(body, at: 2))
    case 0x7E where body.count == 7 && body.last == ControlByte.acknowledgment:
      return .radioStatus(ModemRadioStatus(
        frequencyCode: body[0],
        radioFlags: body[1],
        lightFlags: body[2],
        hardwareVersion: body[3],
        reserved: [body[4], body[5]]
      ))
    case 0x60 where body.count == 7 && body.last == ControlByte.acknowledgment:
      return .modemInfo(ModemInfo(reportedBytes: Array(body.prefix(6))))
    case 0x73 where body.count == 4 && body.last == ControlByte.acknowledgment:
      return .modemConfiguration(ModemConfigurationReport(
        configuration: ModemConfiguration(rawValue: body[0]),
        applicationRetries: body[1],
        databaseDelta: body[2]
      ))
    case 0x60, 0x73, 0x7E:
      // A rejected request: these commands have no parameters to echo.
      return .echo(CommandEcho(
        // Only these numbers reach this case.
        number: SerialCommandNumber(rawValue: frame[1])!,
        parameters: [],
        isAccepted: false
      ))
    default:
      return .echo(CommandEcho(
        // Only recognized numbers reach `decode`, and all of them are host commands here.
        number: SerialCommandNumber(rawValue: frame[1])!,
        parameters: Array(body.dropLast()),
        isAccepted: body.last == ControlByte.acknowledgment
      ))
    }

  }

  private static func address(_ bytes: [UInt8], at index: Int) -> InsteonAddress {

    InsteonAddress(bytes[index], bytes[index + 1], bytes[index + 2])

  }

}
