import Foundation
import Testing
import InsteonScheduling

/// One schedule's runs across a change of the clocks, in a real time zone.
private struct Transition: CustomTestStringConvertible, Sendable {

  /// What the case shows, for the test's name.
  let name: String

  let zone: String

  let hour: Int

  let minute: Int

  /// Where the search starts, in UTC.
  let after: String

  /// The runs that follow, in UTC, one per day the schedule runs.
  let runs: [String]

  var testDescription: String { name }

}

struct DaylightSavingTests {

  private static let transitions = [
    Transition(
      name: "Los Angeles, spring forward: 2:30 runs once at 3:00 and the next day at 2:30",
      zone: "America/Los_Angeles", hour: 2, minute: 30, after: "2026-03-07T12:00:00Z",
      runs: ["2026-03-08T10:00:00Z", "2026-03-09T09:30:00Z", "2026-03-10T09:30:00Z"]
    ),
    Transition(
      name: "Los Angeles, fall back: 1:30 runs once, at its first occurrence",
      zone: "America/Los_Angeles", hour: 1, minute: 30, after: "2026-10-31T12:00:00Z",
      runs: ["2026-11-01T08:30:00Z", "2026-11-02T09:30:00Z", "2026-11-03T09:30:00Z"]
    ),
    Transition(
      name: "Los Angeles, a time that isn't affected: 2:30 in the afternoon is the same wall time",
      zone: "America/Los_Angeles", hour: 14, minute: 30, after: "2026-03-07T12:00:00Z",
      runs: ["2026-03-07T22:30:00Z", "2026-03-08T21:30:00Z", "2026-03-09T21:30:00Z"]
    ),
    Transition(
      name: "London, spring forward: 1:30 doesn't exist and runs at 2:00 summer time",
      zone: "Europe/London", hour: 1, minute: 30, after: "2026-03-28T12:00:00Z",
      runs: ["2026-03-29T01:00:00Z", "2026-03-30T00:30:00Z", "2026-03-31T00:30:00Z"]
    ),
    Transition(
      name: "London, fall back: 1:30 runs at its first occurrence, in summer time",
      zone: "Europe/London", hour: 1, minute: 30, after: "2026-10-24T12:00:00Z",
      runs: ["2026-10-25T00:30:00Z", "2026-10-26T01:30:00Z", "2026-10-27T01:30:00Z"]
    ),
    Transition(
      name: "Lord Howe, a 30 minute change: 2:15 runs when the half hour gap ends",
      zone: "Australia/Lord_Howe", hour: 2, minute: 15, after: "2026-10-02T12:00:00Z",
      runs: ["2026-10-02T15:45:00Z", "2026-10-03T15:30:00Z", "2026-10-04T15:15:00Z"]
    ),
    Transition(
      name: "Lord Howe, a 30 minute change: 1:45 runs at its first occurrence",
      zone: "Australia/Lord_Howe", hour: 1, minute: 45, after: "2026-04-03T12:00:00Z",
      runs: ["2026-04-03T14:45:00Z", "2026-04-04T14:45:00Z", "2026-04-05T15:15:00Z"]
    ),
    Transition(
      name: "Kolkata, a 30 minute offset with no change: 6:00 is 00:30 UTC every day",
      zone: "Asia/Kolkata", hour: 6, minute: 0, after: "2026-03-07T12:00:00Z",
      runs: ["2026-03-08T00:30:00Z", "2026-03-09T00:30:00Z"]
    ),
    Transition(
      name: "Sydney, southern hemisphere spring forward: 2:30 runs at 3:00",
      zone: "Australia/Sydney", hour: 2, minute: 30, after: "2026-10-02T12:00:00Z",
      runs: ["2026-10-02T16:30:00Z", "2026-10-03T16:00:00Z", "2026-10-04T15:30:00Z"]
    ),
    Transition(
      name: "Sydney, southern hemisphere fall back: 2:30 runs at its first occurrence",
      zone: "Australia/Sydney", hour: 2, minute: 30, after: "2026-04-03T12:00:00Z",
      runs: ["2026-04-03T15:30:00Z", "2026-04-04T15:30:00Z", "2026-04-05T16:30:00Z"]
    ),
    Transition(
      name: "Apia, a zone that skips a day: 10:00 runs on the 29th, then the 31st",
      zone: "Pacific/Apia", hour: 10, minute: 0, after: "2011-12-29T00:00:00Z",
      runs: ["2011-12-29T20:00:00Z", "2011-12-30T20:00:00Z", "2011-12-31T20:00:00Z"]
    ),
    Transition(
      name: "A new year: midnight runs on January 1",
      zone: "America/New_York", hour: 0, minute: 0, after: "2026-12-30T12:00:00Z",
      runs: ["2026-12-31T05:00:00Z", "2027-01-01T05:00:00Z", "2027-01-02T05:00:00Z"]
    ),
    Transition(
      name: "A leap day: 18:00 runs on February 29 in 2028",
      zone: "America/New_York", hour: 18, minute: 0, after: "2028-02-27T12:00:00Z",
      runs: ["2028-02-27T23:00:00Z", "2028-02-28T23:00:00Z", "2028-02-29T23:00:00Z", "2028-03-01T23:00:00Z"]
    ),
    Transition(
      name: "No leap day: 18:00 goes from February 28 to March 1 in 2027",
      zone: "America/New_York", hour: 18, minute: 0, after: "2027-02-27T12:00:00Z",
      runs: ["2027-02-27T23:00:00Z", "2027-02-28T23:00:00Z", "2027-03-01T23:00:00Z"]
    )
  ]

  private func calendar(_ zone: String) throws -> Calendar {

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: zone))

    return calendar

  }

  @Test(arguments: transitions)
  fileprivate func runsOncePerDayAcrossTheChange(_ transition: Transition) throws {

    let schedules = ScheduleCalendar(calendar: try calendar(transition.zone))
    let schedule = Schedule(time: .clock(hour: transition.hour, minute: transition.minute))

    var cursor = try Date(transition.after, strategy: .iso8601)
    var runs: [Date] = []

    for _ in transition.runs {

      let run = try #require(schedules.nextRun(of: schedule, after: cursor))
      runs.append(run)
      cursor = run

    }

    #expect(runs == (try transition.runs.map { try Date($0, strategy: .iso8601) }))

  }

  // The same instant is never returned twice, and the next run is always after the last.
  @Test func neverRunsAnInstantTwiceAcrossAYearOfDays() throws {

    for zone in ["America/Los_Angeles", "Europe/London", "Australia/Lord_Howe", "Australia/Sydney"] {

      let schedules = ScheduleCalendar(calendar: try calendar(zone))

      for (hour, minute) in [(1, 30), (2, 0), (2, 30), (3, 0)] {

        let schedule = Schedule(time: .clock(hour: hour, minute: minute))
        var cursor = try Date("2026-01-01T00:00:00Z", strategy: .iso8601)
        var count = 0

        while cursor < (try Date("2027-01-01T00:00:00Z", strategy: .iso8601)) {

          let run = try #require(schedules.nextRun(of: schedule, after: cursor))
          #expect(run > cursor)
          cursor = run
          count += 1

        }

        // One run each day of 2026, with the last one landing on New Year's Day 2027 in the zones ahead of UTC.
        #expect((364...366).contains(count), "\(zone) \(hour):\(minute) ran \(count) times")

      }

    }

  }

  // Sunrise is worked out in UTC for each date, so around a change it moves by about a minute,
  // never by the hour the clocks change by.
  @Test func sunTimesAreContinuousAcrossTheChange() throws {

    let location = try #require(GeographicCoordinate(latitude: 34.05, longitude: -118.24))
    let schedules = ScheduleCalendar(calendar: try calendar("America/Los_Angeles"), sunTimes: SolarCalculator(location: location))
    let sunrise = Schedule(time: .sunrise(offset: .zero))

    var cursor = try Date("2026-03-06T12:00:00Z", strategy: .iso8601)
    var runs: [Date] = []

    for _ in 0..<5 {

      let run = try #require(schedules.nextRun(of: sunrise, after: cursor))
      runs.append(run)
      cursor = run

    }

    for (earlier, later) in zip(runs, runs.dropFirst()) {

      let gap = later.timeIntervalSince(earlier)
      #expect((86_400 - 180...86_400).contains(gap), "gap \(gap)")

    }

  }

}
