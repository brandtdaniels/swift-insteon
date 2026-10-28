import Foundation

/// A place on Earth, in degrees.
public struct GeographicCoordinate: Hashable, Sendable {

  /// The latitude in degrees, positive north of the equator, from -90 to 90.
  public let latitude: Double

  /// The longitude in degrees, positive east of the prime meridian, from -180 to 180.
  public let longitude: Double

  /// Creates a coordinate, or `nil` if either value is out of range or not a number.
  ///
  /// - Parameters:
  ///   - latitude: The latitude in degrees, positive north, from -90 to 90.
  ///   - longitude: The longitude in degrees, positive east, from -180 to 180.
  public init?(latitude: Double, longitude: Double) {

    guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {

      return nil

    }

    self.latitude = latitude
    self.longitude = longitude

  }

}

/// Works out sunrise and sunset at a place with the equations of NOAA's Global Monitoring
/// Division.
///
/// NOAA's "General Solar Position Calculations" estimate the equation of time and the sun's
/// declination from the fractional year, then find the hour angle at which the sun's center
/// is 90.833° from overhead, which allows for refraction and the size of the sun's disk.
/// The results are within a minute or two of published times at most latitudes, close enough
/// for lights, and drift further near the poles.
///
/// ```swift
/// var calendar = Calendar(identifier: .gregorian)
/// calendar.timeZone = TimeZone(identifier: "America/Denver")!
///
/// if let home = GeographicCoordinate(latitude: 39.74, longitude: -104.99) {
///   let schedules = ScheduleCalendar(calendar: calendar, sunTimes: SolarCalculator(location: home))
/// }
/// ```
///
/// A day's sunrise and sunset are the ones around its solar noon, so far north in summer, a
/// day's sunset can come just after midnight. On a day the sun doesn't rise or set, such as in
/// polar summer or winter, there's no sunrise or sunset.
public struct SolarCalculator: SunTimes {

  /// The zenith of the sun at sunrise and sunset, in degrees: 90.833°.
  static let zenith = 90.833

  /// The Gregorian calendar in UTC, which the equations count days in.
  private static let utc: Calendar = {

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!

    return calendar

  }()

  /// A UTC date's solar noon, sunrise and sunset.
  private struct SolarDay {

    let noon: Date

    let sunrise: Date?

    let sunset: Date?

  }

  /// The place to work out sunrise and sunset for.
  public let location: GeographicCoordinate

  /// Creates a calculator for a place.
  ///
  /// - Parameter location: The place, such as the home.
  public init(location: GeographicCoordinate) {

    self.location = location

  }

  /// When the sun rises on a day.
  ///
  /// - Parameters:
  ///   - day: The start of the day, in the calendar's time zone.
  ///   - calendar: The calendar whose time zone the day is in.
  /// - Returns: Sunrise, or `nil` on a day the sun doesn't rise.
  public func sunrise(on day: Date, in calendar: Calendar) -> Date? {

    event(on: day, in: calendar, isSunrise: true)

  }

  /// When the sun sets on a day.
  ///
  /// - Parameters:
  ///   - day: The start of the day, in the calendar's time zone.
  ///   - calendar: The calendar whose time zone the day is in.
  /// - Returns: Sunset, or `nil` on a day the sun doesn't set.
  public func sunset(on day: Date, in calendar: Calendar) -> Date? {

    event(on: day, in: calendar, isSunrise: false)

  }

  /// The sunrise or sunset around a local day's solar noon.
  ///
  /// The equations work in minutes from midnight UTC on a UTC date. The local day's solar noon
  /// is on the UTC date of its noon, or for a time zone far from its longitude, the UTC date
  /// before or after, so each is tried in turn.
  private func event(on day: Date, in calendar: Calendar, isSunrise: Bool) -> Date? {

    let start = calendar.startOfDay(for: day)

    guard let end = calendar.date(byAdding: .day, value: 1, to: start),
          let noon = calendar.date(byAdding: .hour, value: 12, to: start) else {

      return nil

    }

    let noonDate = Self.utc.startOfDay(for: noon)

    for offset in [0, -1, 1] {

      guard let date = Self.utc.date(byAdding: .day, value: offset, to: noonDate),
            let solarDay = solarDay(onUTCDate: date) else {

        continue

      }

      if start <= solarDay.noon, solarDay.noon < end {

        return isSunrise ? solarDay.sunrise : solarDay.sunset

      }

    }

    return nil

  }

  /// The solar noon, sunrise and sunset NOAA's equations give for a UTC date.
  ///
  /// - Parameter date: Midnight UTC at the start of the date.
  /// - Returns: The day, or `nil` if the calendar can't place the date in its year.
  private func solarDay(onUTCDate date: Date) -> SolarDay? {

    guard let dayOfYear = Self.utc.ordinality(of: .day, in: .year, for: date),
          let daysInYear = Self.utc.range(of: .day, in: .year, for: date)?.count else {

      return nil

    }

    // The fractional year, in radians, at the place's solar noon.
    let hour = 12 - location.longitude / 15
    let year = 2 * Double.pi / Double(daysInYear) * (Double(dayOfYear) - 1 + (hour - 12) / 24)

    // The equation of time, in minutes, and the sun's declination, in radians.
    let equationOfTime = 229.18 * (
      0.000075 + 0.001868 * cos(year) - 0.032077 * sin(year)
        - 0.014615 * cos(2 * year) - 0.040849 * sin(2 * year)
    )
    let declination = 0.006918 - 0.399912 * cos(year) + 0.070257 * sin(year)
      - 0.006758 * cos(2 * year) + 0.000907 * sin(2 * year)
      - 0.002697 * cos(3 * year) + 0.00148 * sin(3 * year)

    let noon = date.addingTimeInterval((720 - 4 * location.longitude - equationOfTime) * 60)

    let latitude = Self.radians(location.latitude)
    let cosine = cos(Self.radians(Self.zenith)) / (cos(latitude) * cos(declination)) - tan(latitude) * tan(declination)

    // Beyond ±1, the sun stays above or below the horizon all day.
    guard (-1...1).contains(cosine) else {

      return SolarDay(noon: noon, sunrise: nil, sunset: nil)

    }

    let hourAngle = Self.degrees(acos(cosine))

    return SolarDay(
      noon: noon,
      sunrise: date.addingTimeInterval((720 - 4 * (location.longitude + hourAngle) - equationOfTime) * 60),
      sunset: date.addingTimeInterval((720 - 4 * (location.longitude - hourAngle) - equationOfTime) * 60)
    )

  }

  private static func radians(_ degrees: Double) -> Double {

    degrees * .pi / 180

  }

  private static func degrees(_ radians: Double) -> Double {

    radians * 180 / .pi

  }

}
