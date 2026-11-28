/// Receives the bytes that cross the wire to a modem, for a raw trace.
///
/// A ``TracingConnection`` reports a serial modem's frames, and a Hub reports its requests and
/// its buffer reads. Nothing is traced unless a tracer is given, and the arguments are built only
/// when one is, so a library without a tracer does no extra work. A tracer never sees a Hub's user
/// name, password or `Authorization` header: the bytes are the modem's, and a request's path.
public protocol WireTrace: Sendable {

  /// Records bytes that crossed the wire.
  ///
  /// - Parameters:
  ///   - direction: Where the bytes went or came from.
  ///   - bytes: The bytes, which are empty for a request with no payload or a read with nothing new.
  ///   - instant: When it happened, so the tracer can tell how long it was since the last one.
  func trace(_ direction: WireTraceDirection, _ bytes: [UInt8], at instant: ContinuousClock.Instant)

}

/// Where traced bytes went or came from.
public enum WireTraceDirection: Hashable, Sendable {

  /// A frame written to a serial modem.
  case written

  /// A chunk read from a serial modem.
  case received

  /// A request to a Hub. The bytes are the serial command it passes to the modem, or for a short
  /// command its command byte and group number, or none for any other request.
  case hubRequest(path: String)

  /// A read of a Hub's buffer. The bytes are the ones new since the last read, and `endIndex` is
  /// where the Hub writes the next byte.
  case hubBuffer(endIndex: Int, step: WireTraceBufferStep)

}

/// How a Hub buffer cursor treated a read of the buffer.
public enum WireTraceBufferStep: Hashable, Sendable {

  /// New bytes followed the cursor's position.
  case advanced

  /// The end position passed the end of the ring and the new bytes wrapped around it.
  case wrapped

  /// The buffer was all zeros, so the cursor treated it as just cleared and started over.
  case cleared

  /// The buffer was cleared and refilled: it was zeros after its end position, so only the bytes
  /// before the end position are new.
  case refilled

  /// Nothing was written since the last read.
  case unchanged

}

/// A ``ModemConnection`` that reports each frame written and each chunk read to a ``WireTrace``.
///
/// Wrap a serial connection to trace it. A Hub traces itself: see `Hub.tracing(_:)`.
public struct TracingConnection: ModemConnection {

  private let connection: any ModemConnection

  private let tracer: (any WireTrace)?

  /// Creates a connection that traces another.
  ///
  /// - Parameters:
  ///   - connection: The connection to trace.
  ///   - tracer: Receives the traffic, or `nil` to trace nothing.
  public init(_ connection: any ModemConnection, tracer: (any WireTrace)?) {

    self.connection = connection
    self.tracer = tracer

  }

  /// Traces the frame, then sends it.
  public func write(_ bytes: [UInt8]) async throws {

    tracer?.trace(.written, bytes, at: .now)

    try await connection.write(bytes)

  }

  /// Returns the connection's stream, tracing each chunk as it is read.
  public func receive() -> AsyncThrowingStream<[UInt8], any Error> {

    guard let tracer else {

      return connection.receive()

    }

    let source = ChunkSource(connection.receive())

    return AsyncThrowingStream(unfolding: {

      guard let chunk = try await source.next() else {

        return nil

      }

      tracer.trace(.received, chunk, at: .now)

      return chunk

    })

  }

}

/// Holds the traced stream's iterator, which one reading task uses at a time.
private actor ChunkSource {

  // One reading task reads the stream a call at a time, so nothing else touches the iterator; the
  // actor can't hold it as isolated state because reading it is a mutating call that suspends.
  nonisolated(unsafe) private var iterator: AsyncThrowingStream<[UInt8], any Error>.Iterator

  init(_ stream: AsyncThrowingStream<[UInt8], any Error>) {

    iterator = stream.makeAsyncIterator()

  }

  func next() async throws -> [UInt8]? {

    try await iterator.next()

  }

}
