import Foundation
import InsteonModem
import InsteonProtocol
import InsteonScheduling
import InsteonTestSupport
import Testing
@testable import InsteonService

/// The scheduler's behavior over a hand-set wall clock and a test clock. Nothing waits on time: a test sets
/// the wall clock, moves the test clock and asks for a pass, or waits for the loop's own sleep and events.
@Suite(.timeLimit(.minutes(1)))
struct SchedulerTests {

  // MARK: Create and manage

  @Test func storesAScheduleAndListsItWithItsNextRun() async throws {
    let h = SchedulerHarness()
    let entry = try await h.scheduler.putSchedule(lampSchedule(when: daily(8, 0)))

    // 8:00 a.m. on March 8 is after the clocks spring forward: 15:00 UTC.
    #expect(entry.nextRun == utc("2026-03-08T15:00:00Z"))
    #expect(try await h.scheduler.schedules() == [entry])
    #expect(h.store.stored?.schedules == [lampSchedule(when: daily(8, 0))])
    #expect(h.store.stored?.settings == ScheduleSettings(timeZoneIdentifier: "America/Los_Angeles", location: GeographicCoordinate(latitude: 34.05, longitude: -118.24)))
  }

  @Test(arguments: [
    (lampSchedule(when: daily(8, 0), action: ScheduledAction(device: InsteonAddress(0x09, 0x09, 0x09), kind: .off)), ScheduleError.unknownDevice),
    (lampSchedule(when: daily(8, 0), action: ScheduledAction(device: FakeScheduleHost.sensor, kind: .off)), ScheduleError.unsupportedAction),
    (lampSchedule(when: daily(8, 0), action: ScheduledAction(device: FakeScheduleHost.relay, kind: .on(levelPercent: 50))), ScheduleError.unsupportedAction),
    (lampSchedule(when: daily(8, 0), action: ScheduledAction(device: FakeScheduleHost.lamp, kind: .on(levelPercent: 101))), ScheduleError.invalidSchedule),
    (lampSchedule(when: daily(24, 0)), ScheduleError.invalidSchedule),
    (lampSchedule(when: daily(8, 60)), ScheduleError.invalidSchedule),
    (lampSchedule(when: daily(8, 0, on: [])), ScheduleError.invalidSchedule),
    (lampSchedule("", when: daily(8, 0)), ScheduleError.invalidSchedule),
    (lampSchedule("has space", when: daily(8, 0)), ScheduleError.invalidSchedule),
    (ServiceSchedule(id: "porch", name: "  ", when: daily(8, 0), action: ScheduledAction(device: FakeScheduleHost.lamp, kind: .off)), ScheduleError.invalidSchedule),
    (lampSchedule(when: Schedule(time: .sunset(offset: .seconds(13 * 3600)))), ScheduleError.invalidSchedule)
  ])
  func refusesAScheduleThatBreaksALimitAndSavesNothing(_ schedule: ServiceSchedule, _ error: ScheduleError) async throws {
    let h = SchedulerHarness()
    _ = try await h.scheduler.schedules()
    let saves = h.store.saves

    await #expect(throws: error) { try await h.scheduler.putSchedule(schedule) }

    #expect(try await h.scheduler.schedules().isEmpty)
    #expect(h.store.saves == saves)
  }

  @Test func anEditTakesEffectAtOnceAndKeepsNothingOfTheLastRun() async throws {
    let h = SchedulerHarness(at: "2026-03-08T14:59:00Z")
    _ = try await h.scheduler.putSchedule(lampSchedule(when: daily(8, 0)))
    h.wall.set("2026-03-08T15:00:10Z")
    await h.scheduler.tick()
    #expect(h.host.commands.count == 1)

    // The edit moves the time to half past eight, after the run that just happened.
    let edited = try await h.scheduler.putSchedule(lampSchedule(when: daily(8, 30)))
    #expect(edited.nextRun == utc("2026-03-08T15:30:00Z"))

    h.wall.set("2026-03-08T15:30:05Z")
    await h.scheduler.tick()
    #expect(h.host.commands.count == 2)
  }

  @Test func disablingOrDeletingAScheduleStopsItAtOnce() async throws {
    let h = SchedulerHarness()
    _ = try await h.scheduler.putSchedule(lampSchedule("a", when: daily(8, 0)))
    _ = try await h.scheduler.putSchedule(lampSchedule("b", when: daily(8, 0)))

    let disabled = try await h.scheduler.putSchedule(lampSchedule("a", when: daily(8, 0), enabled: false))
    #expect(disabled.nextRun == nil)
    try await h.scheduler.removeSchedule(id: "b")

    h.wall.set("2026-03-08T15:00:05Z")
    await h.scheduler.tick()

    #expect(h.host.commands.isEmpty)
    #expect(h.host.events.isEmpty)
    await #expect(throws: ScheduleError.unknownSchedule) { try await h.scheduler.removeSchedule(id: "b") }
  }

  @Test func refusesTheSixtyFifthScheduleAndTimerButReplacesOneAtTheLimit() async throws {
    let h = SchedulerHarness()
    for number in 0..<ServiceSchedule.maximumCount { _ = try await h.scheduler.putSchedule(lampSchedule("s\(number)", when: daily(8, 0))) }
    for number in 0..<ServiceTimer.maximumCount { _ = try await h.scheduler.putTimer(ServiceTimer(id: "t\(number)", name: "Timer", delaySeconds: 600, action: ScheduledAction(device: FakeScheduleHost.lamp, kind: .off))) }

    await #expect(throws: ScheduleError.scheduleLimitReached) { try await h.scheduler.putSchedule(lampSchedule("extra", when: daily(8, 0))) }
    await #expect(throws: ScheduleError.timerLimitReached) { try await h.scheduler.putTimer(ServiceTimer(id: "extra", name: "Timer", delaySeconds: 600, action: ScheduledAction(device: FakeScheduleHost.lamp, kind: .off))) }

    _ = try await h.scheduler.putSchedule(lampSchedule("s0", when: daily(9, 0)))
    _ = try await h.scheduler.putTimer(ServiceTimer(id: "t0", name: "Timer", delaySeconds: 60, action: ScheduledAction(device: FakeScheduleHost.lamp, kind: .off)))
    #expect(try await h.scheduler.schedules().count == ServiceSchedule.maximumCount)
    #expect(try await h.scheduler.timers().count == ServiceTimer.maximumCount)
  }

  @Test func changesNothingWhenTheStoredSchedulesCantBeReadOrSaved() async throws {
    let h = SchedulerHarness()
    h.store.failLoading(true)
    await #expect(throws: ScheduleError.notSaved) { try await h.scheduler.schedules() }
    await #expect(throws: ScheduleError.notSaved) { try await h.scheduler.putSchedule(lampSchedule(when: daily(8, 0))) }

    h.store.failLoading(false)
    h.store.failSaving(true)
    await #expect(throws: ScheduleError.notSaved) { try await h.scheduler.putSchedule(lampSchedule(when: daily(8, 0))) }
    #expect(try await h.scheduler.schedules().isEmpty)

    h.store.failSaving(false)
    _ = try await h.scheduler.putSchedule(lampSchedule(when: daily(8, 0)))
    #expect(try await h.scheduler.schedules().count == 1)
  }

  // MARK: Run

  @Test func runsOnceAtItsTimeOnItsWeekdaysAndPublishesTheRun() async throws {
    // Saturday, March 7, 2026, noon in Los Angeles; the schedule is for Monday and Tuesday at 8:00 a.m.
    let h = SchedulerHarness()
    let entry = try await h.scheduler.putSchedule(lampSchedule(when: daily(8, 0, on: [.monday, .tuesday])))
    #expect(entry.nextRun == utc("2026-03-09T15:00:00Z"))

    h.wall.set("2026-03-08T15:00:05Z")
    await h.scheduler.tick()
    #expect(h.host.commands.isEmpty)

    h.wall.set("2026-03-09T15:00:05Z")
    await h.scheduler.tick()
    await h.scheduler.tick()

    #expect(h.host.commands == [ServiceCommand(address: FakeScheduleHost.lamp, action: .on, levelPercent: 80)])
    #expect(h.host.events == [ScheduleRun(source: .schedule, id: "porch", name: "Porch light", device: FakeScheduleHost.lamp, outcome: .acknowledged, firedAt: utc("2026-03-09T15:00:05Z"), nextRun: utc("2026-03-10T15:00:00Z"))])
  }

  @Test func sunsetUsesTheSunSourceAndAnOffset() async throws {
    let h = SchedulerHarness(sunTimes: { _ in FixedSunTimes() })
    let entry = try await h.scheduler.putSchedule(lampSchedule(when: Schedule(time: .sunset(offset: .seconds(-15 * 60)))))

    // 18:45 on March 7 is 02:45 UTC the next day, standard time.
    #expect(entry.nextRun == utc("2026-03-08T02:45:00Z"))
  }

  @Test func refusesASunScheduleWithoutALocationAndSaysWhatIsMissing() async throws {
    let h = SchedulerHarness(location: nil)

    await #expect(throws: ScheduleError.locationMissing) { try await h.scheduler.putSchedule(lampSchedule(when: Schedule(time: .sunrise(offset: .zero)))) }
    _ = try await h.scheduler.putSchedule(lampSchedule(when: daily(8, 0)))
  }

  @Test func reportsAnUnavailableDeviceDoesNotRetryAndRunsTheNextDay() async throws {
    let h = SchedulerHarness()
    _ = try await h.scheduler.putSchedule(lampSchedule(when: daily(8, 0)))
    h.host.fail(with: ServiceControlError.modemUnavailable(.hubUnreachable))

    h.wall.set("2026-03-08T15:00:05Z")
    await h.scheduler.tick()
    h.wall.set("2026-03-08T15:00:35Z")
    await h.scheduler.tick()

    #expect(h.host.commands.count == 1)
    #expect(h.host.events.map(\.outcome) == [.unavailable(.hubUnreachable)])

    h.host.fail(with: nil)
    h.wall.set("2026-03-09T15:00:05Z")
    await h.scheduler.tick()
    #expect(h.host.commands.count == 2)
    #expect(h.host.events.map(\.outcome) == [.unavailable(.hubUnreachable), .acknowledged])
  }

  @Test(arguments: [
    (ServiceControlError.notLinked as any Error, ScheduleRun.Outcome.refused(.notLinked)),
    (ServiceControlError.busy as any Error, ScheduleRun.Outcome.refused(.busy)),
    (ModemError.deviceTimedOut(FakeScheduleHost.lamp) as any Error, ScheduleRun.Outcome.unknown)
  ])
  func nameswhatCameOfACommandThatFailed(_ failure: any Error, _ outcome: ScheduleRun.Outcome) async throws {
    let h = SchedulerHarness()
    _ = try await h.scheduler.putSchedule(lampSchedule(when: daily(8, 0)))
    h.host.fail(with: failure)

    h.wall.set("2026-03-08T15:00:05Z")
    await h.scheduler.tick()

    #expect(h.host.events.map(\.outcome) == [outcome])
  }

  // MARK: Missed runs

  @Test func skipsARunMissedWhileStoppedAndReportsItOnce() async throws {
    let h = SchedulerHarness()
    _ = try await h.scheduler.putSchedule(lampSchedule(when: daily(8, 0)))

    // Stopped across two run times; started again on March 9 at 1 p.m.
    h.wall.set("2026-03-09T20:00:00Z")
    let restarted = h.restarted()
    await restarted.scheduler.tick()

    #expect(h.host.commands.isEmpty)
    #expect(h.host.events.map(\.outcome) == [.missed])
    #expect(h.host.events.first?.nextRun == utc("2026-03-10T15:00:00Z"))
    #expect(try await restarted.scheduler.schedules().first?.nextRun == utc("2026-03-10T15:00:00Z"))
  }

  @Test func catchesUpAMissedRunLessThanFifteenMinutesLateOnlyWhenAskedTo() async throws {
    let h = SchedulerHarness()
    _ = try await h.scheduler.putSchedule(lampSchedule("catches", when: daily(8, 0), catchUp: true))
    _ = try await h.scheduler.putSchedule(lampSchedule("skips", when: daily(8, 0)))

    h.wall.set("2026-03-08T15:10:00Z")
    await h.restarted().scheduler.tick()

    #expect(h.host.events.map(\.id) == ["catches", "skips"])
    #expect(h.host.events.map(\.outcome) == [.acknowledged, .missed])
    #expect(h.host.commands.count == 1)
  }

  @Test func doesNotCatchUpARunMoreThanFifteenMinutesLate() async throws {
    let h = SchedulerHarness()
    _ = try await h.scheduler.putSchedule(lampSchedule(when: daily(8, 0), catchUp: true))

    h.wall.set("2026-03-08T15:16:00Z")
    await h.restarted().scheduler.tick()

    #expect(h.host.commands.isEmpty)
    #expect(h.host.events.map(\.outcome) == [.missed])
  }

  @Test func neverRepeatsARunWhenTheClockIsSetBackAndCountsAForwardJumpAsMissed() async throws {
    let h = SchedulerHarness(at: "2026-03-08T14:00:00Z")
    _ = try await h.scheduler.putSchedule(lampSchedule("morning", when: daily(8, 0)))
    _ = try await h.scheduler.putSchedule(lampSchedule("noon", when: daily(12, 0)))

    h.wall.set("2026-03-08T15:00:05Z")
    await h.scheduler.tick()
    #expect(h.host.events.map(\.id) == ["morning"])

    // Set back an hour, then forward again past the run time: the run isn't repeated.
    h.wall.set("2026-03-08T14:00:00Z")
    await h.scheduler.tick()
    h.wall.set("2026-03-08T15:00:30Z")
    await h.scheduler.tick()
    #expect(h.host.commands.count == 1)

    // Set forward three hours, past noon: counted as missed.
    h.wall.set("2026-03-08T22:00:00Z")
    await h.scheduler.tick()
    #expect(h.host.events.map(\.outcome) == [.acknowledged, .missed])
    #expect(h.host.events.last?.id == "noon")
  }

  // MARK: Daylight saving time

  @Test func runsATimeTheClocksSkipOnceWhenTheSkippedHourEnds() async throws {
    let h = SchedulerHarness()
    let entry = try await h.scheduler.putSchedule(lampSchedule(when: daily(2, 30)))
    #expect(entry.nextRun == utc("2026-03-08T10:00:00Z"))

    h.wall.set("2026-03-08T09:59:59Z")
    await h.scheduler.tick()
    #expect(h.host.commands.isEmpty)

    h.wall.set("2026-03-08T10:00:00Z")
    await h.scheduler.tick()
    await h.scheduler.tick()

    #expect(h.host.commands.count == 1)
    #expect(h.host.events.first?.nextRun == utc("2026-03-09T09:30:00Z"))
  }

  @Test func runsATimeThatHappensTwiceOnceAtItsFirstOccurrence() async throws {
    let h = SchedulerHarness(at: "2026-10-31T20:00:00Z")
    let entry = try await h.scheduler.putSchedule(lampSchedule(when: daily(1, 30)))
    #expect(entry.nextRun == utc("2026-11-01T08:30:00Z"))

    h.wall.set("2026-11-01T08:30:00Z")
    await h.scheduler.tick()
    #expect(h.host.commands.count == 1)

    // The second 1:30 a.m., an hour later, does not run.
    h.wall.set("2026-11-01T09:30:00Z")
    await h.scheduler.tick()
    #expect(h.host.commands.count == 1)
    #expect(try await h.scheduler.schedules().first?.nextRun == utc("2026-11-02T09:30:00Z"))
  }

  @Test func runsSunsetEveryDayAcrossTheChangeWithNoRepeatOrSkip() async throws {
    let h = SchedulerHarness(at: "2026-03-06T12:00:00Z")
    var entry = try await h.scheduler.putSchedule(lampSchedule(when: Schedule(time: .sunset(offset: .zero))))
    var runs: [Date] = []

    for _ in 0..<5 {
      let run = try #require(entry.nextRun)
      runs.append(run)
      h.wall.set(run)
      await h.scheduler.tick()
      entry = try #require(try await h.scheduler.schedules().first)
    }

    #expect(h.host.commands.count == 5)
    // Sunset comes about a minute later each day in March, in UTC, never by the hour the clocks change by.
    for (earlier, later) in zip(runs, runs.dropFirst()) {
      #expect((86_400...86_400 + 180).contains(later.timeIntervalSince(earlier)))
    }
  }

  @Test func recomputesEveryScheduleFromItsWallClockTimeWhenTheTimeZoneChanges() async throws {
    let h = SchedulerHarness(zone: "America/Los_Angeles", at: "2026-03-07T20:00:00Z")
    _ = try await h.scheduler.putSchedule(lampSchedule(when: daily(8, 0)))

    let restarted = h.restarted(zone: "Europe/London")
    let entry = try #require(try await restarted.scheduler.schedules().first)

    // 8:00 a.m. in London is 08:00 UTC on March 8, before the clocks there change.
    #expect(entry.nextRun == utc("2026-03-08T08:00:00Z"))
    #expect(h.store.stored?.settings.timeZoneIdentifier == "Europe/London")
  }

  @Test func refusesAClockTimeInAZoneTheHostDoesntHaveAndReportsIt() async throws {
    let h = SchedulerHarness(zone: "Not/AZone")

    await #expect(throws: ScheduleError.timeZoneUnavailable) { try await h.scheduler.putSchedule(lampSchedule(when: daily(8, 0))) }
    #expect(await h.scheduler.notes == [.timeZoneUnavailable("Not/AZone")])
    #expect(try await h.scheduler.schedules().isEmpty)
  }

  @Test func remembersTheSettingsTheHostChoseForTheNextStart() async throws {
    let h = SchedulerHarness()
    _ = try await h.scheduler.schedules()

    let restarted = h.restarted(zone: nil, location: nil)
    let entry = try await restarted.scheduler.putSchedule(lampSchedule(when: Schedule(time: .sunset(offset: .zero))))

    #expect(entry.nextRun != nil)
    #expect(await restarted.scheduler.notes.isEmpty)
  }

  // MARK: Timers

  @Test func firesATimerOnceAfterItsDelayAndRemovesIt() async throws {
    let h = SchedulerHarness()
    let entry = try await h.scheduler.putTimer(ServiceTimer(id: "porch-off", name: "Porch off", delaySeconds: 300, action: ScheduledAction(device: FakeScheduleHost.lamp, kind: .off)))
    #expect(entry.dueAt == h.wall.now.addingTimeInterval(300))
    #expect(entry.remainingSeconds == 300)

    h.clock.advance(by: .seconds(299))
    await h.scheduler.tick()
    #expect(h.host.commands.isEmpty)

    h.clock.advance(by: .seconds(1))
    await h.scheduler.tick()
    await h.scheduler.tick()

    #expect(h.host.commands == [ServiceCommand(address: FakeScheduleHost.lamp, action: .off)])
    #expect(h.host.events.map(\.source) == [.timer])
    #expect(h.host.events.first?.nextRun == nil)
    #expect(try await h.scheduler.timers().isEmpty)
    #expect(h.store.stored?.timers.isEmpty == true)
  }

  @Test func aTimerCountsElapsedTimeSoAChangeOfTheWallClockDoesNotMoveIt() async throws {
    let h = SchedulerHarness()
    _ = try await h.scheduler.putTimer(ServiceTimer(id: "t", name: "Timer", delaySeconds: 300, action: ScheduledAction(device: FakeScheduleHost.lamp, kind: .off)))

    h.wall.advance(by: 3 * 3600)
    await h.scheduler.tick()
    h.wall.advance(by: -6 * 3600)
    await h.scheduler.tick()
    #expect(h.host.commands.isEmpty)

    h.clock.advance(by: .seconds(300))
    await h.scheduler.tick()
    #expect(h.host.commands.count == 1)
  }

  @Test func cancelingATimerStopsIt() async throws {
    let h = SchedulerHarness()
    _ = try await h.scheduler.putTimer(ServiceTimer(id: "t", name: "Timer", delaySeconds: 60, action: ScheduledAction(device: FakeScheduleHost.lamp, kind: .off)))
    try await h.scheduler.removeTimer(id: "t")

    h.clock.advance(by: .seconds(60))
    await h.scheduler.tick()

    #expect(h.host.commands.isEmpty)
    await #expect(throws: ScheduleError.unknownTimer) { try await h.scheduler.removeTimer(id: "t") }
  }

  @Test(arguments: [0, -5, ServiceTimer.longestDelaySeconds + 1])
  func refusesATimerWithADelayOutOfRange(_ delay: Int) async throws {
    let h = SchedulerHarness()
    await #expect(throws: ScheduleError.invalidTimer) { try await h.scheduler.putTimer(ServiceTimer(id: "t", name: "Timer", delaySeconds: delay, action: ScheduledAction(device: FakeScheduleHost.lamp, kind: .off))) }
  }

  // MARK: The loop

  @Test func theLoopRunsAScheduleWhenTheClockReachesItAndSavesTheTimeATimerHasLeftWhenItStops() async throws {
    let h = SchedulerHarness(at: "2026-03-08T14:59:30Z")
    _ = try await h.scheduler.putSchedule(lampSchedule(when: daily(8, 0)))
    let scheduler = h.scheduler
    let loop = Task { await scheduler.run() }

    await h.clock.waitForSleeper(until: .seconds(30))
    h.wall.set("2026-03-08T15:00:00Z")
    h.clock.advance(by: .seconds(30))
    var events = h.host.runs.makeAsyncIterator()
    let run = await events.next()
    #expect(run?.outcome == .acknowledged)

    // A timer set while the loop sleeps wakes it; it is stored with the time it has left when the loop stops.
    let mark = h.clock.mark()
    _ = try await h.scheduler.putTimer(ServiceTimer(id: "t", name: "Timer", delaySeconds: 300, action: ScheduledAction(device: FakeScheduleHost.lamp, kind: .off)))
    await h.clock.waitForSleeper(until: .seconds(60), after: mark)
    h.clock.advance(by: .seconds(120))
    await h.clock.waitForSleeper(until: .seconds(180))
    loop.cancel()
    await loop.value

    let remaining = try #require(h.store.stored?.timers.first?.remainingSeconds)
    #expect(remaining == 180)

    // A restart picks the timer up with 180 seconds left, whatever the wall clock says.
    h.wall.advance(by: 3600)
    let restarted = h.restarted(clock: TestClock())
    #expect(try await restarted.scheduler.timers().first?.remainingSeconds == 180)
    restarted.clock.advance(by: .seconds(179))
    await restarted.scheduler.tick()
    #expect(h.host.commands.count == 1)
    restarted.clock.advance(by: .seconds(1))
    await restarted.scheduler.tick()
    #expect(h.host.commands.count == 2)
  }

}
