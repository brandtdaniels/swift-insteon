import Foundation
import InsteonModem

/// A connection that answers each write with bytes chosen by a script, like a modem would.
///
/// It runs under a real `Modem`, so a test exercises the same command pacing, echoes and
/// timeouts a modem on a serial port gets.
public final class ScriptedConnection: ModemConnection, @unchecked Sendable {

  // `lock` guards `writes` and `respond`.
  private let lock = NSLock()

  private var writes: [[UInt8]] = []

  private var respond: ([UInt8], Int) -> [UInt8]

  private let stream: AsyncThrowingStream<[UInt8], any Error>

  /// Feeds bytes to the modem as if they had arrived on the connection, unasked.
  public let incoming: AsyncThrowingStream<[UInt8], any Error>.Continuation

  /// Every frame written, in order, for tests that need to wait for a write.
  public let writeLog: AsyncStream<[UInt8]>

  private let writeLogContinuation: AsyncStream<[UInt8]>.Continuation

  /// Creates a connection that answers each write as a script says.
  ///
  /// - Parameter respond: Given each written frame and its index, returns the bytes to send
  ///   back. Defaults to echoing the frame followed by an ACK, `0x06`.
  public init(respond: @escaping ([UInt8], Int) -> [UInt8] = { written, _ in written + [0x06] }) {

    var continuation: AsyncThrowingStream<[UInt8], any Error>.Continuation!
    stream = AsyncThrowingStream { continuation = $0 }
    incoming = continuation
    (writeLog, writeLogContinuation) = AsyncStream.makeStream()
    self.respond = respond

  }

  /// Every frame written so far, oldest first.
  public var written: [[UInt8]] {

    lock.withLock { writes }

  }

  /// Records a frame and sends back the bytes the script answers it with.
  ///
  /// - Parameter bytes: The frame written.
  public func write(_ bytes: [UInt8]) async throws {

    let reply = lock.withLock {

      writes.append(bytes)
      return respond(bytes, writes.count - 1)

    }

    writeLogContinuation.yield(bytes)

    if !reply.isEmpty {

      incoming.yield(reply)

    }

  }

  /// Returns the bytes sent back, and those fed to ``incoming``.
  ///
  /// - Returns: The one stream of received bytes.
  public func receive() -> AsyncThrowingStream<[UInt8], any Error> {

    stream

  }

}
