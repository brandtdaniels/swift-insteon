/// The bytes that mark frames and answers in the serial protocols of Insteon modems and of
/// devices running IBIOS.
package enum ControlByte {

  /// Start of Text (`0x02`), the first byte of every frame.
  package static let startOfText = SerialCommand.startOfText

  /// End of Text (`0x03`), which ends an IBIOS text message.
  package static let endOfText: UInt8 = 0x03

  /// Acknowledge (`0x06`): the device accepted a command.
  package static let acknowledgment: UInt8 = 0x06

  /// Negative Acknowledge (`0x15`): the device rejected a command, usually because it was busy.
  package static let negativeAcknowledgment: UInt8 = 0x15

  /// Whether a byte ends an answer to a command: an ACK or a NAK.
  package static func isAnswer(_ byte: UInt8) -> Bool {

    byte == acknowledgment || byte == negativeAcknowledgment

  }

}

/// How long the frame at the start of some bytes is.
enum FrameLength {

  /// The frame is this many bytes long, though they may not all have arrived.
  case complete(Int)

  /// More bytes must arrive before the frame's length is known.
  case needMoreBytes

  /// The start byte doesn't begin a frame this protocol recognizes.
  case unrecognized

}

/// A serial protocol's frames: how long each one is, and what it means.
protocol Framing {

  /// What the device sends.
  associatedtype Reply

  /// The reply a lone NAK byte stands for, where a frame would start.
  static var negativeAcknowledgment: Reply { get }

  /// The length of the frame at the start of `bytes`, which start with ``ControlByte/startOfText``.
  static func frameLength(of bytes: [UInt8]) -> FrameLength

  /// Whether a complete frame is a reply, rather than a start byte that only looked like one.
  static func isReply(_ frame: ArraySlice<UInt8>) -> Bool

  /// The reply a complete frame carries.
  static func decode(_ frame: [UInt8]) -> Reply

}

extension Framing {

  static func isReply(_ frame: ArraySlice<UInt8>) -> Bool {

    true

  }

}

/// Splits the bytes a device sends into frames, keeping an incomplete one until the rest of its
/// bytes arrive.
///
/// A NAK byte where a frame would start is reported as ``Framing/negativeAcknowledgment``.
/// Other bytes that don't start a frame are skipped up to the next start byte, NAK bytes among
/// them.
struct FrameReader<Format: Framing>: Hashable, Sendable {

  /// Bytes received that haven't made a complete frame yet.
  private(set) var pending: [UInt8] = []

  /// Whether bytes are being skipped up to the next start byte, so a NAK byte among them isn't
  /// reported. It lasts from one read to the next, so how the bytes are split doesn't change
  /// what's reported.
  private var isSkipping = false

  /// Adds received bytes and returns every reply they complete, oldest first.
  mutating func read(_ bytes: some Sequence<UInt8>) -> [Format.Reply] {

    pending.append(contentsOf: bytes)

    var replies: [Format.Reply] = []

    while let reply = nextReply() {

      replies.append(reply)

    }

    return replies

  }

  /// Removes a NAK that directly follows a command's number, `02 <number> 15`, from the start of
  /// the pending bytes.
  ///
  /// - Parameter command: The command a number belongs to, or `nil` if it isn't one that can be
  ///   answered this way.
  /// - Returns: The command, or `nil` if the pending bytes don't start with such a NAK.
  mutating func takeShortNegativeAcknowledgment<Number>(of command: (UInt8) -> Number?) -> Number? {

    guard
      pending.count >= 3,
      pending[2] == ControlByte.negativeAcknowledgment,
      let number = command(pending[1])
    else {

      return nil

    }

    pending.removeFirst(3)
    isSkipping = false

    return number

  }

  /// Discards the pending bytes of a frame that stopped arriving before it was complete.
  ///
  /// Call this only once no bytes at all have arrived for a while, so the frame has truly
  /// stalled, such as one begun by line noise or missing bytes from its middle; a frame still
  /// arriving is never cut short. Its bytes are discarded whole, never read again as frames,
  /// so data inside it, such as a message's user data holding `02 50`, can't pass for a reply.
  /// The next byte to arrive starts afresh.
  ///
  /// - Returns: Whether any bytes were discarded.
  @discardableResult
  mutating func discardStalledFrame() -> Bool {

    guard !pending.isEmpty else {

      return false

    }

    pending.removeAll()
    isSkipping = false

    return true

  }

  private mutating func nextReply() -> Format.Reply? {

    // A NAK counts only where a frame can start, not among bytes being skipped.
    while true {

      // A device sometimes answers a command with a lone NAK instead of an echo.
      if !isSkipping, pending.first == ControlByte.negativeAcknowledgment {

        pending.removeFirst()

        return Format.negativeAcknowledgment

      }

      guard let start = pending.firstIndex(of: ControlByte.startOfText) else {

        // These bytes start no frame, and neither do the bytes up to the next start byte.
        isSkipping = isSkipping || !pending.isEmpty
        pending.removeAll()

        return nil

      }

      pending.removeFirst(start)
      isSkipping = false

      switch Format.frameLength(of: pending) {
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

        guard Format.isReply(pending.prefix(length)) else {

          pending.removeFirst()
          isSkipping = true

          continue

        }

        let frame = Array(pending.prefix(length))
        pending.removeFirst(length)

        return Format.decode(frame)
      }

    }

  }

}
