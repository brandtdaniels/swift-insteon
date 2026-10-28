import Foundation

/// A place on Earth, in degrees.
public struct GeographicCoordinate: Hashable, Sendable {

  /// The latitude in degrees, positive north of the equator, from -90 to 90.
  public let latitude: Double

  /// The longitude in degrees, positive east of the prime meridian, from -180 to 180.
  public let longitude: Double

  /// Creates a coordinate.
  ///
  /// - Parameters:
  ///   - latitude: The latitude in degrees, positive north, from -90 to 90.
  ///   - longitude: The longitude in degrees, positive east, from -180 to 180.
  public init(latitude: Double, longitude: Double) {

    precondition((-90...90).contains(latitude), "A latitude is from -90 to 90 degrees: \(latitude)")
    precondition((-180...180).contains(longitude), "A longitude is from -180 to 180 degrees: \(longitude)")

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
/// let home = GeographicCoordinate(latitude: 39.74, longitude: -104.99)
/// let schedules = ScheduleCalendar(calendar: calendar, sunTimes: SolarCalculator(location: home))
/// ```
///
/// On a day the sun doesn't rise or set, such as in polar summer or winter, there's no sunrise
/// or sunset.
public struct SolarCalculator: SunTimes {

  /// The zenith of the sun at sunrise and sunset, in degrees: 90.833°.
  static let zenith = 90.833

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

  /// The sunrise or sunset that falls within a local day.
  ///
  /// The equations give the event in minutes from midnight UTC on a UTC date. The local day's
  /// event is on the UTC date of its noon, or for a time zone far from its longitude, the UTC
  /// date before or after, so each is tried in turn.
  private func event(on day: Date, in calendar: Calendar, isSunrise: Bool) -> Date? {

    let start = calendar.startOfDay(for: day)

    guard let end = calendar.date(byAdding: .day, value: 1, to: start),
          let noon = calendar.date(byAdding: .hour, value: 12, to: start) else {

      return nil

    }

    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let noonDate = utc.startOfDay(for: noon)

    for offset in [0, -1, 1] {

      guard let date = utc.date(byAdding: .day, value: offset, to: noonDate),
            let event = event(onUTCDate: date, in: utc, isSunrise: isSunrise) else {

        continue

      }

      if start <= event, event < end {

        return event

      }

    }

    return nil

  }

  /// The sunrise or sunset NOAA's equations give for a UTC date.
  ///
  /// - Parameters:
  ///   - date: Midnight UTC at the start of the date.
  ///   - utc: A Gregorian calendar in UTC.
  ///   - isSunrise: Whether to find sunrise rather than sunset.
  /// - Returns: The event, or `nil` if the sun doesn't rise or set that day.
  private func event(onUTCDate date: Date, in utc: Calendar, isSunrise: Bool) -> Date? {

    guard let dayOfYear = utc.ordinality(of: .day, in: .year, for: date),
          let daysInYear = utc.range(of: .day, in: .year, for: date)?.count else {

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

    let latitude = Self.radians(location.latitude)
    let cosine = cos(Self.radians(Self.zenith)) / (cos(latitude) * cos(declination)) - tan(latitude) * tan(declination)

    // Beyond ±1, the sun stays above or below the horizon all day.
    guard (-1...1).contains(cosine) else {

      return nil

    }

    let hourAngle = Self.degrees(acos(cosine)) * (isSunrise ? 1 : -1)
    let minutes = 720 - 4 * (location.longitude + hourAngle) - equationOfTime

    return date.addingTimeInterval(minutes * 60)

  }

  private static func radians(_ degrees: Double) -> Double {

    degrees * .pi / 180

  }

  private static func degrees(_ radians: Double) -> Double {

    radians * 180 / .pi

  }

}
