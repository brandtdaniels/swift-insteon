import InsteonClient
import InsteonService
import InsteonTestSupport
import Testing

/// Reads items from a sequence until `count` have arrived.
private func take<Events: AsyncSequence>(_ count: Int, from events: Events) async throws -> [Events.Element] {
  var taken: [Events.Element] = []
  guard count > 0 else { return taken }
  for try await item in events {
    taken.append(item)
    if taken.count == count { break }
  }
  return taken
}

/// Wakes the connection's waits, each when it begins: the delays are the ones it is expected to wait.
private func release(_ delays: [Duration], on clock: TestClock) async {
  var deadline = Duration.zero
  for delay in delays {
    deadline += delay
    await clock.waitForSleeper(until: deadline)
    clock.advance(by: delay)
  }
}

@Suite("ClientConnection gives the service's events and keeps them across lost paths", .timeLimit(.minutes(1)))
struct ClientEventsTests {

  // Given a path that serves events, when a client subscribes, then it gets them in order
  // from the path the connection already uses.
  @Test func numberedEventsArriveInOrderFromThePathInUse() async throws {
    let path = EventPath("local", subscriptions: [.items([.position(cursor(0)), heard(1), heard(2)], ending: .held)])
    let connection = ClientConnection(paths: [path])
    _ = try await connection.devices()

    let items = try await take(3, from: connection.sequencedEvents(after: nil))

    #expect(items == [.position(cursor(0)), heard(1), heard(2)])
    #expect(await path.openCount == 1)
    #expect(await path.calls.requested == [nil])
  }

  // Given a cursor, when a client subscribes after it, then the service is asked to resume after it.
  @Test func aSubscriptionResumesAfterTheCursorItWasGiven() async throws {
    let path = EventPath("local", subscriptions: [.items([heard(8)], ending: .held)])
    let connection = ClientConnection(paths: [path])

    _ = try await take(1, from: connection.sequencedEvents(after: cursor(7)))

    #expect(await path.calls.requested == [cursor(7)])
  }

  // Given a path lost mid-stream, when the connection reconnects, then it waits the first delay
  // and resumes after the last event the client saw.
  @Test func aLostPathIsReopenedAfterADelayAndResumesFromTheLastCursor() async throws {
    let path = EventPath("local", subscriptions: [
      .items([heard(1), heard(2)], ending: .lost(.interrupted)),
      .items([heard(3)], ending: .held)
    ])
    let clock = TestClock()
    let connection = ClientConnection(paths: [path], clock: clock)

    async let items = take(3, from: connection.sequencedEvents(after: nil))
    await release([.seconds(1)], on: clock)

    #expect(try await items == [heard(1), heard(2), heard(3)])
    #expect(await path.openCount == 2)
    #expect(await path.calls.requested == [nil, cursor(2)])
  }

  // Given the preferred path is lost and does not come back, when the connection reconnects, then
  // the next path serves the events from the same cursor.
  @Test func aLostPathFallsBackToTheNextPathFromTheSameCursor() async throws {
    let local = EventPath("local", openings: [nil, .notReached("gone")], subscriptions: [.items([heard(1)], ending: .lost(.interrupted))])
    let remote = EventPath("remote", subscriptions: [.items([heard(2)], ending: .held)])
    let clock = TestClock()
    let connection = ClientConnection(paths: [local, remote], clock: clock)

    async let items = take(2, from: connection.sequencedEvents(after: nil))
    await release([.seconds(1)], on: clock)

    #expect(try await items == [heard(1), heard(2)])
    #expect(await remote.calls.requested == [cursor(1)])
    #expect(await connection.currentPath == "remote")
  }

  // Given the service can't replay what was missed, when it says so, then the client is told to
  // refresh and later resumes from the service's position, not its old one.
  @Test func aGapIsPassedOnAndTheCursorMovesToTheServicesPosition() async throws {
    let path = EventPath("local", subscriptions: [
      .items([heard(4)], ending: .lost(.interrupted)),
      .items([.gap(.otherRun, current: cursor(0, run: "run2")), heard(1, run: "run2")], ending: .lost(.interrupted)),
      .items([], ending: .held)
    ])
    let clock = TestClock()
    let connection = ClientConnection(paths: [path], clock: clock)

    async let items = take(3, from: connection.sequencedEvents(after: nil))
    await release([.seconds(1)], on: clock)
    #expect(try await items == [heard(4), .gap(.otherRun, current: cursor(0, run: "run2")), heard(1, run: "run2")])
    #expect(await path.calls.requested == [nil, cursor(4)])
  }

  // Given repeated failures, when the connection keeps trying, then each wait is longer, up to the
  // last delay, and an event restores the first.
  @Test func delaysGrowWithFailuresAndStartOverAfterAnEvent() async throws {
    let path = EventPath("local", openings: [nil, .notReached("a"), .notReached("b"), nil], subscriptions: [
      .items([heard(1)], ending: .lost(.interrupted)),
      .items([heard(2)], ending: .lost(.interrupted)),
      .items([heard(3)], ending: .held)
    ])
    let clock = TestClock()
    let connection = ClientConnection(paths: [path], retryDelays: [.seconds(1), .seconds(2), .seconds(4)], clock: clock)

    async let items = take(3, from: connection.sequencedEvents(after: nil))
    // Lost after event 1: 1 s. Two failed openings: 2 s, then 4 s. Event 2 restores 1 s.
    await release([.seconds(1), .seconds(2), .seconds(4), .seconds(1)], on: clock)

    #expect(try await items == [heard(1), heard(2), heard(3)])
  }

  // Given a client that stops reading, when it cancels, then the connection stops reconnecting.
  @Test func cancellationStopsTheReconnecting() async throws {
    let path = EventPath("local", subscriptions: [.items([heard(1)], ending: .lost(.interrupted))])
    let clock = TestClock()
    let connection = ClientConnection(paths: [path], clock: clock)
    let reader = Task { try await take(5, from: connection.sequencedEvents(after: nil)) }

    await clock.waitForSleeper(until: .seconds(1))
    reader.cancel()
    let items = try await reader.value

    #expect(items == [heard(1)])
    #expect(await path.openCount == 1)
  }

  // Given every path refuses the credential, when the client subscribes, then it is told so and
  // the connection does not retry.
  @Test func aRefusedCredentialEndsTheEventsWithoutRetrying() async throws {
    let path = EventPath("local", subscriptions: [.refuse(.unauthorized)])
    let connection = ClientConnection(paths: [path], clock: TestClock())

    await #expect(throws: ConnectionError.unauthorized(paths: ["local"])) {
      try await take(1, from: connection.sequencedEvents(after: nil))
    }
    #expect(await path.openCount == 1)
  }

  // Given a client that falls behind, when the service ends its subscription, then the connection
  // resubscribes on the same path from the last cursor.
  @Test func aSlowConsumerResubscribesOnTheSamePath() async throws {
    let path = EventPath("local", subscriptions: [
      .items([heard(1)], ending: .slowConsumer),
      .items([heard(2)], ending: .held)
    ])
    let clock = TestClock()
    let connection = ClientConnection(paths: [path], clock: clock)

    async let items = take(2, from: connection.sequencedEvents(after: nil))
    await release([.seconds(1)], on: clock)

    #expect(try await items == [heard(1), heard(2)])
    #expect(await path.openCount == 1)
    #expect(await path.calls.requested == [nil, cursor(1)])
  }

  // Given a path that carries no events, when a client subscribes, then the next path serves them.
  @Test func aPathThatCarriesNoEventsIsPassedOver() async throws {
    let local = ScriptedPath("local")
    let remote = EventPath("remote", subscriptions: [.items([heard(1)], ending: .held)])
    let connection = ClientConnection(paths: [local, remote], clock: TestClock())

    let items = try await take(1, from: connection.sequencedEvents(after: nil))

    #expect(items == [heard(1)])
    #expect(await connection.currentPath == "remote")
  }

  // Given numbered events and a gap, when a client asks for plain events, then it gets the events
  // and a refresh notice, and no positions.
  @Test func plainEventsCarryEventsAndRefreshNotices() async throws {
    let path = EventPath("local", subscriptions: [
      .items([.position(cursor(3)), heard(4), .gap(.tooOld, current: cursor(9)), heard(10)], ending: .held)
    ])
    let connection = ClientConnection(paths: [path])

    let events = try await take(3, from: connection.events())

    #expect(events == [.event(.statusChanged(lampAddress)), .refresh(.tooOld), .event(.statusChanged(lampAddress))])
  }
}
