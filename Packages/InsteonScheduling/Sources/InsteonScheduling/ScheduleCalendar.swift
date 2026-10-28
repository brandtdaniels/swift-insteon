import Foundation

/// The times of sunrise and sunset at a place, for schedules that run relative to them.
///
/// Use ``SolarCalculator``, or supply times from a service you trust.
public protocol SunTimes: Sendable {

  /// When the sun rises on a day.
  ///
  /// - Parameters:
  ///   - day: The start of the day, in the calendar's time zone.
  ///   - calendar: The calendar whose time zone the day is in.
  /// - Returns: Sunrise, or `nil` on a day the sun doesn't rise.
  func sunrise(on day: Date, in calendar: Calendar) -> Date?

  /// When the sun sets on a day.
  ///
  /// - Parameters:
  ///   - day: The start of the day, in the calendar's time zone.
  ///   - calendar: The calendar whose time zone the day is in.
  /// - Returns: Sunset, or `nil` on a day the sun doesn't set.
  func sunset(on day: Date, in calendar: Calendar) -> Date?

}

/// Works out when schedules next run, in a home's time zone.
///
/// Times are worked out day by day in the calendar's time zone, so a schedule set for 6:30
/// p.m. runs at 6:30 p.m. local time on either side of a daylight saving change, rather than an
/// hour off. On the days the clocks change:
///
/// - A time that doesn't exist, such as 2:30 a.m. when the clocks spring forward from 2:00 to
///   3:00, runs the same amount of time after the change: at 3:30 a.m.
/// - A time that happens twice, such as 1:30 a.m. when the clocks fall back from 2:00 to 1:00,
///   runs the first time.
///
/// ```swift
/// var calendar = Calendar(identifier: .gregorian)
/// calendar.timeZone = TimeZone(identifier: "America/Denver")!
///
/// let schedules = ScheduleCalendar(calendar: calendar, sunTimes: mySunTimes)
/// let next = schedules.nextRun(of: Schedule(time: .clock(hour: 18, minute: 30)), after: .now)
/// ```
public struct ScheduleCalendar: Sendable {

  /// The calendar, with the home's time zone.
  public let calendar: Calendar

  /// Where sunrise and sunset come from, if any schedules use them.
  public let sunTimes: (any SunTimes)?

  /// Creates a schedule calendar.
  ///
  /// - Parameters:
  ///   - calendar: The calendar, with the home's time zone.
  ///   - sunTimes: Where sunrise and sunset come from. Defaults to `nil`, for schedules that
  ///     use only clock times.
  public init(calendar: Calendar, sunTimes: (any SunTimes)? = nil) {

    self.calendar = calendar
    self.sunTimes = sunTimes

  }

  /// The next time a schedule runs after a date.
  ///
  /// A schedule's weekdays are the days it runs on, so a run that an offset moves past
  /// midnight, such as six hours after sunset, counts on the day it happens.
  ///
  /// - Parameters:
  ///   - schedule: The schedule.
  ///   - date: The date to look after.
  /// - Returns: The next run, strictly after `date`, or `nil` if there's none: for a schedule
  ///   with no weekdays, a clock time outside 0:00 to 23:59, a time relative to sunrise or
  ///   sunset with no ``ScheduleCalendar/sunTimes``, or no sun event within a year.
  public func nextRun(of schedule: Schedule, after date: Date) -> Date? {

    guard !schedule.weekdays.isEmpty else {

      return nil

    }

    switch schedule.time {
    case let .clock(hour, minute):
      guard (0...23).contains(hour), (0...59).contains(minute) else {

        return nil

      }
    case .sunrise, .sunset:
      guard sunTimes != nil else {

        return nil

      }
    }

    // A run from the day before can land after midnight, so the search starts a day early.
    guard var day = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: date)) else {

      return nil

    }

    var earliest: Date?

    // A year of days covers every weekday and a polar night or day.
    for _ in 0..<368 {

      if let run = time(of: schedule.time, on: day),
         run > date,
         let weekday = Weekday(rawValue: calendar.component(.weekday, from: run)),
         schedule.weekdays.contains(weekday),
         earliest.map({ run < $0 }) ?? true {

        earliest = run

      }

      // Runs keep their order from day to day, except around a large offset; one more day
      // settles which is first.
      if let earliest, let start = calendar.date(byAdding: .day, value: -1, to: day), earliest < start {

        return earliest

      }

      guard let next = calendar.date(byAdding: .day, value: 1, to: day) else {

        return earliest

      }

      day = calendar.startOfDay(for: next)

    }

    return earliest

  }

  /// The time a schedule runs on a day.
  private func time(of time: DailyTime, on day: Date) -> Date? {

    switch time {
    case let .clock(hour, minute):
      // Starting just before the day finds the first time the day reaches the hour and minute.
      guard let run = calendar.nextDate(
        after: day.addingTimeInterval(-1),
        matching: DateComponents(hour: hour, minute: minute, second: 0),
        matchingPolicy: .nextTimePreservingSmallerComponents,
        repeatedTimePolicy: .first,
        direction: .forward
      ) else {

        return nil

      }

      if calendar.isDate(run, inSameDayAs: day) {

        return run

      }

      // A time the clocks skip late in the evening can move just past midnight; anything
      // else on another day belongs to that day.
      let shifted = calendar.component(.hour, from: run) != hour || calendar.component(.minute, from: run) != minute

      guard shifted, let nextDay = calendar.date(byAdding: .day, value: 1, to: day), calendar.isDate(run, inSameDayAs: nextDay) else {

        return nil

      }

      return run
    case let .sunrise(offset):
      return sunTimes?.sunrise(on: day, in: calendar).map { $0.addingTimeInterval(Self.seconds(offset)) }
    case let .sunset(offset):
      return sunTimes?.sunset(on: day, in: calendar).map { $0.addingTimeInterval(Self.seconds(offset)) }
    }

  }

  /// A duration in seconds, as `Date` takes it.
  private static func seconds(_ duration: Duration) -> TimeInterval {

    let (seconds, attoseconds) = duration.components

    return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18

  }

}
