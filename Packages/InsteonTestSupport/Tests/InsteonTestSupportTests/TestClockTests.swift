import Testing
import InsteonTestSupport

/// ``TestClock``'s sleeps, advances, cancellation and waits for sleepers.
@Suite(.timeLimit(.minutes(1)))
struct TestClockTests {

  let clock = TestClock()

  /// A task that sleeps on the clock until `offset` past its start.
  func startSleep(until offset: Duration) -> Task<Void, any Error> {

    Task { [clock] in

      try await clock.sleep(until: TestClock.Instant(offset: offset))

    }

  }

  @Test func aSleepEndsWhenTheClockReachesItsDeadline() async throws {

    let sleep = startSleep(until: .seconds(5))
    await clock.waitForSleeper(until: .seconds(5))

    clock.advance(by: .seconds(4))
    #expect(clock.sleeperCount(until: .seconds(5)) == 1)

    clock.advance(by: .seconds(1))
    try await sleep.value

    #expect(clock.now == TestClock.Instant(offset: .seconds(5)))
    #expect(clock.sleeperCount(until: .seconds(5)) == 0)

  }

  @Test func aSleepUntilADeadlineThatHasPassedEndsAtOnce() async throws {

    clock.advance(by: .seconds(5))

    try await clock.sleep(until: TestClock.Instant(offset: .seconds(3)))
    try await clock.sleep(until: TestClock.Instant(offset: .seconds(5)))
    try await clock.sleep(for: .zero)

    #expect(clock.sleeperCount(until: .seconds(5)) == 0)

  }

  @Test func advancingEndsEverySleepItReachesAndNoOther() async throws {

    let early = startSleep(until: .seconds(1))
    let late = startSleep(until: .seconds(3))
    let later = startSleep(until: .seconds(10))
    await clock.waitForSleeper(until: .seconds(1))
    await clock.waitForSleeper(until: .seconds(3))
    await clock.waitForSleeper(until: .seconds(10))

    clock.advance(by: .seconds(5))
    try await early.value
    try await late.value

    #expect(clock.sleeperCount(until: .seconds(10)) == 1)

    later.cancel()
    await #expect(throws: CancellationError.self) { try await later.value }

  }

  @Test func cancelingASleepEndsItWithCancellationError() async throws {

    let sleep = startSleep(until: .seconds(5))
    await clock.waitForSleeper(until: .seconds(5))

    sleep.cancel()

    await #expect(throws: CancellationError.self) { try await sleep.value }
    #expect(clock.sleeperCount(until: .seconds(5)) == 0)

    // Reaching the deadline afterward has nothing to end; a second resumption would trap.
    clock.advance(by: .seconds(5))

  }

  @Test func aSleepCanceledBeforeItStartsEndsAtOnce() async throws {

    let sleep = Task { [clock] in

      withUnsafeCurrentTask { (task: UnsafeCurrentTask?) -> Void in task?.cancel() }
      try await clock.sleep(until: TestClock.Instant(offset: .seconds(5)))

    }

    await #expect(throws: CancellationError.self) { try await sleep.value }
    #expect(clock.sleeperCount(until: .seconds(5)) == 0)

  }

  @Test func twoSleepsWithTheSameDeadlineBothEnd() async throws {

    let first = startSleep(until: .seconds(5))
    let second = startSleep(until: .seconds(5))
    await clock.waitForSleepers(2, until: .seconds(5))

    #expect(clock.sleeperCount(until: .seconds(5)) == 2)

    clock.advance(by: .seconds(5))
    try await first.value
    try await second.value

  }

  @Test func aWaitForASleeperEndsAtOnceForOneAlreadySleeping() async throws {

    let sleep = startSleep(until: .seconds(5))
    await clock.waitForSleeper(until: .seconds(5))

    // The sleep is still waiting, so this returns without another.
    await clock.waitForSleeper(until: .seconds(5))

    clock.advance(by: .seconds(5))
    try await sleep.value

  }

  @Test func aWaitAfterAMarkIgnoresASleepThatStartedBeforeIt() async throws {

    let first = startSleep(until: .seconds(5))
    await clock.waitForSleeper(until: .seconds(5))
    let mark = clock.mark()

    let waiter = Task { [clock] in

      await clock.waitForSleeper(until: .seconds(5), after: mark)

      // Only a sleep that started after the mark ends the wait, so both are sleeping by now.
      return clock.sleeperCount(until: .seconds(5))

    }
    let second = startSleep(until: .seconds(5))

    #expect(await waiter.value == 2)

    clock.advance(by: .seconds(5))
    try await first.value
    try await second.value

  }

  @Test func aWaitAfterAMarkCountsOnlyTheDeadlineItNames() async throws {

    let mark = clock.mark()
    let other = startSleep(until: .seconds(3))
    await clock.waitForSleeper(until: .seconds(3), after: mark)
    let sleep = startSleep(until: .seconds(5))

    await clock.waitForSleeper(until: .seconds(5), after: mark)
    #expect(clock.sleeperCount(until: .seconds(5)) == 1)

    clock.advance(by: .seconds(5))
    try await other.value
    try await sleep.value

  }

  @Test func cancelingAWaitForASleeperEndsIt() async throws {

    let waiter = Task { [clock] in

      await clock.waitForSleeper(until: .seconds(5))

    }

    waiter.cancel()
    await waiter.value

    // A sleep afterward doesn't resume the canceled wait a second time, which would trap.
    let sleep = startSleep(until: .seconds(5))
    await clock.waitForSleeper(until: .seconds(5))
    clock.advance(by: .seconds(5))
    try await sleep.value

  }

}
