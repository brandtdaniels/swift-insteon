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
/// bytes are coming, ``ModemReplyParser/finishPendingReply()`` reports it. A frame that stops
/// arriving partway is discarded with ``ModemReplyParser/discardStalledFrame()``.
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

  /// Discards the pending bytes of a frame that stopped arriving before it was complete, such
  /// as one begun by line noise or missing bytes from its middle, which would otherwise take
  /// the replies after it as the rest of its bytes.
  ///
  /// Call this only once the frame has stalled, such as when no bytes at all have arrived for
  /// a while, or when it was already pending before a command that has since timed out: a
  /// frame still arriving is never cut short. Its bytes are discarded whole rather than read
  /// again as frames, so data inside it can't pass for a reply.
  ///
  /// - Returns: Whether any bytes were discarded.
  @discardableResult
  public mutating func discardStalledFrame() -> Bool {

    reader.discardStalledFrame()

  }

  /// Where the frame the parser is waiting on starts, as a count of the bytes received before
  /// it, or `nil` if it isn't waiting on one.
  ///
  /// The same position later means the same frame is still incomplete, such as one that was
  /// pending before a command was written and is still pending when its answer times out.
  public var pendingFrameStart: Int? {

    reader.pendingFrameStart

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

  /// The length of each report the modem sends of its own, by number. A frame starts with one of
  /// these numbers or with the number of a reply to a host command, and `startsFrame` reads this
  /// same table, so the two can't drift apart. `0x56` is 7 bytes here, but its length is decided
  /// by `cleanupFailureLength(of:)`.
  ///
  /// `0x5C` is seen once in a Hub's buffer and not in a cited document. Its 11 bytes (`02 5C`
  /// and 9 more) are inferred from that one bench trace, whose byte counts fit exactly: 17 bytes
  /// for the `5C` frame and the 6-byte failure report after it, then 14 for the status report and
  /// a standard message. A byte after the frame that isn't a start byte is skipped up to the next
  /// start byte, so a wrong length costs only the frame it swallows. Unverified.
  private static let reportLengths: [UInt8: Int] = [
    0x50: 11, 0x51: 25, 0x52: 4, 0x53: 10, 0x54: 3, 0x55: 2, 0x56: 7, 0x57: 10, 0x58: 3,
    0x59: 12, 0x5A: 13, 0x5B: 13, 0x5C: 11
  ]

  /// The total length of the frame at the start of `bytes`, which starts with `0x02`.
  static func frameLength(of bytes: [UInt8], after written: [UInt8]?) -> FrameLength {

    guard bytes.count >= 2 else {

      return .needMoreBytes

    }

    if bytes[1] == 0x56 {

      return cleanupFailureLength(of: bytes)

    }

    if let length = reportLengths[bytes[1]] {

      return .complete(length)

    }

    switch bytes[1] {
    default:
      guard let number = SerialCommandNumber(rawValue: bytes[1]) else {

        return .unrecognized

      }

      return replyLength(to: number, in: bytes)
    }

  }

  /// The length of an ALL-Link Cleanup Failure Report: 7 bytes, `02 56 <reserved> <group> <address>`,
  /// the layout the parser was written for, or 6 bytes, `02 56 <group> <address>`, as the bench
  /// Hub 2 sends it (a hardware observation; unverified against a document).
  ///
  /// The two can't be told apart by their start, so the frame is read as 7 bytes unless the
  /// 7th byte starts the next frame, a start byte followed by a number a modem sends. An address
  /// that ends in a start byte doesn't, since the frame after it starts with another start byte.
  /// A 7th byte that is a start byte waits for the byte after it.
  private static func cleanupFailureLength(of bytes: [UInt8]) -> FrameLength {

    guard bytes.count >= 7 else {

      return .needMoreBytes

    }

    guard bytes[6] == ControlByte.startOfText else {

      return .complete(7)

    }

    guard bytes.count >= 8 else {

      return .needMoreBytes

    }

    return .complete(startsFrame(bytes[7]) ? 6 : 7)

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
  /// one in `reportLengths`, or the reply to a host command.
  private static func startsFrame(_ number: UInt8) -> Bool {

    reportLengths[number] != nil || SerialCommandNumber(rawValue: number) != nil

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
    case 0x56 where frame.count == 6:
      return .allLinkCleanupFailed(group: AllLinkGroupNumber(rawValue: body[0]), address: address(body, at: 1))
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
    case 0x5C:
      return .unrecognized(number: frame[1], body: body)
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
