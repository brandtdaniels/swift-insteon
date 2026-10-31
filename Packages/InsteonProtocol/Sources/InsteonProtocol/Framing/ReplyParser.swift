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
  /// with any replies after it, or gives up on a frame that never finished.
  ///
  /// Call this once no more bytes are coming, for example when a reply has timed out. A frame
  /// that never finished, such as one begun by line noise, loses its start byte, so the bytes
  /// after it are read afresh.
  ///
  /// - Returns: The held-back reply and the replies after it, or the replies in the bytes after
  ///   the dropped start byte.
  mutating func finishPendingReply() -> [Reply]

}
