import Foundation

/// A time of day a schedule runs at: a fixed time on the clock, or a time relative to sunrise
/// or sunset.
public enum DailyTime: Hashable, Sendable {

  /// A fixed time on the local clock, such as 6:30 p.m.
  ///
  /// - Parameters:
  ///   - hour: The hour, from 0 to 23.
  ///   - minute: The minute, from 0 to 59.
  case clock(hour: Int, minute: Int)

  /// A time relative to sunrise, such as 30 minutes before, as a negative offset.
  case sunrise(offset: Duration)

  /// A time relative to sunset, such as 15 minutes after.
  case sunset(offset: Duration)

}

/// A day of the week.
public enum Weekday: Int, CaseIterable, Hashable, Sendable {

  /// Sunday.
  case sunday = 1

  /// Monday.
  case monday

  /// Tuesday.
  case tuesday

  /// Wednesday.
  case wednesday

  /// Thursday.
  case thursday

  /// Friday.
  case friday

  /// Saturday.
  case saturday

}

/// When something should happen: a time of day, on some days of the week.
///
/// ```swift
/// let porchLight = Schedule(time: .sunset(offset: .seconds(15 * 60)))
/// let weekdayAlarm = Schedule(time: .clock(hour: 6, minute: 30), weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday])
/// ```
public struct Schedule: Hashable, Sendable {

  /// The time of day.
  public var time: DailyTime

  /// The days of the week it runs on.
  public var weekdays: Set<Weekday>

  /// Creates a schedule.
  ///
  /// - Parameters:
  ///   - time: The time of day.
  ///   - weekdays: The days of the week it runs on. Defaults to every day.
  public init(time: DailyTime, weekdays: Set<Weekday> = Set(Weekday.allCases)) {

    self.time = time
    self.weekdays = weekdays

  }

}
