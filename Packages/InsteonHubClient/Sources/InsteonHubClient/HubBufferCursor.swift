/// Tracks how far the Hub's buffer has been read, so each read returns only new bytes.
///
/// ```swift
/// var cursor = HubBufferCursor()
///
/// while true {
///   let received = cursor.advance(to: try await hub.readBuffer())
///   // Parse the modem's replies in `received`.
/// }
/// ```
public struct HubBufferCursor: Hashable, Sendable {

  private var position = 0

  /// Creates a cursor at the start of the buffer, as after ``Hub/clearBuffer()``.
  public init() {}

  /// Returns the bytes written since the last call, and moves the cursor past them.
  ///
  /// Bytes that wrapped around the end of the ring buffer are returned in the order they were
  /// written. A buffer of all zeros is treated as just cleared and resets the cursor.
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

      let tail = buffer.bytes[start...]

      // A zeroed tail means the buffer was cleared since the last read.
      let wrapped = tail.allSatisfy { $0 == 0 } ? [] : Array(tail)

      return wrapped + buffer.bytes[..<end]

    }

    return []

  }

  /// Moves the cursor back to the start of the buffer. Call this after clearing the buffer.
  public mutating func reset() {

    position = 0

  }

}
