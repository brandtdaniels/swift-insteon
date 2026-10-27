/// Tracks how far the Hub's buffer has been read, so each read returns only new bytes.
///
/// Clear the buffer before the first read, so earlier replies aren't returned as new:
///
/// ```swift
/// try await hub.clearBuffer()
/// var cursor = HubBufferCursor()
///
/// while true {
///   let received = cursor.advance(to: try await hub.readBuffer())
///   // Parse the modem's replies in `received`.
/// }
/// ```
///
/// The cursor tracks one reader. If another client clears the buffer and the modem then writes
/// past the cursor's position, the cursor can't tell, and the bytes before its position are
/// missed; have one client read a Hub's buffer at a time.
public struct HubBufferCursor: Hashable, Sendable {

  private var position = 0

  /// Creates a cursor at the start of the buffer, as after ``Hub/clearBuffer()``.
  public init() {}

  /// Returns the bytes written since the last call, and moves the cursor past them.
  ///
  /// Bytes that wrapped around the end of the ring buffer are returned in the order they were
  /// written. A buffer of all zeros is treated as just cleared and resets the cursor, and so is
  /// a buffer that's all zeros from its end position on, since a wrap would leave the previous
  /// pass's bytes there.
  ///
  /// - Parameter buffer: The latest buffer read from the Hub.
  /// - Returns: The bytes written since the previous call, oldest first.
  public mutating func advance(to buffer: HubBuffer) -> [UInt8] {

    guard buffer.bytes.contains(where: { $0 != 0 }) else {

      reset()

      return []

    }

    let start = min(position, buffer.bytes.count)
    let end = buffer.endIndex

    position = end

    if end > start {

      return Array(buffer.bytes[start..<end])

    }

    if end < start {

      // Zeros everywhere after the end position mean the buffer was cleared and refilled, not
      // wrapped: only the bytes before the end position are new.
      guard buffer.bytes[end...].contains(where: { $0 != 0 }) else {

        return Array(buffer.bytes[..<end])

      }

      return Array(buffer.bytes[start...]) + buffer.bytes[..<end]

    }

    return []

  }

  /// Moves the cursor back to the start of the buffer. Call this after clearing the buffer.
  public mutating func reset() {

    position = 0

  }

}
