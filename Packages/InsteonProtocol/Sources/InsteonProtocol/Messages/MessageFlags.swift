/// The flags byte that follows the addresses in every Insteon message.
///
/// The byte packs four fields:
///
/// | Bits | Field |
/// | --- | --- |
/// | 7–5 | ``MessageFlags/messageType`` |
/// | 4 | ``MessageFlags/isExtended`` |
/// | 3–2 | ``MessageFlags/hopsLeft`` |
/// | 1–0 | ``MessageFlags/maxHops`` |
///
/// For example, ``MessageFlags/direct`` is `0x0F`: a standard-length direct message that other devices
/// may repeat up to three times.
public struct MessageFlags: Hashable, Sendable {

  /// The kind of an Insteon message, from bits 7–5 of the flags byte.
  public enum MessageType: UInt8, CaseIterable, Hashable, Sendable {

    /// A message addressed to a single device.
    case direct = 0b000

    /// A device's acknowledgement of a direct message.
    case directAcknowledgement = 0b001

    /// A direct follow-up to an ALL-Link broadcast, sent to each member of the group in turn.
    case allLinkCleanup = 0b010

    /// A device's acknowledgement of an ALL-Link cleanup message.
    case allLinkCleanupAcknowledgement = 0b011

    /// A message for every device that hears it; the destination address carries other data.
    case broadcast = 0b100

    /// A device's negative acknowledgement of a direct message.
    case directNegativeAcknowledgement = 0b101

    /// A message for the members of an ALL-Link group; the destination's low byte is the group.
    case allLinkBroadcast = 0b110

    /// A device's negative acknowledgement of an ALL-Link cleanup message.
    case allLinkCleanupNegativeAcknowledgement = 0b111

  }

  /// How many times a message may be retransmitted by other devices, from 0 to 3.
  public enum HopCount: UInt8, CaseIterable, Comparable, Hashable, Sendable {

    /// The message is not retransmitted.
    case zero = 0

    /// The message may be retransmitted once.
    case one = 1

    /// The message may be retransmitted twice.
    case two = 2

    /// The message may be retransmitted three times, the protocol maximum.
    case three = 3

    /// Orders hop counts by their numeric value.
    ///
    /// - Parameters:
    ///   - lhs: A hop count.
    ///   - rhs: Another hop count.
    /// - Returns: `true` if `lhs` is fewer hops than `rhs`.
    public static func < (lhs: HopCount, rhs: HopCount) -> Bool {

      lhs.rawValue < rhs.rawValue

    }

  }

  /// The kind of message.
  public var messageType: MessageType

  /// Whether the message is extended-length, carrying 14 bytes of user data.
  public var isExtended: Bool

  /// The number of retransmissions remaining. Repeating devices decrement it.
  public var hopsLeft: HopCount

  /// The number of retransmissions the sender allowed.
  public var maxHops: HopCount

  /// Creates message flags.
  ///
  /// - Parameters:
  ///   - messageType: The kind of message.
  ///   - isExtended: Whether the message carries 14 bytes of user data.
  ///   - maxHops: The number of retransmissions to allow.
  ///   - hopsLeft: The number of retransmissions remaining. Defaults to `maxHops`, as for a
  ///     message that has not been retransmitted yet, and is limited to `maxHops`.
  public init(
    messageType: MessageType,
    isExtended: Bool = false,
    maxHops: HopCount = .three,
    hopsLeft: HopCount? = nil
  ) {

    self.messageType = messageType
    self.isExtended = isExtended
    self.maxHops = maxHops
    self.hopsLeft = min(hopsLeft ?? maxHops, maxHops)

  }

  /// Standard-length direct flags with three hops: `0x0F`.
  public static let direct = MessageFlags(messageType: .direct)

  /// Extended-length direct flags with three hops: `0x1F`.
  public static let extendedDirect = MessageFlags(messageType: .direct, isExtended: true)

}

// MARK: - RawRepresentable

extension MessageFlags: RawRepresentable {

  /// Decodes a flags byte. Every byte value is valid.
  ///
  /// - Parameter rawValue: The flags byte.
  public init(rawValue: UInt8) {

    // Every 3-bit and 2-bit pattern has a case, so these can't fail.
    messageType = MessageType(rawValue: rawValue >> 5)!
    isExtended = rawValue & 0b0001_0000 != 0
    hopsLeft = HopCount(rawValue: (rawValue >> 2) & 0b11)!
    maxHops = HopCount(rawValue: rawValue & 0b11)!

  }

  /// The encoded flags byte.
  public var rawValue: UInt8 {

    messageType.rawValue << 5
      | (isExtended ? 0b0001_0000 : 0)
      | hopsLeft.rawValue << 2
      | maxHops.rawValue

  }

}
