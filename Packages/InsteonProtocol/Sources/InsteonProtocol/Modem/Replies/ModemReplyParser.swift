/// Turns the bytes an INSTEON modem sends into ``ModemReply`` values.
///
/// The parser keeps any incomplete reply until the rest of its bytes arrive, so feed it bytes
/// as you receive them, in any chunk size. Bytes that don't start a recognizable reply are
/// skipped until the next start byte (`0x02`).
///
/// ```swift
/// var cursor = HubBufferCursor()
/// var parser = ModemReplyParser()
///
/// for reply in parser.parse(cursor.advance(to: try await hub.readBuffer())) {
///   if case let .messageReceived(message) = reply {
///     // Handle a message from a device.
///   }
/// }
/// ```
public struct ModemReplyParser: Hashable, Sendable {

  private var pending: [UInt8] = []

  /// Creates a parser with no pending bytes.
  public init() {}

  /// Adds bytes received from the modem and returns every reply they complete.
  ///
  /// - Parameter bytes: The next bytes received from the modem.
  /// - Returns: The replies completed by these bytes, oldest first.
  public mutating func parse(_ bytes: some Sequence<UInt8>) -> [ModemReply] {

    pending.append(contentsOf: bytes)

    var replies: [ModemReply] = []

    while let reply = nextReply() {

      replies.append(reply)

    }

    return replies

  }

  private mutating func nextReply() -> ModemReply? {

    while true {

      guard let start = pending.firstIndex(of: SerialCommand.startOfText) else {

        pending.removeAll()

        return nil

      }

      pending.removeFirst(start)

      switch Self.frameLength(of: pending) {
      case .needMoreBytes:
        return nil
      case .unrecognized:
        pending.removeFirst()
      case let .complete(length):
        guard pending.count >= length else {

          return nil

        }

        let frame = Array(pending.prefix(length))
        pending.removeFirst(length)

        return Self.decode(frame)
      }

    }

  }

  private enum FrameLength {

    case complete(Int)

    case needMoreBytes

    case unrecognized

  }

  /// The number of parameter bytes each host command has, which its echo repeats.
  private static let echoParameterCounts: [UInt8: Int] = [
    0x61: 3, 0x63: 2, 0x64: 2, 0x65: 0, 0x66: 3, 0x67: 0, 0x68: 1, 0x69: 0, 0x6A: 0,
    0x6B: 1, 0x6C: 0, 0x6D: 0, 0x6E: 0, 0x6F: 9, 0x70: 1, 0x71: 2, 0x72: 0, 0x74: 0,
    0x75: 2, 0x76: 10, 0x77: 0, 0x7A: 1
  ]

  /// The total length of the frame at the start of `bytes`, which starts with `0x02`.
  private static func frameLength(of bytes: [UInt8]) -> FrameLength {

    guard bytes.count >= 2 else {

      return .needMoreBytes

    }

    let number = bytes[1]

    switch number {
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
    case 0x60, 0x73:
      // A NAK to these requests carries no data.
      guard bytes.count >= 3 else {

        return .needMoreBytes

      }

      if bytes[2] == negativeAcknowledgement {

        return .complete(3)

      }

      return .complete(number == 0x60 ? 9 : 6)
    case 0x62:
      // The echoed message's flags say whether user data follows.
      guard bytes.count >= 6 else {

        return .needMoreBytes

      }

      return .complete(MessageFlags(rawValue: bytes[5]).isExtended ? 23 : 9)
    default:
      guard let parameterCount = echoParameterCounts[number] else {

        return .unrecognized

      }

      return .complete(2 + parameterCount + 1)
    }

  }

  private static let acknowledgement: UInt8 = 0x06

  private static let negativeAcknowledgement: UInt8 = 0x15

  private static func decode(_ frame: [UInt8]) -> ModemReply {

    let body = Array(frame.dropFirst(2))

    switch frame[1] {
    case 0x50, 0x51:
      return .messageReceived(ReceivedMessage(
        sender: address(body, at: 0),
        destination: address(body, at: 3),
        flags: MessageFlags(rawValue: body[6]),
        command: Command(command1: body[7], command2: body[8]),
        // Exactly 14 bytes, so this never throws.
        userData: frame[1] == 0x51 ? try! UserData(Array(body[9..<23])) : nil
      ))
    case 0x52:
      return .x10Received(X10Code(rawX10: body[0], flag: body[1]))
    case 0x53:
      return .allLinkingCompleted(AllLinkingCompleted(
        linkCode: body[0],
        group: body[1],
        address: address(body, at: 2),
        category: body[5],
        subcategory: body[6],
        firmwareVersion: body[7]
      ))
    case 0x54:
      return .buttonEvent(body[0])
    case 0x55:
      return .userReset
    case 0x56:
      return .allLinkCleanupFailed(group: body[1], address: address(body, at: 2))
    case 0x57:
      return .allLinkRecord(record(body, at: 0))
    case 0x58:
      return .allLinkCleanupStatus(isComplete: body[0] == acknowledgement)
    case 0x59:
      return .databaseRecord(address: UInt16(body[0]) << 8 | UInt16(body[1]), record: record(body, at: 2))
    case 0x60 where body.last == acknowledgement && body.count == 7:
      return .modemInfo(ModemInfo(
        address: address(body, at: 0),
        category: body[3],
        subcategory: body[4],
        firmwareVersion: body[5]
      ))
    case 0x73 where body.last == acknowledgement && body.count == 4:
      return .modemConfiguration(ModemConfigurationReport(
        configuration: ModemConfiguration(rawValue: body[0]),
        applicationRetries: body[1],
        databaseDelta: body[2]
      ))
    default:
      return .echo(CommandEcho(
        // Only recognized numbers reach `decode`, and all of them are host commands here.
        number: SerialCommandNumber(rawValue: frame[1])!,
        parameters: Array(body.dropLast()),
        isAccepted: body.last == acknowledgement
      ))
    }

  }

  private static func address(_ bytes: [UInt8], at index: Int) -> InsteonAddress {

    InsteonAddress(bytes[index], bytes[index + 1], bytes[index + 2])

  }

  private static func record(_ bytes: [UInt8], at index: Int) -> AllLinkRecord {

    AllLinkRecord(
      flags: AllLinkRecordFlags(rawValue: bytes[index]),
      group: bytes[index + 1],
      address: address(bytes, at: index + 2),
      data1: bytes[index + 5],
      data2: bytes[index + 6],
      data3: bytes[index + 7]
    )

  }

}
