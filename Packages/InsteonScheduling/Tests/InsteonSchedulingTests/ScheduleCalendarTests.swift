import Foundation
import Testing
import InsteonScheduling

/// Sunrise at 7:00 and sunset at 19:00 local time, every day.
struct FixedSunTimes: SunTimes {

  func sunrise(on day: Date, in calendar: Calendar) -> Date? {

    calendar.date(bySettingHour: 7, minute: 0, second: 0, of: day)

  }

  func sunset(on day: Date, in calendar: Calendar) -> Date? {

    calendar.date(bySettingHour: 19, minute: 0, second: 0, of: day)

  }

}

/// Schedules in Denver, where in 2026 the clocks spring forward on March 8 and fall back on
/// November 1.
struct ScheduleCalendarTests {

  let schedules: ScheduleCalendar

  init() throws {

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/Denver"))
    schedules = ScheduleCalendar(calendar: calendar, sunTimes: FixedSunTimes())

  }

  func date(_ text: String) throws -> Date {

    try Date(text, strategy: .iso8601)

  }

  @Test func runsAtTheSameLocalTimeOnEitherSideOfTheChange() throws {

    let evening = Schedule(time: .clock(hour: 18, minute: 30))

    // 6:30 p.m. is 01:30 UTC in standard time and 00:30 UTC in daylight time.
    #expect(schedules.nextRun(of: evening, after: try date("2026-03-07T12:00:00Z")) == (try date("2026-03-08T01:30:00Z")))
    #expect(schedules.nextRun(of: evening, after: try date("2026-03-09T12:00:00Z")) == (try date("2026-03-10T00:30:00Z")))

  }

  // 2:30 a.m. doesn't exist on March 8, so it runs at 3:30 a.m. daylight time.
  @Test func runsATimeTheClocksSkipAfterTheChange() throws {

    let early = Schedule(time: .clock(hour: 2, minute: 30))

    #expect(schedules.nextRun(of: early, after: try date("2026-03-07T12:00:00Z")) == (try date("2026-03-08T09:30:00Z")))

  }

  // 1:30 a.m. happens twice on November 1; the first is in daylight time.
  @Test func runsATimeTheClocksRepeatTheFirstTime() throws {

    let early = Schedule(time: .clock(hour: 1, minute: 30))

    #expect(schedules.nextRun(of: early, after: try date("2026-11-01T06:00:00Z")) == (try date("2026-11-01T07:30:00Z")))

  }

  @Test func runsOnlyOnItsWeekdays() throws {

    let monday = Schedule(time: .clock(hour: 8, minute: 0), weekdays: [.monday])

    // Saturday, March 7, to Monday, March 9, at 8:00 a.m. daylight time.
    #expect(schedules.nextRun(of: monday, after: try date("2026-03-07T12:00:00Z")) == (try date("2026-03-09T14:00:00Z")))

  }

  @Test func runsRelativeToSunriseAndSunset() throws {

    let beforeSunrise = Schedule(time: .sunrise(offset: .seconds(-30 * 60)))
    let afterSunset = Schedule(time: .sunset(offset: .seconds(15 * 60)))

    // 6:30 a.m. and 7:15 p.m. daylight time on March 10.
    #expect(schedules.nextRun(of: beforeSunrise, after: try date("2026-03-10T06:00:00Z")) == (try date("2026-03-10T12:30:00Z")))
    #expect(schedules.nextRun(of: afterSunset, after: try date("2026-03-10T06:00:00Z")) == (try date("2026-03-11T01:15:00Z")))

  }

  // Six hours after the 19:00 sunset is 1:00 the next morning. Just after midnight, that run,
  // from the day before's sunset, is the next one.
  @Test func findsARunAnOffsetMovedPastMidnight() throws {

    let late = Schedule(time: .sunset(offset: .seconds(6 * 3600)))

    // 00:10 daylight time on March 11, to 01:00 daylight time.
    #expect(schedules.nextRun(of: late, after: try date("2026-03-11T06:10:00Z")) == (try date("2026-03-11T07:00:00Z")))

  }

  // Eight hours before the 7:00 sunrise is 23:00 the night before, so a Monday schedule runs
  // late on Monday, from Tuesday's sunrise.
  @Test func countsWeekdaysByTheDayTheRunHappens() throws {

    let monday = Schedule(time: .sunrise(offset: .seconds(-8 * 3600)), weekdays: [.monday])

    // From Saturday, March 7, to 23:00 daylight time on Monday, March 9.
    #expect(schedules.nextRun(of: monday, after: try date("2026-03-07T12:00:00Z")) == (try date("2026-03-10T05:00:00Z")))

  }

  @Test(arguments: [(24, 0), (18, 75), (-1, 0)])
  func neverRunsAtAClockTimeThatDoesntExist(_ hour: Int, _ minute: Int) throws {

    #expect(schedules.nextRun(of: Schedule(time: .clock(hour: hour, minute: minute)), after: try date("2026-03-10T06:00:00Z")) == nil)

  }

  @Test func neverRunsWithoutSunTimesOrWeekdays() throws {

    let calendar = schedules.calendar
    let clockOnly = ScheduleCalendar(calendar: calendar)
    let now = try date("2026-03-10T06:00:00Z")

    #expect(clockOnly.nextRun(of: Schedule(time: .sunset(offset: .zero)), after: now) == nil)
    #expect(schedules.nextRun(of: Schedule(time: .clock(hour: 8, minute: 0), weekdays: []), after: now) == nil)

  }

  @Test func runsStrictlyAfterTheDate() throws {

    let morning = Schedule(time: .clock(hour: 8, minute: 0))
    let eightToday = try date("2026-03-10T14:00:00Z")

    #expect(schedules.nextRun(of: morning, after: eightToday) == (try date("2026-03-11T14:00:00Z")))

  }

}
