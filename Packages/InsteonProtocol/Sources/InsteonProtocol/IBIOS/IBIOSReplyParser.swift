/// Turns the bytes a device running IBIOS sends into ``IBIOSReply`` values.
///
/// Like ``ModemReplyParser``, it keeps any incomplete reply until the rest of its bytes arrive,
/// reports a NAK byte (`0x15`) where a reply would start as
/// ``IBIOSReply/negativeAcknowledgment``, and skips other bytes up to the next start byte
/// (`0x02`).
///
/// A NAK that follows a command's number, such as `02 48 15`, begins the same way as a reply
/// whose data starts with `0x15`, so it's reported once more bytes arrive. If no more bytes are
/// coming, ``IBIOSReplyParser/finishPendingReply()`` reports it.
public struct IBIOSReplyParser: ReplyParser, Hashable, Sendable {

  private var reader = FrameReader<IBIOSFraming>()

  /// Creates a parser with no pending bytes.
  public init() {}

  /// Adds bytes received from the device and returns every reply they complete.
  ///
  /// - Parameter bytes: The next bytes received from the device.
  /// - Returns: The replies completed by these bytes, oldest first.
  public mutating func parse(_ bytes: some Sequence<UInt8>) -> [IBIOSReply] {

    reader.read(bytes)

  }

  /// Reports a NAK to a command that's waiting for more bytes, along with any replies after it.
  ///
  /// Call this once no more bytes are coming, for example when the reply has timed out.
  ///
  /// - Returns: The NAK's echo and the replies after it, or no replies if the pending bytes
  ///   don't start with such a NAK. Those bytes are kept.
  public mutating func finishPendingReply() -> [IBIOSReply] {

    guard let number = reader.takeShortNegativeAcknowledgment(of: IBIOSCommandNumber.init(rawValue:)) else {

      return []

    }

    return [.echo(IBIOSEcho(number: number, parameters: [], isAccepted: false))] + parse([])

  }

}

/// The frames of the IBIOS serial protocol.
private enum IBIOSFraming: Framing {

  static let negativeAcknowledgment: IBIOSReply = .negativeAcknowledgment

  /// The commands a host sends, which IBIOS echoes with an ACK or NAK.
  static let echoedCommands = Set(IBIOSCommandNumber.allCases.map(\.rawValue))

  /// Every number a frame from IBIOS can start with.
  private static let frameNumbers = echoedCommands.union([0x41, 0x43, 0x45, 0x49, 0x4A, 0x4F])

  /// The length of the frame at the start of `bytes`, which starts with `0x02`.
  static func frameLength(of bytes: [UInt8]) -> FrameLength {

    guard bytes.count >= 2 else {

      return .needMoreBytes

    }

    let number = bytes[1]

    guard echoedCommands.contains(number) else {

      return reportLength(of: bytes)

    }

    // An echo of `0x02`, the number and a NAK can't be told apart from an echo whose first
    // parameter is 0x15 until the full echo would have arrived, unless the next frame starts
    // right after the NAK. Reading on would take that frame's bytes as the echo's.
    if bytes.count >= 5, bytes[2] == ControlByte.negativeAcknowledgment, bytes[3] == ControlByte.startOfText, frameNumbers.contains(bytes[4]) {

      return .complete(3)

    }

    guard let length = echoLength(of: bytes) else {

      return .needMoreBytes

    }

    guard bytes.count >= length else {

      return .needMoreBytes

    }

    if ControlByte.isAnswer(bytes[length - 1]) {

      return .complete(length)

    }

    return bytes[2] == ControlByte.negativeAcknowledgment ? .complete(3) : .unrecognized

  }

  /// The length of an echo, including its ACK or NAK, or `nil` until enough bytes arrive to
  /// tell.
  private static func echoLength(of bytes: [UInt8]) -> Int? {

    switch IBIOSCommandNumber(rawValue: bytes[1]) {
    case .download, .mask: 7
    case .simulateEvent: 5
    case .getChecksum, .getVersion: 9
    // An upload's length is in its header.
    case .upload: bytes.count >= 6 ? 9 + Int(UInt16(highByte: bytes[4], lowByte: bytes[5])) : nil
    case nil: nil
    }

  }

  /// The length of a report the device sends on its own.
  private static func reportLength(of bytes: [UInt8]) -> FrameLength {

    switch bytes[1] {
    case 0x45:
      return .complete(3)
    case 0x49, 0x4A:
      return .complete(4)
    case 0x41:
      guard bytes.count >= 3 else {

        return .needMoreBytes

      }

      return .complete(3 + Int(bytes[2]))
    case 0x43:
      guard let end = bytes.dropFirst(2).firstIndex(of: ControlByte.endOfText) else {

        return .needMoreBytes

      }

      return .complete(end + 1)
    case 0x4F:
      guard bytes.count >= 3 else {

        return .needMoreBytes

      }

      // A message that wasn't acknowledged is reported without one.
      if bytes[2] == IBIOSEvent.sendNotAcknowledged.rawValue {

        return .complete(3)

      }

      // The message's flags, after its two addresses, say whether user data follows.
      guard bytes.count >= 10 else {

        return .needMoreBytes

      }

      return .complete(MessageFlags(rawValue: bytes[9]).isExtended ? 26 : 12)
    default:
      return .unrecognized
    }

  }

  static func decode(_ frame: [UInt8]) -> IBIOSReply {

    let body = Array(frame.dropFirst(2))

    if let number = IBIOSCommandNumber(rawValue: frame[1]) {

      let isAccepted = body.last == ControlByte.acknowledgment

      switch number {
      case .upload where isAccepted:
        let data = Array(body[4..<(body.count - 3)])
        let checksum = UInt16(highByte: body[body.count - 3], lowByte: body[body.count - 2])

        return .memory(
          address: word(body, at: 0),
          data: data,
          isIntact: checksum == IBIOSCommand.checksum(of: body[0..<4] + data)
        )
      case .getChecksum where isAccepted:
        return .checksum(address: word(body, at: 0), length: word(body, at: 2), checksum: word(body, at: 4))
      case .getVersion where isAccepted:
        return .version(ModemInfo(reportedBytes: Array(body.prefix(6))))
      default:
        // Rejected requests echo no data, and the other echoes repeat their parameters.
        return .echo(IBIOSEcho(
          number: number,
          parameters: isAccepted || frame.count > 3 ? Array(body.dropLast()) : [],
          isAccepted: isAccepted
        ))
      }

    }

    switch frame[1] {
    case 0x45:
      return .eventReport(IBIOSEvent(rawValue: body[0]))
    case 0x49:
      return .debugReport(address: word(body, at: 0))
    case 0x4A:
      return .x10Received(X10Code(rawX10: body[1], flag: body[0] == 0x01 ? 0x80 : 0x00))
    case 0x41:
      return .data(Array(body.dropFirst()))
    case 0x43:
      return .text(String(decoding: body.dropLast(), as: UTF8.self))
    default:
      // 0x4F, the only other number `frameLength` recognizes.
      let event = IBIOSEvent(rawValue: body[0])

      guard body.count > 1 else {

        return .messageReceived(event, message: nil)

      }

      return .messageReceived(event, message: ReceivedMessage(reportedBytes: Array(body.dropFirst())))
    }

  }

  private static func word(_ bytes: [UInt8], at index: Int) -> UInt16 {

    UInt16(highByte: bytes[index], lowByte: bytes[index + 1])

  }

}
