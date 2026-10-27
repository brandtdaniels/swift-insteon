/// Turns the bytes a device running IBIOS sends into ``IBIOSReply`` values.
///
/// Like ``ModemReplyParser``, it keeps any incomplete reply until the rest of its bytes arrive,
/// reports a NAK byte (`0x15`) where a reply would start as
/// ``IBIOSReply/negativeAcknowledgement``, and skips other bytes up to the next start byte
/// (`0x02`).
///
/// A NAK that follows a command's number, such as `02 48 15`, begins the same way as a reply
/// whose data starts with `0x15`, so it's reported once more bytes arrive. If no more bytes are
/// coming, ``IBIOSReplyParser/finishPendingReply()`` reports it.
public struct IBIOSReplyParser: Hashable, Sendable {

  private var pending: [UInt8] = []

  /// Creates a parser with no pending bytes.
  public init() {}

  /// Adds bytes received from the device and returns every reply they complete.
  ///
  /// - Parameter bytes: The next bytes received from the device.
  /// - Returns: The replies completed by these bytes, oldest first.
  public mutating func parse(_ bytes: some Sequence<UInt8>) -> [IBIOSReply] {

    pending.append(contentsOf: bytes)

    var replies: [IBIOSReply] = []

    while let reply = nextReply() {

      replies.append(reply)

    }

    return replies

  }

  /// Reports a NAK to a command that's waiting for more bytes, along with any replies after it.
  ///
  /// Call this once no more bytes are coming, for example when the reply has timed out.
  ///
  /// - Returns: The NAK's echo and the replies after it, or no replies if the pending bytes
  ///   don't start with such a NAK. Those bytes are kept.
  public mutating func finishPendingReply() -> [IBIOSReply] {

    guard
      pending.count >= 3,
      Self.echoedCommands.contains(pending[1]),
      pending[2] == Self.negativeAcknowledgement
    else {

      return []

    }

    let number = pending[1]
    pending.removeFirst(3)

    return [.echo(IBIOSEcho(number: number, parameters: [], isAccepted: false))] + parse([])

  }

  private mutating func nextReply() -> IBIOSReply? {

    // A NAK counts only where a reply can start, not among bytes being skipped.
    var isSkipping = false

    while true {

      if !isSkipping, pending.first == Self.negativeAcknowledgement {

        pending.removeFirst()

        return .negativeAcknowledgement

      }

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
        isSkipping = true
      case let .complete(length):
        // Every frame waits here for the rest of its bytes, whatever its type.
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

  private static let acknowledgement: UInt8 = 0x06

  private static let negativeAcknowledgement: UInt8 = 0x15

  private static let endOfText: UInt8 = 0x03

  /// The commands a host sends, which IBIOS echoes with an ACK or NAK.
  private static let echoedCommands: Set<UInt8> = [0x40, 0x42, 0x44, 0x46, 0x47, 0x48]

  /// Every number a frame from IBIOS can start with.
  private static let frameNumbers = echoedCommands.union([0x41, 0x43, 0x45, 0x49, 0x4A, 0x4F])

  /// The length of the frame at the start of `bytes`, which starts with `0x02`.
  private static func frameLength(of bytes: [UInt8]) -> FrameLength {

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
    if bytes.count >= 5, bytes[2] == negativeAcknowledgement, bytes[3] == 0x02, frameNumbers.contains(bytes[4]) {

      return .complete(3)

    }

    guard let length = echoLength(of: bytes) else {

      return .needMoreBytes

    }

    guard bytes.count >= length else {

      return .needMoreBytes

    }

    if isAcknowledgement(bytes[length - 1]) {

      return .complete(length)

    }

    return bytes[2] == negativeAcknowledgement ? .complete(3) : .unrecognized

  }

  /// The length of an echo, including its ACK or NAK, or `nil` until enough bytes arrive to
  /// tell.
  private static func echoLength(of bytes: [UInt8]) -> Int? {

    switch bytes[1] {
    case 0x40, 0x46: 7
    case 0x47: 5
    case 0x44, 0x48: 9
    // An upload's length is in its header.
    case 0x42: bytes.count >= 6 ? 9 + Int(UInt16(bytes[4]) << 8 | UInt16(bytes[5])) : nil
    default: nil
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
      guard let end = bytes.dropFirst(2).firstIndex(of: endOfText) else {

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

  private static func isAcknowledgement(_ byte: UInt8) -> Bool {

    byte == acknowledgement || byte == negativeAcknowledgement

  }

  private static func decode(_ frame: [UInt8]) -> IBIOSReply {

    let body = Array(frame.dropFirst(2))

    switch frame[1] {
    case 0x42 where body.last == acknowledgement:
      let data = Array(body[4..<(body.count - 3)])
      let checksum = UInt16(body[body.count - 3]) << 8 | UInt16(body[body.count - 2])

      return .memory(
        address: word(body, at: 0),
        data: data,
        isIntact: checksum == IBIOSCommand.checksum(of: body[0..<4] + data)
      )
    case 0x44 where body.last == acknowledgement:
      return .checksum(address: word(body, at: 0), length: word(body, at: 2), checksum: word(body, at: 4))
    case 0x48 where body.last == acknowledgement:
      return .version(ModemInfo(
        address: InsteonAddress(body[0], body[1], body[2]),
        category: DeviceCategory(rawValue: body[3]),
        subcategory: DeviceSubcategory(rawValue: body[4]),
        firmwareVersion: FirmwareVersion(rawValue: body[5])
      ))
    case 0x40, 0x42, 0x44, 0x46, 0x47, 0x48:
      // Rejected requests echo no data, and the other echoes repeat their parameters.
      let isAccepted = body.last == acknowledgement

      return .echo(IBIOSEcho(
        number: frame[1],
        parameters: isAccepted || frame.count > 3 ? Array(body.dropLast()) : [],
        isAccepted: isAccepted
      ))
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

      let message = Array(body.dropFirst())

      return .messageReceived(event, message: ReceivedMessage(
        sender: InsteonAddress(message[0], message[1], message[2]),
        destination: InsteonAddress(message[3], message[4], message[5]),
        flags: MessageFlags(rawValue: message[6]),
        command: Command(command1: message[7], command2: message[8]),
        // Exactly 14 bytes, so this never throws.
        userData: message.count == 23 ? try! UserData(Array(message[9..<23])) : nil
      ))
    }

  }

  private static func word(_ bytes: [UInt8], at index: Int) -> UInt16 {

    UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1])

  }

}
