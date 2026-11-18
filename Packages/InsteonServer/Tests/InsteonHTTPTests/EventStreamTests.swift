import Foundation
import Hummingbird
import HTTPTypes
import InsteonCore
import InsteonService
import NIOCore
import NIOEmbedded
import Testing
@testable import InsteonHTTP

@Suite(.timeLimit(.minutes(1)))
struct EventStreamTests {
  let policy = EventStreamPolicy(heartbeatInterval: .seconds(10), maximumLifetime: .seconds(30), maximumStreams: 2)

  /// Opens an event response whose source never ends, so only the policy can end it.
  private func openStream(_ api: DeviceAPI<FakeService>) -> (task: Task<Void, any Error>, chunks: AsyncStream<String>) {
    let (chunks, continuation) = AsyncStream<String>.makeStream()
    let task = Task {
      let response = await api.events()
      try await response.body.write(ChunkRecorder(chunks: continuation))
    }
    return (task, chunks)
  }

  private func makeAPI(_ clock: ManualClock, sources: AsyncStream<ServiceEvent>? = nil) -> DeviceAPI<FakeService> {
    DeviceAPI(service: FakeService(eventStream: sources, endlessEvents: sources == nil), policy: policy, clock: clock)
  }

  @Test func anIdleStreamWritesAKeepaliveCommentEachInterval() async throws {
    let clock = ManualClock()
    let api = makeAPI(clock)
    let stream = openStream(api)
    var chunks = stream.chunks.makeAsyncIterator()
    #expect(await chunks.next() == ": connected\n\n")
    for beat in 1...2 {
      await clock.waitForSleepers(1, until: .seconds(10 * beat))
      clock.advance(by: .seconds(10))
      #expect(await chunks.next() == ": keepalive\n\n")
    }
    stream.task.cancel()
    _ = await stream.task.result
  }

  @Test func eventsAndKeepalivesShareOneOrderedStream() async throws {
    let clock = ManualClock()
    let (source, events) = AsyncStream<ServiceEvent>.makeStream()
    let api = makeAPI(clock, sources: source)
    let stream = openStream(api)
    var chunks = stream.chunks.makeAsyncIterator()
    _ = await chunks.next()
    events.yield(.statusChanged(InsteonAddress(0x1A, 0x2B, 0x3C)))
    #expect(await chunks.next()?.hasPrefix("id: ") == true)
    await clock.waitForSleepers(1, until: .seconds(10))
    clock.advance(by: .seconds(10))
    #expect(await chunks.next() == ": keepalive\n\n")
    stream.task.cancel()
    _ = await stream.task.result
  }

  @Test func aStreamEndsCleanlyAtItsMaximumLifetimeSoTheBrowserReconnects() async throws {
    let clock = ManualClock()
    let api = makeAPI(clock)
    let stream = openStream(api)
    var chunks = stream.chunks.makeAsyncIterator()
    _ = await chunks.next()
    for beat in 1...2 {
      await clock.waitForSleepers(1, until: .seconds(10 * beat))
      clock.advance(by: .seconds(10))
      #expect(await chunks.next() == ": keepalive\n\n")
    }
    await clock.waitForSleepers(1, until: .seconds(30))
    clock.advance(by: .seconds(10))
    try await stream.task.value
    #expect(await chunks.next() == ChunkRecorder.finished)
  }

  @Test func openingPastTheStreamCapEndsTheOldestStreamAndKeepsTheNewest() async throws {
    let clock = ManualClock()
    let api = makeAPI(clock)
    let first = openStream(api)
    var firstChunks = first.chunks.makeAsyncIterator()
    _ = await firstChunks.next()
    let second = openStream(api)
    var secondChunks = second.chunks.makeAsyncIterator()
    _ = await secondChunks.next()
    let third = openStream(api)
    var thirdChunks = third.chunks.makeAsyncIterator()
    _ = await thirdChunks.next()
    try await first.task.value
    #expect(await firstChunks.next() == ChunkRecorder.finished)
    for open in [second, third] {
      open.task.cancel()
      _ = await open.task.result
    }
  }

  @Test func aClosedStreamFreesItsPlaceUnderTheCap() async throws {
    let clock = ManualClock()
    let api = makeAPI(clock)
    let first = openStream(api)
    var firstChunks = first.chunks.makeAsyncIterator()
    _ = await firstChunks.next()
    first.task.cancel()
    _ = await first.task.result
    let second = openStream(api)
    var secondChunks = second.chunks.makeAsyncIterator()
    _ = await secondChunks.next()
    let third = openStream(api)
    var thirdChunks = third.chunks.makeAsyncIterator()
    _ = await thirdChunks.next()
    // Two streams fit under the cap of two, so both still receive keepalives.
    await clock.waitForSleepers(2, until: .seconds(10))
    clock.advance(by: .seconds(10))
    let got2 = await secondChunks.next()
    let got3 = await thirdChunks.next()
    #expect(got2 == ": keepalive\n\n", "second got \(String(describing: got2))")
    #expect(got3 == ": keepalive\n\n", "third got \(String(describing: got3))")
    for open in [second, third] {
      open.task.cancel()
      _ = await open.task.result
    }
  }

  @Test func theStandardPolicyLeavesConnectionsForRequests() {
    let standard = EventStreamPolicy.standard
    #expect(standard.heartbeatInterval < standard.maximumLifetime)
    #expect(standard.maximumStreams <= ConnectionLimits.maximumConnections / 2)
  }
}

struct WriteStallTests {
  private func channel(timeout: TimeAmount) throws -> EmbeddedChannel {
    let channel = EmbeddedChannel()
    try channel.pipeline.syncOperations.addHandler(WriteStallHandler(timeout: timeout))
    try channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 1)).wait()
    return channel
  }

  @Test func aWriteThatNeverCompletesClosesTheConnectionAfterTheTimeout() throws {
    let channel = try channel(timeout: .seconds(30))
    channel.write(ByteBuffer(string: "data"), promise: nil)
    channel.embeddedEventLoop.advanceTime(by: .seconds(29))
    #expect(channel.isActive)
    channel.embeddedEventLoop.advanceTime(by: .seconds(1))
    #expect(!channel.isActive)
  }

  @Test func aWriteThatCompletesLeavesTheConnectionOpen() throws {
    let channel = try channel(timeout: .seconds(30))
    try channel.writeAndFlush(ByteBuffer(string: "data")).wait()
    channel.embeddedEventLoop.advanceTime(by: .seconds(300))
    #expect(channel.isActive)
  }

  @Test func eachWriteHasItsOwnDeadline() throws {
    let channel = try channel(timeout: .seconds(30))
    try channel.writeAndFlush(ByteBuffer(string: "first")).wait()
    channel.embeddedEventLoop.advanceTime(by: .seconds(20))
    channel.write(ByteBuffer(string: "second"), promise: nil)
    channel.embeddedEventLoop.advanceTime(by: .seconds(29))
    #expect(channel.isActive)
    channel.embeddedEventLoop.advanceTime(by: .seconds(1))
    #expect(!channel.isActive)
  }
}

private struct ChunkRecorder: ResponseBodyWriter {
  static let finished = "<finished>"
  let chunks: AsyncStream<String>.Continuation
  mutating func write(_ buffer: ByteBuffer) async throws { chunks.yield(String(buffer: buffer)) }
  consuming func finish(_ trailingHeaders: HTTPFields?) async throws {
    chunks.yield(Self.finished)
    chunks.finish()
  }
}

/// A clock that moves only when a test advances it.
final class ManualClock: Clock, @unchecked Sendable {
  struct Instant: InstantProtocol {
    var offset: Duration
    func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
    func duration(to other: Instant) -> Duration { other.offset - offset }
    static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
  }
  private struct Sleeper { let id: Int; let deadline: Instant; let continuation: CheckedContinuation<Void, any Error> }
  private struct Waiter { let count: Int; let deadline: Instant; let continuation: CheckedContinuation<Void, Never> }
  private let lock = NSLock()
  private var current = Instant(offset: .zero)
  private var nextID = 0
  private var sleepers: [Sleeper] = []
  private var waiters: [Waiter] = []

  var now: Instant { lock.withLock { current } }
  var minimumResolution: Duration { .zero }

  func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
    let id = lock.withLock { defer { nextID += 1 }; return nextID }
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
        let cancelled = Task.isCancelled
        let ready: [CheckedContinuation<Void, Never>]? = lock.withLock {
          if cancelled { return [] }
          if deadline <= current { return nil }
          sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
          return takeSatisfiedWaiters()
        }
        if cancelled { continuation.resume(throwing: CancellationError()); ready?.forEach { $0.resume() } }
        else if let ready { ready.forEach { $0.resume() } } else { continuation.resume() }
      }
    } onCancel: {
      let canceled = lock.withLock { () -> Sleeper? in
        guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return nil }
        return sleepers.remove(at: index)
      }
      canceled?.continuation.resume(throwing: CancellationError())
    }
  }

  func advance(by duration: Duration) {
    let due: [Sleeper] = lock.withLock {
      current = current.advanced(by: duration)
      let due = sleepers.filter { $0.deadline <= current }
      sleepers.removeAll { $0.deadline <= current }
      return due
    }
    due.forEach { $0.continuation.resume() }
  }

  /// Returns once `count` tasks sleep until `offset` past the clock's start.
  func waitForSleepers(_ count: Int, until offset: Duration) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let ready = lock.withLock { () -> Bool in
        let deadline = Instant(offset: offset)
        if sleepers.filter({ $0.deadline == deadline }).count >= count { return true }
        waiters.append(Waiter(count: count, deadline: deadline, continuation: continuation))
        return false
      }
      if ready { continuation.resume() }
    }
  }

  // Call while holding `lock`.
  private func takeSatisfiedWaiters() -> [CheckedContinuation<Void, Never>] {
    let satisfied = waiters.filter { waiter in sleepers.filter { $0.deadline == waiter.deadline }.count >= waiter.count }
    waiters.removeAll { waiter in sleepers.filter { $0.deadline == waiter.deadline }.count >= waiter.count }
    return satisfied.map(\.continuation)
  }
}
