/// Turns the bytes an INSTEON modem sends into ``ModemReply`` values.
///
/// The parser keeps any incomplete reply until the rest of its bytes arrive, so feed it bytes
/// as you receive them, in any chunk size. A NAK byte (`0x15`) between replies is reported
/// as ``ModemReply/negativeAcknowledgement``. Other bytes that don't start a recognizable
/// reply are skipped until the next start byte (`0x02`), and so is a start byte whose reply
/// doesn't end in an ACK or NAK where one is expected.
///
/// A NAK to ``SerialCommand/getModemInfo`` or ``SerialCommand/getModemConfiguration`` is
/// reported once more bytes arrive, since until then it can't be told apart from a reply whose
/// data starts with `0x15`.
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

      guard let start = pending.firstIndex(where: { $0 == SerialCommand.startOfText || $0 == Self.negativeAcknowledgement }) else {

        pending.removeAll()

        return nil

      }

      pending.removeFirst(start)

      // The modem sometimes answers a command with a lone NAK instead of an echo.
      if pending[0] == Self.negativeAcknowledgement {

        pending.removeFirst()

        return .negativeAcknowledgement

      }

      switch Self.frameLength(of: pending) {
      case .needMoreBytes:
        return nil
      case .unrecognized:
        pending.removeFirst()
      case let .complete(length):
        guard pending.count >= length else {

          return nil

        }

        // A host command's reply ends in an ACK or NAK. Anything else means this start byte
        // didn't begin a reply, so look for the next one.
        guard SerialCommandNumber(rawValue: pending[1]) == nil || Self.isAcknowledgement(pending[length - 1]) else {

          pending.removeFirst()
          continue

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

  /// The total length of the frame at the start of `bytes`, which starts with `0x02`.
  private static func frameLength(of bytes: [UInt8]) -> FrameLength {

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
    case .getModemInfo, .getModemConfiguration:
      // A NAK can follow the number directly, but the data's first byte can also be 0x15, so
      // a full-length reply that ends in an ACK or NAK takes precedence.
      let dataLength = number == .getModemInfo ? 9 : 6

      guard bytes.count >= dataLength else {

        return bytes.count >= 3 && bytes[2] != negativeAcknowledgement ? .complete(dataLength) : .needMoreBytes

      }

      return .complete(isAcknowledgement(bytes[dataLength - 1]) ? dataLength : 3)
    case .sendMessage:
      // The echoed message's flags say whether user data follows.
      guard bytes.count >= 6 else {

        return .needMoreBytes

      }

      return .complete(MessageFlags(rawValue: bytes[5]).isExtended ? 23 : 9)
    case .cancelAllLinking, .resetModem, .getFirstAllLinkRecord, .getNextAllLinkRecord,
         .getAllLinkRecordForSender, .ledOn, .ledOff, .rfSleep, .cancelCleanup, .beep:
      return .complete(3)
    case .setAcknowledgementByte, .setModemConfiguration, .setNegativeAcknowledgementByte,
         .setApplicationRetries:
      return .complete(4)
    case .sendX10, .startAllLinking, .setAcknowledgementBytes, .readDatabase:
      return .complete(5)
    case .sendAllLinkCommand, .setHostDeviceCategory, .setResponderLinkData:
      return .complete(6)
    case .manageAllLinkRecord:
      return .complete(12)
    case .writeDatabase:
      return .complete(13)
    }

  }

  private static func isAcknowledgement(_ byte: UInt8) -> Bool {

    byte == acknowledgement || byte == negativeAcknowledgement

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
        category: DeviceCategory(rawValue: body[5]),
        subcategory: body[6],
        firmwareVersion: body[7]
      ))
    case 0x54:
      return .buttonEvent(ModemButtonEvent(rawValue: body[0]))
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
    case 0x60 where body.count == 7 && body.last == acknowledgement:
      return .modemInfo(ModemInfo(
        address: address(body, at: 0),
        category: DeviceCategory(rawValue: body[3]),
        subcategory: body[4],
        firmwareVersion: body[5]
      ))
    case 0x73 where body.count == 4 && body.last == acknowledgement:
      return .modemConfiguration(ModemConfigurationReport(
        configuration: ModemConfiguration(rawValue: body[0]),
        applicationRetries: body[1],
        databaseDelta: body[2]
      ))
    case 0x60, 0x73:
      // A rejected request: these commands have no parameters to echo.
      return .echo(CommandEcho(
        number: frame[1] == 0x60 ? .getModemInfo : .getModemConfiguration,
        parameters: [],
        isAccepted: false
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
