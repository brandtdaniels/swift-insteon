import Foundation
import InsteonModem

/// A connection that answers each write with bytes chosen by a script, like a modem would.
final class ScriptedConnection: ModemConnection, @unchecked Sendable {

  // `lock` guards `writes` and `respond`.
  private let lock = NSLock()

  private var writes: [[UInt8]] = []

  private var respond: ([UInt8], Int) -> [UInt8]

  private let stream: AsyncThrowingStream<[UInt8], any Error>

  let incoming: AsyncThrowingStream<[UInt8], any Error>.Continuation

  /// - Parameter respond: Given each written frame and its index, returns the bytes to send back.
  init(respond: @escaping ([UInt8], Int) -> [UInt8] = { written, _ in written + [0x06] }) {

    var continuation: AsyncThrowingStream<[UInt8], any Error>.Continuation!
    stream = AsyncThrowingStream { continuation = $0 }
    incoming = continuation
    self.respond = respond

  }

  var written: [[UInt8]] {

    lock.lock()
    defer { lock.unlock() }

    return writes

  }

  func write(_ bytes: [UInt8]) async throws {

    lock.lock()
    let index = writes.count
    writes.append(bytes)
    let reply = respond(bytes, index)
    lock.unlock()

    if !reply.isEmpty {

      incoming.yield(reply)

    }

  }

  func receive() -> AsyncThrowingStream<[UInt8], any Error> {

    stream

  }

}
