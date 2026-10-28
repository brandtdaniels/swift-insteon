import Foundation

/// The times of sunrise and sunset at a place, for schedules that run relative to them.
///
/// Supply one from a solar calculator or a service you trust; the package doesn't include one.
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
  /// - Parameters:
  ///   - schedule: The schedule.
  ///   - date: The date to look after.
  /// - Returns: The next run, strictly after `date`, or `nil` if there's none within a year,
  ///   as for a schedule with no weekdays, or one relative to sunrise or sunset with no
  ///   ``ScheduleCalendar/sunTimes`` or none of the sun events it needs.
  public func nextRun(of schedule: Schedule, after date: Date) -> Date? {

    var day = calendar.startOfDay(for: date)

    // A year of days covers every weekday and a polar night or day.
    for _ in 0..<367 {

      if let weekday = Weekday(rawValue: calendar.component(.weekday, from: day)),
         schedule.weekdays.contains(weekday),
         let run = time(of: schedule.time, on: day),
         run > date {

        return run

      }

      guard let next = calendar.date(byAdding: .day, value: 1, to: day) else {

        return nil

      }

      day = calendar.startOfDay(for: next)

    }

    return nil

  }

  /// The time a schedule runs on a day.
  private func time(of time: DailyTime, on day: Date) -> Date? {

    switch time {
    case let .clock(hour, minute):
      // Starting just before the day finds the first time the day reaches the hour and minute.
      return calendar.nextDate(
        after: day.addingTimeInterval(-1),
        matching: DateComponents(hour: hour, minute: minute, second: 0),
        matchingPolicy: .nextTimePreservingSmallerComponents,
        repeatedTimePolicy: .first,
        direction: .forward
      ).flatMap { calendar.isDate($0, inSameDayAs: day) ? $0 : nil }
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
