import Foundation
import HTTPTypes
import Testing
@testable import InsteonHTTP

/// The store's rules without a server: what is recorded, how long, how many, and who waits.
@Suite(.timeLimit(.minutes(1)))
struct IdempotencyStoreTests {
  private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { date } }
    func advance(_ seconds: TimeInterval) { lock.withLock { date = date.addingTimeInterval(seconds) } }
  }

  private let scope = IdempotencyScope.gateway
  private func ok(_ text: String = "{}") -> IdempotentOutcome { .response(.ok, Data(text.utf8)) }

  private func store(capacity: Int = 3, retention: TimeInterval = 600, clock: Clock, onWait: (@Sendable () -> Void)? = nil) -> IdempotencyStore {
    IdempotencyStore(policy: IdempotencyPolicy(capacity: capacity, retention: retention), now: { clock.now }, onWait: onWait)
  }

  /// Counts how often work ran.
  private actor Runs {
    var count = 0
    func ran() { count += 1 }
  }

  @Test func aSuccessIsRecordedAndReplayed() async throws {
    let runs = Runs()
    let subject = store(clock: Clock())
    let first = try await subject.perform(scope: scope, key: "k", fingerprint: "a") { await runs.ran(); return ok("1") }
    let second = try await subject.perform(scope: scope, key: "k", fingerprint: "a") { await runs.ran(); return ok("2") }
    #expect(!first.replayed)
    #expect(second.replayed)
    #expect(second.outcome == ok("1"))
    #expect(await runs.count == 1)
  }

  @Test func aFailureIsRecordedOnlyWhenACommandMayHaveReachedTheDevice() async throws {
    let subject = store(clock: Clock())
    let runs = Runs()
    for (key, code, recorded) in [("unknown", APIErrorCode.outcomeUnknown, true), ("canceled", .canceled, true), ("busy", .busy, false), ("away", .modemUnavailable, false), ("silent", .deviceNotAnswering, false), ("rejected", .deviceRejected, false)] {
      _ = try await subject.perform(scope: scope, key: key, fingerprint: "a") { await runs.ran(); return .failure(HTTPFailure(code, sent: code.sent)) }
      let again = try await subject.perform(scope: scope, key: key, fingerprint: "a") { await runs.ran(); return .failure(HTTPFailure(code, sent: code.sent)) }
      #expect(again.replayed == recorded, "\(code)")
    }
  }

  @Test func theSameKeyWithAnotherFingerprintIsReused() async throws {
    let subject = store(clock: Clock())
    _ = try await subject.perform(scope: scope, key: "k", fingerprint: "a") { ok() }
    await #expect(throws: IdempotencyError.reused) {
      try await subject.perform(scope: scope, key: "k", fingerprint: "b") { ok() }
    }
  }

  @Test func theSameKeyInAnotherScopeIsAnotherCommand() async throws {
    let subject = store(clock: Clock())
    _ = try await subject.perform(scope: scope, key: "k", fingerprint: "a") { ok("1") }
    let other = try await subject.perform(scope: IdempotencyScope(principal: "second-client"), key: "k", fingerprint: "b") { ok("2") }
    #expect(!other.replayed)
  }

  @Test func anEntryExpiresWhenItsRetentionPeriodEnds() async throws {
    let clock = Clock()
    let subject = store(retention: 600, clock: clock)
    _ = try await subject.perform(scope: scope, key: "k", fingerprint: "a") { ok() }
    clock.advance(599)
    #expect(try await subject.perform(scope: scope, key: "k", fingerprint: "a") { ok() }.replayed)
    clock.advance(1)
    #expect(try await !subject.perform(scope: scope, key: "k", fingerprint: "a") { ok() }.replayed)
    // An expired key can be used for a different command.
    clock.advance(600)
    #expect(try await !subject.perform(scope: scope, key: "k", fingerprint: "b") { ok() }.replayed)
  }

  @Test func theOldestEntryLeavesWhenTheStoreIsFull() async throws {
    let subject = store(capacity: 3, clock: Clock())
    for key in ["1", "2", "3", "4"] { _ = try await subject.perform(scope: scope, key: key, fingerprint: key) { ok() } }
    #expect(await subject.count == 3)
    #expect(try await !subject.perform(scope: scope, key: "1", fingerprint: "1") { ok() }.replayed)
    #expect(try await subject.perform(scope: scope, key: "4", fingerprint: "4") { ok() }.replayed)
  }

  @Test func aRepeatWhileTheFirstRunsWaitsForItsResultAndSendsNothing() async throws {
    let (waiting, onWait) = AsyncStream<Void>.makeStream()
    let (started, didStart) = AsyncStream<Void>.makeStream()
    let (release, finish) = AsyncStream<Void>.makeStream()
    let subject = store(clock: Clock(), onWait: { onWait.yield() })
    let runs = Runs()
    let first = Task {
      try await subject.perform(scope: scope, key: "k", fingerprint: "a") {
        await runs.ran()
        didStart.yield()
        for await _ in release {}
        return ok("first")
      }
    }
    var begun = started.makeAsyncIterator()
    _ = await begun.next()
    let second = Task { try await subject.perform(scope: scope, key: "k", fingerprint: "a") { await runs.ran(); return ok("second") } }
    var parked = waiting.makeAsyncIterator()
    _ = await parked.next()
    finish.finish()
    let (one, two) = try await (first.value, second.value)
    #expect(one.outcome == ok("first") && !one.replayed)
    #expect(two.outcome == ok("first") && two.replayed)
    #expect(await runs.count == 1)
  }

  @Test func aRepeatThatWaitedForAnUnrecordedOutcomeGetsItAndTheKeyIsFreeAfterwards() async throws {
    let (waiting, onWait) = AsyncStream<Void>.makeStream()
    let (started, didStart) = AsyncStream<Void>.makeStream()
    let (release, finish) = AsyncStream<Void>.makeStream()
    let subject = store(clock: Clock(), onWait: { onWait.yield() })
    let first = Task {
      try await subject.perform(scope: scope, key: "k", fingerprint: "a") {
        didStart.yield()
        for await _ in release {}
        return .failure(HTTPFailure(.busy, sent: false))
      }
    }
    var begun = started.makeAsyncIterator()
    _ = await begun.next()
    let second = Task { try await subject.perform(scope: scope, key: "k", fingerprint: "a") { ok() } }
    var parked = waiting.makeAsyncIterator()
    _ = await parked.next()
    finish.finish()
    #expect(try await second.value.replayed)
    #expect(try await !subject.perform(scope: scope, key: "k", fingerprint: "a") { ok() }.replayed)
    _ = try await first.value
  }

  @Test(arguments: ["a", "A1", "0123456789._~:-", String(repeating: "k", count: 128)])
  func aWellFormedKeyIsAccepted(_ key: String) throws {
    #expect(try IdempotencyKey(header: [key])?.value == key)
  }

  @Test(arguments: [[""], ["a", "b"], ["has space"], ["tab\t"], ["a,b"], ["caf\u{E9}"], [String(repeating: "k", count: 129)]])
  func aMalformedKeyIsRejected(_ values: [String]) {
    #expect(throws: IdempotencyError.invalidKey) { try IdempotencyKey(header: values) }
  }

  @Test func noHeaderMeansNoKey() throws {
    #expect(try IdempotencyKey(header: []) == nil)
  }
}
