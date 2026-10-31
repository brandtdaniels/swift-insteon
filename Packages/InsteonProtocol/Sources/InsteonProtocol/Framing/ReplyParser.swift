/// Turns the bytes a device sends over a serial connection into replies, as they arrive.
///
/// ``ModemReplyParser`` parses the replies of an Insteon modem, and ``IBIOSReplyParser`` those
/// of a device running IBIOS. Feed a parser bytes in any chunk size: it keeps an incomplete reply
/// until the rest of its bytes arrive.
public protocol ReplyParser: Sendable {

  /// What the device sends.
  associatedtype Reply: Sendable

  /// Adds bytes received from the device and returns every reply they complete.
  ///
  /// - Parameter bytes: The next bytes received from the device.
  /// - Returns: The replies completed by these bytes, oldest first.
  mutating func parse(_ bytes: some Sequence<UInt8>) -> [Reply]

  /// Reports a reply held back because it can't yet be told apart from a longer one, along
  /// with any replies after it.
  ///
  /// Call this once no more bytes are coming, for example when a reply has timed out.
  ///
  /// - Returns: The held-back reply and the replies after it, or no replies if nothing is held
  ///   back.
  mutating func finishPendingReply() -> [Reply]

  /// Discards the pending bytes of a frame that stopped arriving before it was complete.
  ///
  /// Call this only once the frame has stalled, such as when no bytes at all have arrived for
  /// a while, so a frame still arriving is never cut short. The bytes are discarded whole
  /// rather than read again as frames.
  ///
  /// - Returns: Whether any bytes were discarded.
  @discardableResult
  mutating func discardStalledFrame() -> Bool

  /// Where the frame the parser is waiting on starts, as a count of the bytes received before
  /// it, or `nil` if it isn't waiting on one. The same position later means the same frame is
  /// still incomplete.
  var pendingFrameStart: Int? { get }

  /// Tells the parser the command about to be written, for frames read only as answers to
  /// what was written.
  ///
  /// - Parameter command: The command's bytes.
  /// - Returns: The replies the pending bytes complete, read as answers to this command.
  mutating func willWrite(_ command: [UInt8]) -> [Reply]

}

extension ReplyParser {

  /// Keeps the pending bytes, for a parser whose frames can't stall.
  ///
  /// - Returns: `false`.
  @discardableResult
  public mutating func discardStalledFrame() -> Bool {

    false

  }

  /// Reads every frame the same whatever was written.
  ///
  /// - Returns: No replies.
  public mutating func willWrite(_ command: [UInt8]) -> [Reply] {

    []

  }

  /// No frame, for a parser whose frames can't stall.
  public var pendingFrameStart: Int? {

    nil

  }

}
