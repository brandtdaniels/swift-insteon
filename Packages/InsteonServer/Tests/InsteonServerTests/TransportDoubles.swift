import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonCore
import InsteonHubClient
import InsteonModem
import InsteonNetworking
import Logging
import Testing
@testable import InsteonServerSupport

/// An HTTP transport that answers every request the same way.
struct ScriptedTransport: HTTPClient {
  enum Behavior: Sendable {
    case status(Int)
    case fails(URLError)
  }
  let behavior: Behavior
  init(_ behavior: Behavior) { self.behavior = behavior }
  func send(_ request: URLRequest) async throws -> HTTPResponse {
    switch behavior {
    case let .status(code): HTTPResponse(statusCode: code)
    case let .fails(error): throw error
    }
  }
}

/// Lets a test choose between a real and a virtual clock for the same code.
struct AnyClock: Clock, Sendable {
  struct Instant: InstantProtocol {
    var offset: Duration
    func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
    func duration(to other: Instant) -> Duration { other.offset - offset }
    static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
  }
  private let nowOffset: @Sendable () -> Duration
  private let sleepUntil: @Sendable (Duration) async throws -> Void
  init<C: Clock>(_ clock: C) where C.Duration == Duration {
    let origin = clock.now
    nowOffset = { origin.duration(to: clock.now) }
    sleepUntil = { offset in try await clock.sleep(until: origin.advanced(by: offset), tolerance: nil) }
  }
  var now: Instant { Instant(offset: nowOffset()) }
  var minimumResolution: Duration { .nanoseconds(1) }
  func sleep(until deadline: Instant, tolerance: Duration?) async throws { try await sleepUntil(deadline.offset) }
}

/// A connection that accepts writes and never answers.
final class SilentConnection: ModemConnection, @unchecked Sendable {
  func write(_ bytes: [UInt8]) async throws {}
  func receive() -> AsyncThrowingStream<[UInt8], any Error> { AsyncThrowingStream<[UInt8], any Error>.makeStream().stream }
}

/// A connection whose writes are rejected with 401 and whose reader fails with a connection error
/// once it is canceled, as a dropped connection does.
final class RejectingConnection: ModemConnection, @unchecked Sendable {
  func write(_ bytes: [UInt8]) async throws { throw HubError.unexpectedStatus(401) }
  func receive() -> AsyncThrowingStream<[UInt8], any Error> {
    AsyncThrowingStream(unfolding: {
      for await _ in AsyncStream<Void>.makeStream().stream {}
      throw URLError(.networkConnectionLost)
    })
  }
}

/// A clock whose sleeps return at once and move its time forward, so the library's real retry and
/// timeout policies run without waiting.
final class VirtualClock: Clock, @unchecked Sendable {
  struct Instant: InstantProtocol {
    var offset: Duration
    func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
    func duration(to other: Instant) -> Duration { other.offset - offset }
    static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
  }
  private let lock = NSLock()
  private var elapsed = Duration.zero
  var now: Instant { lock.withLock { Instant(offset: elapsed) } }
  var minimumResolution: Duration { .nanoseconds(1) }
  func sleep(until deadline: Instant, tolerance: Duration?) async throws {
    try Task.checkCancellation()
    lock.withLock { if deadline.offset > elapsed { elapsed = deadline.offset } }
    await Task.yield()
  }
}
