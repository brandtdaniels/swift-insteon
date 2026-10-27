/// A byte-level connection to an INSTEON modem, such as a serial port.
///
/// ``Modem`` speaks the modem's protocol over any connection, so supporting another way of
/// reaching a modem only means conforming to this protocol.
public protocol ModemConnection: Sendable {

  /// Sends bytes to the modem.
  ///
  /// - Parameter bytes: The bytes to send.
  /// - Throws: An error if the bytes couldn't be sent.
  func write(_ bytes: [UInt8]) async throws

  /// Returns the bytes the modem sends, in chunks of any size, as they arrive.
  ///
  /// The stream finishes when the connection closes. Each call may replace the previous stream,
  /// so call it once and keep the stream.
  ///
  /// - Returns: A stream of received byte chunks.
  func receive() -> AsyncThrowingStream<[UInt8], any Error>

}
