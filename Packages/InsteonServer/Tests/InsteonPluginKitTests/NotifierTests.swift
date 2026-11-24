import Foundation
import Testing
@testable import InsteonPluginKit

/// A clock that records each sleep and returns at once, so backoff is checked by its exact durations and never waited on.
/// After `ceiling` sleeps it cancels, so a notifier that retries forever ends the test instead of hanging it.
final class RecordingClock: Clock, @unchecked Sendable {
  struct Instant: InstantProtocol {
    var offset: Duration
    func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
    func duration(to other: Instant) -> Duration { other.offset - offset }
    static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
  }
  private let lock = NSLock()
  private var elapsed = Duration.zero
  private var recorded: [Duration] = []
  private let ceiling: Int

  init(ceiling: Int = 12) { self.ceiling = ceiling }

  var now: Instant { lock.withLock { Instant(offset: elapsed) } }
  var minimumResolution: Duration { .zero }
  var sleeps: [Duration] { lock.withLock { recorded } }

  func sleep(until deadline: Instant, tolerance: Duration?) async throws {
    let allowed: Bool = lock.withLock {
      guard recorded.count < ceiling else { return false }
      recorded.append(deadline.offset - elapsed)
      elapsed = deadline.offset
      return true
    }
    guard allowed else { throw CancellationError() }
  }
}

/// A service stream scripted connection by connection. When the script is spent, the next connection is refused, which ends a run.
final class ScriptedSource: NotificationStreaming, @unchecked Sendable {
  enum Ending: Sendable { case ends, fails(PluginError) }
  struct Connection: Sendable {
    var items: [StreamItem]
    var ending: Ending = .ends
  }

  private let lock = NSLock()
  private var script: [Connection]
  private var requested: [String?] = []
  private let rules: Result<Int, PluginError>

  init(_ script: [Connection], rules: Result<Int, PluginError> = .success(3)) {
    self.script = script
    self.rules = rules
  }

  var cursors: [String?] { lock.withLock { requested } }

  typealias Events = AsyncThrowingStream<StreamItem, any Error>

  func events(after lastEventID: String?) -> Events {
    let connection: Connection = lock.withLock {
      requested.append(lastEventID)
      return script.isEmpty ? Connection(items: [], ending: .fails(.unauthorized(status: 401, code: nil))) : script.removeFirst()
    }
    return AsyncThrowingStream { continuation in
      for item in connection.items { continuation.yield(item) }
      switch connection.ending {
      case .ends: continuation.finish()
      case let .fails(error): continuation.finish(throwing: error)
      }
    }
  }

  func ruleCount() async throws -> Int { try rules.get() }
}

final class RecordingState: NotifierStateStoring, @unchecked Sendable {
  struct Refused: Error {}
  private let lock = NSLock()
  private var stored: String?
  private var saved: [String] = []
  private let refusesWrites: Bool

  init(_ stored: String? = nil, refusesWrites: Bool = false) {
    self.stored = stored
    self.refusesWrites = refusesWrites
  }

  var records: [String] { lock.withLock { saved } }
  func lastEventID() throws -> String? { lock.withLock { stored } }
  func record(lastEventID: String) throws {
    if refusesWrites { throw Refused() }
    lock.withLock { stored = lastEventID; saved.append(lastEventID) }
  }
}

/// Fails a set number of times, then delivers. Records what it was given and what the state held at each attempt.
final class ScriptedDeliverer: Deliverer, @unchecked Sendable {
  struct Down: Error {}
  private let lock = NSLock()
  private var remainingFailures: Int
  private var attempts: [DeliveryPayload] = []
  private var done: [DeliveryPayload] = []
  private let state: RecordingState?
  private var recordsAtAttempt: [[String]] = []

  init(failures: Int = 0, state: RecordingState? = nil) {
    remainingFailures = failures
    self.state = state
  }

  var delivered: [DeliveryPayload] { lock.withLock { done } }
  var attemptCount: Int { lock.withLock { attempts.count } }
  var stateRecordsAtEachAttempt: [[String]] { lock.withLock { recordsAtAttempt } }

  func deliver(_ payload: DeliveryPayload) async throws {
    let fails: Bool = lock.withLock {
      attempts.append(payload)
      recordsAtAttempt.append(state?.records ?? [])
      if remainingFailures > 0 { remainingFailures -= 1; return true }
      done.append(payload)
      return false
    }
    if fails { throw Down() }
  }
}

final class Reports: @unchecked Sendable {
  private let lock = NSLock()
  private var items: [NotifierReport] = []
  var all: [NotifierReport] { lock.withLock { items } }
  func add(_ report: NotifierReport) { lock.withLock { items.append(report) } }
}

private func note(_ id: String, name: String = "Basement leak", event: String? = nil) -> StreamItem {
  .notification(NotificationEvent(id: id, ruleID: "basement-leak", ruleName: name, address: "1A.2B.3C", firedAt: "2027-01-15T08:00:00Z", event: event))
}

@Suite(.timeLimit(.minutes(1)))
struct NotifierTests {
  private func run(_ notifier: Notifier<ScriptedSource>) async -> (any Error)? {
    do { try await notifier.run(); return nil } catch { return error }
  }

  private func notifier(_ source: ScriptedSource, _ deliverer: ScriptedDeliverer, _ state: RecordingState = RecordingState(), clock: RecordingClock = RecordingClock(), includesDetail: Bool = false, reports: Reports = Reports()) -> Notifier<ScriptedSource> {
    Notifier(source: source, deliverer: deliverer, state: state, clock: clock, includesDetail: includesDetail, report: reports.add)
  }

  // MARK: Delivering once

  @Test func eachNotificationIsDeliveredOnceInOrderAndItsIdIsRecordedAfterwards() async throws {
    let source = ScriptedSource([.init(items: [note("r-1", name: "One"), .other(id: "r-2"), note("r-3", name: "Two")])])
    let state = RecordingState()
    let deliverer = ScriptedDeliverer(state: state)
    let error = await run(notifier(source, deliverer, state))
    #expect(error as? PluginError == .unauthorized(status: 401, code: nil))
    #expect(deliverer.delivered.map(\.ruleName) == ["One", "Two"])
    #expect(state.records == ["r-1", "r-3"])
    // The id is recorded after the delivery, so each attempt saw only the earlier ids.
    #expect(deliverer.stateRecordsAtEachAttempt == [[], ["r-1"]])
  }

  @Test func aRestartResumesFromTheRecordedIdAndDeliversNothingTwice() async throws {
    let source = ScriptedSource([.init(items: [note("r-5", name: "Already"), note("r-6", name: "Next")])])
    let state = RecordingState("r-5")
    let deliverer = ScriptedDeliverer()
    _ = await run(notifier(source, deliverer, state))
    #expect(source.cursors.first == "r-5")
    // A service that sent r-5 again anyway is not delivered twice.
    #expect(deliverer.delivered.map(\.ruleName) == ["Next"])
    #expect(state.records == ["r-6"])
  }

  @Test func aNotificationTheServiceSendsTwiceIsDeliveredOnce() async throws {
    let source = ScriptedSource([.init(items: [note("r-1"), note("r-1"), note("r-2")])])
    let deliverer = ScriptedDeliverer()
    _ = await run(notifier(source, deliverer))
    #expect(deliverer.delivered.count == 2)
  }

  @Test func theFirstConnectionHasNoPlaceWhenNothingWasRecorded() async throws {
    let source = ScriptedSource([])
    _ = await run(notifier(source, ScriptedDeliverer()))
    #expect(source.cursors == [nil])
  }

  @Test func theNotifierReportsWhenTheStreamIsOpen() async throws {
    let source = ScriptedSource([.init(items: [.connected, note("r-1")])])
    let reports = Reports()
    _ = await run(notifier(source, ScriptedDeliverer(), reports: reports))
    #expect(reports.all.prefix(2) == [.connected, .delivered(id: "r-1")])
  }

  @Test func aStreamThatEndsIsFollowedAgainFromTheLastIdSeenWithoutWaiting() async throws {
    let source = ScriptedSource([.init(items: [note("r-1"), .other(id: "r-9")]), .init(items: [note("r-10")])])
    let clock = RecordingClock()
    let deliverer = ScriptedDeliverer()
    _ = await run(notifier(source, deliverer, clock: clock))
    #expect(source.cursors == [nil, "r-9", "r-10"])
    #expect(deliverer.delivered.count == 2)
    #expect(clock.sleeps.isEmpty)
  }

  // MARK: Failing channels

  @Test func aFailingChannelIsRetriedWithDoublingBackoffAndDeliversOnceWhenItRecovers() async throws {
    let source = ScriptedSource([.init(items: [note("r-1")])])
    let state = RecordingState()
    let deliverer = ScriptedDeliverer(failures: 3, state: state)
    let clock = RecordingClock()
    let reports = Reports()
    _ = await run(notifier(source, deliverer, state, clock: clock, reports: reports))
    #expect(clock.sleeps == [.seconds(1), .seconds(2), .seconds(4)])
    #expect(deliverer.attemptCount == 4 && deliverer.delivered.count == 1)
    #expect(state.records == ["r-1"])
    #expect(deliverer.stateRecordsAtEachAttempt == Array(repeating: [], count: 4))
    #expect(reports.all.prefix(4) == [.deliveryFailed(id: "r-1", attempt: 1), .deliveryFailed(id: "r-1", attempt: 2), .deliveryFailed(id: "r-1", attempt: 3), .delivered(id: "r-1")])
  }

  @Test func backoffStopsGrowingAtTheMaximum() {
    let policy = RetryPolicy(initial: .seconds(1), maximum: .seconds(10))
    #expect((1...7).map { policy.delay(afterFailures: $0) } == [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(10), .seconds(10), .seconds(10)])
    #expect(RetryPolicy.standard.delay(afterFailures: 20) == .seconds(60))
    #expect(policy.delay(afterFailures: 0) == .seconds(1))
  }

  @Test func aChannelThatStaysDownKeepsTheNotificationAndTheNotifierEndsWhenCanceled() async throws {
    let source = ScriptedSource([.init(items: [note("r-1")])])
    let state = RecordingState()
    let deliverer = ScriptedDeliverer(failures: .max, state: state)
    let clock = RecordingClock(ceiling: 5)
    let error = await run(notifier(source, deliverer, state, clock: clock))
    #expect(error is CancellationError)
    #expect(deliverer.attemptCount == 6 && deliverer.delivered.isEmpty)
    #expect(state.records.isEmpty)
  }

  // MARK: The stream failing

  @Test func aFailedConnectionIsFollowedAgainAfterBackoffThatRestartsOnceEventsFlowAgain() async throws {
    let source = ScriptedSource([
      .init(items: [], ending: .fails(.unreachable)),
      .init(items: [], ending: .fails(.unreachable)),
      .init(items: [note("r-1")], ending: .fails(.unreachable)),
      .init(items: [note("r-2")])
    ])
    let clock = RecordingClock()
    let reports = Reports()
    let deliverer = ScriptedDeliverer()
    _ = await run(notifier(source, deliverer, clock: clock, reports: reports))
    #expect(clock.sleeps == [.seconds(1), .seconds(2), .seconds(1)])
    #expect(source.cursors == [nil, nil, nil, "r-1", "r-2"])
    #expect(deliverer.delivered.count == 2)
    #expect(reports.all.filter { $0 == .disconnected }.count == 3)
  }

  @Test func aRefusedTokenEndsTheRunAtOnceBecauseWaitingCannotFixIt() async throws {
    let source = ScriptedSource([.init(items: [], ending: .fails(.unauthorized(status: 403, code: "forbidden")))])
    let clock = RecordingClock()
    let error = await run(notifier(source, ScriptedDeliverer(), clock: clock))
    #expect(error as? PluginError == .unauthorized(status: 403, code: "forbidden"))
    #expect(source.cursors.count == 1 && clock.sleeps.isEmpty)
  }

  // MARK: Gaps

  @Test func aGapRelistsTheRulesReportsThatMissedNotificationsCannotBeReplayedAndContinuesFromThere() async throws {
    let source = ScriptedSource([.init(items: [.gap(id: "r2-7"), note("r2-8", name: "After")])], rules: .success(2))
    let state = RecordingState("r-4")
    let reports = Reports()
    let deliverer = ScriptedDeliverer()
    _ = await run(notifier(source, deliverer, state, reports: reports))
    #expect(reports.all.first == .gap(rules: 2))
    #expect(deliverer.delivered.map(\.ruleName) == ["After"])
    #expect(state.records == ["r2-7", "r2-8"])
  }

  @Test func aGapIsReportedEvenWhenTheRulesCannotBeListed() async throws {
    let source = ScriptedSource([.init(items: [.gap(id: "r2-7")])], rules: .failure(.unreachable))
    let reports = Reports()
    _ = await run(notifier(source, ScriptedDeliverer(), reports: reports))
    #expect(reports.all.first == .gap(rules: nil))
  }

  // MARK: Content

  @Test func aPayloadCarriesOnlyTheRuleNameAndTheTimeByDefault() async throws {
    let source = ScriptedSource([.init(items: [note("r-1", event: "wet")])])
    let deliverer = ScriptedDeliverer()
    _ = await run(notifier(source, deliverer))
    #expect(deliverer.delivered == [DeliveryPayload(ruleName: "Basement leak", firedAt: "2027-01-15T08:00:00Z")])
  }

  @Test func detailIsIncludedOnlyWhenTheNotifierWasToldTo() async throws {
    let source = ScriptedSource([.init(items: [note("r-1", event: "wet")])])
    let deliverer = ScriptedDeliverer()
    _ = await run(notifier(source, deliverer, includesDetail: true))
    #expect(deliverer.delivered == [DeliveryPayload(ruleName: "Basement leak", firedAt: "2027-01-15T08:00:00Z", address: "1A.2B.3C", event: "wet")])
  }

  // MARK: Its own state

  @Test func aStateThatCannotBeWrittenStopsTheNotifierBeforeItCanRepeatAnything() async throws {
    let source = ScriptedSource([.init(items: [note("r-1"), note("r-2")])])
    let deliverer = ScriptedDeliverer()
    let error = await run(notifier(source, deliverer, RecordingState(refusesWrites: true)))
    #expect(error is RecordingState.Refused)
    #expect(deliverer.delivered.count == 1)
  }
}
