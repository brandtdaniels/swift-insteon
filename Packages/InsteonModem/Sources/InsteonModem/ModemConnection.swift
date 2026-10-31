/// A byte-level connection to an Insteon modem, such as a serial port.
///
/// ``Modem`` and ``PowerLincController`` speak their device's protocol over any connection, so
/// supporting another way of reaching a device only means conforming to this protocol.
public protocol ModemConnection: Sendable {

  /// Sends bytes to the modem.
  ///
  /// A write that can't finish, such as one to a port that has stopped taking bytes, returns
  /// promptly once its task is canceled, by throwing `CancellationError`, so a canceled send
  /// never waits on it. ``Modem`` counts the time a write takes against the answer's timeout.
  ///
  /// - Parameter bytes: The bytes to send.
  /// - Throws: An error if the bytes couldn't be sent, or `CancellationError` if the task is
  ///   canceled first.
  func write(_ bytes: [UInt8]) async throws

  /// Returns the bytes the modem sends, in chunks of any size, as they arrive.
  ///
  /// The stream finishes when the connection closes. Each call may replace the previous stream,
  /// so call it once and keep the stream.
  ///
  /// - Returns: A stream of received byte chunks.
  func receive() -> AsyncThrowingStream<[UInt8], any Error>

}
