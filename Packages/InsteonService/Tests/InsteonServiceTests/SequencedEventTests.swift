import Foundation
import InsteonCore
import InsteonHubClient
import InsteonLinkingTestSupport
import InsteonTestSupport
import Testing
@testable import InsteonService

/// Every event the service publishes has a number in its run, and a client that reconnects with
/// the last number it saw gets what it missed or is told to refresh.
@Suite(.timeLimit(.minutes(1)))
struct SequencedEventTests {
  let address = InsteonAddress(0x1A, 0x2B, 0x3C)
  let hubAway = HubStoppedAnswering(underlyingError: URLError(.timedOut))

  private func service(runID: String? = nil) -> InsteonService {
    let identity = ReportedIdentity(category: 1, subcategory: 125, firmwareVersion: 69)
    let network = DeviceNetwork(modem: InMemoryModem(), catalog: nil, snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [address: identity])), now: { Date(timeIntervalSince1970: 1_800_000_000) })
    return InsteonService(network: network, runID: runID)
  }

  private func perform(_ count: Int, on service: InsteonService) async throws {
    for index in 0..<count {
      _ = try await service.execute(ServiceCommand(address: address, action: index.isMultiple(of: 2) ? .on : .off))
    }
  }

  /// The next `count` items of a sequenced stream.
  private func take(_ count: Int, from events: SequencedEvents) async throws -> [SequencedItem] {
    var items: [SequencedItem] = []
    var reader = events.makeAsyncIterator()
    while items.count < count, let item = try await reader.next() {
      if case .position = item { continue }
      items.append(item)
    }
    return items
  }

  private func sequences(_ items: [SequencedItem]) -> [UInt64] {
    items.compactMap { if case let .event(_, cursor) = $0 { cursor.sequence } else { nil } }
  }

  @Test func eachEventHasTheNextNumberOfTheRun() async throws {
    let service = service(runID: "run-one")
    let events = await service.sequencedEvents(after: nil)
    try await perform(3, on: service)
    let items = try await take(3, from: events)
    #expect(sequences(items) == [1, 2, 3])
    for case let .event(_, cursor) in items { #expect(cursor.runID == "run-one") }
  }

  @Test func aFreshSubscriptionStartsWithTheRunsPositionAndAResumedOneDoesNot() async throws {
    let service = service(runID: "run-one")
    try await perform(2, on: service)
    var fresh = await service.sequencedEvents(after: nil).makeAsyncIterator()
    #expect(try await fresh.next() == .position(EventCursor(runID: "run-one", sequence: 2)))
    try await perform(1, on: service)
    var resumed = await service.sequencedEvents(after: EventCursor(runID: "run-one", sequence: 2)).makeAsyncIterator()
    guard case .event? = try await resumed.next() else { Issue.record("a resumed stream starts with the missed event"); return }
  }

  @Test func theNumbersAreSharedByEverySubscriber() async throws {
    let service = service()
    let first = await service.sequencedEvents(after: nil)
    let second = await service.sequencedEvents(after: nil)
    try await perform(2, on: service)
    #expect(sequences(try await take(2, from: first)) == sequences(try await take(2, from: second)))
  }

  @Test func theUnsequencedSubscriptionStillSeesTheSameEvents() async throws {
    let service = service()
    let plain = await service.events()
    try await perform(2, on: service)
    var reader = plain.makeAsyncIterator()
    #expect(try await reader.next() != nil)
    #expect(try await reader.next() != nil)
  }

  // MARK: Resuming

  @Test func aClientThatSawTheThirdEventGetsTheMissedOnesInOrderThenLiveOnes() async throws {
    let service = service(runID: "run-one")
    try await perform(5, on: service)
    let events = await service.sequencedEvents(after: EventCursor(runID: "run-one", sequence: 3))
    try await perform(1, on: service)
    let items = try await take(3, from: events)
    #expect(sequences(items) == [4, 5, 6])
  }

  @Test func aClientThatIsCurrentGetsOnlyLiveEvents() async throws {
    let service = service(runID: "run-one")
    try await perform(2, on: service)
    let events = await service.sequencedEvents(after: EventCursor(runID: "run-one", sequence: 2))
    try await perform(1, on: service)
    #expect(sequences(try await take(1, from: events)) == [3])
  }

  @Test func theBufferKeepsTheLast256EventsAndNoMore() async throws {
    let service = service(runID: "run-one")
    try await perform(300, on: service)
    // Events 45 through 300 are kept; a client at 44 missed exactly those.
    let covered = await service.sequencedEvents(after: EventCursor(runID: "run-one", sequence: 44))
    let items = try await take(256, from: covered)
    #expect(sequences(items).first == 45)
    #expect(sequences(items).last == 300)
    let tooOld = await service.sequencedEvents(after: EventCursor(runID: "run-one", sequence: 43))
    #expect(try await take(1, from: tooOld) == [.gap(.tooOld, current: EventCursor(runID: "run-one", sequence: 300))])
  }

  // MARK: Gaps

  @Test func aClientFromAnotherRunIsToldToRefresh() async throws {
    let service = service(runID: "run-two")
    try await perform(2, on: service)
    let events = await service.sequencedEvents(after: EventCursor(runID: "run-one", sequence: 2))
    #expect(try await take(1, from: events) == [.gap(.otherRun, current: EventCursor(runID: "run-two", sequence: 2))])
  }

  @Test func aClientAheadOfTheRunIsToldToRefresh() async throws {
    let service = service(runID: "run-one")
    try await perform(2, on: service)
    let events = await service.sequencedEvents(after: EventCursor(runID: "run-one", sequence: 9))
    #expect(try await take(1, from: events) == [.gap(.ahead, current: EventCursor(runID: "run-one", sequence: 2))])
  }

  @Test func aGapIsFollowedByLiveEvents() async throws {
    let service = service(runID: "run-one")
    let events = await service.sequencedEvents(after: EventCursor(runID: "other", sequence: 1))
    try await perform(1, on: service)
    let items = try await take(2, from: events)
    #expect(items.first == .gap(.otherRun, current: EventCursor(runID: "run-one", sequence: 0)))
    #expect(sequences(Array(items.dropFirst())) == [1])
  }

  @Test func aSlowSubscriberCanResumeFromTheNumberItReached() async throws {
    let service = service(runID: "run-one")
    let slow = await service.sequencedEvents(after: nil)
    try await perform(70, on: service)
    var reader = slow.makeAsyncIterator()
    var last: UInt64 = 0
    await #expect(throws: ServiceEventError.slowConsumer) {
      while let item = try await reader.next() { if case let .event(_, cursor) = item { last = cursor.sequence } }
    }
    #expect(last == 64)
    let resumed = await service.sequencedEvents(after: EventCursor(runID: "run-one", sequence: last))
    let items = try await take(6, from: resumed)
    #expect(sequences(items) == [65, 66, 67, 68, 69, 70])
  }

  // MARK: Cursor text

  @Test func aCursorRoundTripsThroughItsText() {
    let cursor = EventCursor(runID: "0123abcd", sequence: 42)
    #expect(cursor.token == "0123abcd-42")
    #expect(EventCursor(token: cursor.token) == cursor)
  }

  @Test(arguments: ["", "42", "-42", "run-", "run-x", "run--1", "a-b-3"])
  func textThatIsNotACursorIsRejected(_ token: String) {
    #expect(EventCursor(token: token) == nil)
  }
  // MARK: A modem that is away

  @Test func aSubscriberThatArrivesWhileTheModemIsAwayIsToldAtTheCurrentNumberWithoutUsingOne() async throws {
    let clock = TestClock()
    let opener = ScriptedOpener([.fail(hubAway)])
    let identity = ReportedIdentity(category: 1, subcategory: 125, firmwareVersion: 69)
    let snapshot = NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [address: identity]))
    let service = InsteonService(network: DeviceNetwork.offline(catalog: nil, snapshot: snapshot, hub: nil), opener: opener, clock: clock, now: { Date(timeIntervalSince1970: 1_800_000_000) }, jitter: { 0 }, runID: "run-one")
    try await withThrowingTaskGroup(of: Void.self) { group in
      let hostStopped = AsyncStream<Void>.makeStream()
      group.addTask { _ = try await service.run { for await _ in hostStopped.0 {} } }
      var attempts = opener.started.makeAsyncIterator()
      #expect(await attempts.next() == 1)
      await clock.waitForSleeper(until: .seconds(1))
      // The outage was the run's first event.
      let fresh = await service.sequencedEvents(after: nil)
      #expect(try await take(1, from: fresh) == [.event(.modemUnavailable(.hubUnreachable), EventCursor(runID: "run-one", sequence: 1))])
      // A client that saw nothing yet is replayed it.
      let missed = await service.sequencedEvents(after: EventCursor(runID: "run-one", sequence: 0))
      #expect(try await take(1, from: missed) == [.event(.modemUnavailable(.hubUnreachable), EventCursor(runID: "run-one", sequence: 1))])
      hostStopped.1.finish()
      try await group.waitForAll()
    }
  }
}
