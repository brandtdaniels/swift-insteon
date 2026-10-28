import Foundation
import Testing
import InsteonScheduling

/// Checks sunrise and sunset against published times, to within two minutes.
struct SolarCalculatorTests {

  func calendar(_ identifier: String) throws -> Calendar {

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: identifier))

    return calendar

  }

  func day(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar) throws -> Date {

    try #require(calendar.date(from: DateComponents(year: year, month: month, day: day)))

  }

  func time(_ hour: Int, _ minute: Int, on day: Date, in calendar: Calendar) throws -> Date {

    try #require(calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day))

  }

  func expectTime(_ date: Date?, near expected: Date, sourceLocation: SourceLocation = #_sourceLocation) throws {

    let date = try #require(date, sourceLocation: sourceLocation)
    #expect(abs(date.timeIntervalSince(expected)) <= 120, "\(date) isn't near \(expected)", sourceLocation: sourceLocation)

  }

  @Test func worksOutDenversLongestAndShortestDays() throws {

    let denver = try calendar("America/Denver")
    let sun = SolarCalculator(location: try #require(GeographicCoordinate(latitude: 39.7392, longitude: -104.9903)))
    let summer = try day(2026, 6, 21, in: denver)
    let winter = try day(2026, 12, 21, in: denver)

    try expectTime(sun.sunrise(on: summer, in: denver), near: try time(5, 32, on: summer, in: denver))
    try expectTime(sun.sunset(on: summer, in: denver), near: try time(20, 31, on: summer, in: denver))
    try expectTime(sun.sunrise(on: winter, in: denver), near: try time(7, 17, on: winter, in: denver))
    try expectTime(sun.sunset(on: winter, in: denver), near: try time(16, 39, on: winter, in: denver))

  }

  // Sydney's sunrise is the evening before in UTC.
  @Test func findsTheLocalDaysSunriseFarFromUTC() throws {

    let sydney = try calendar("Australia/Sydney")
    let sun = SolarCalculator(location: try #require(GeographicCoordinate(latitude: -33.8688, longitude: 151.2093)))
    let newYear = try day(2026, 1, 1, in: sydney)

    try expectTime(sun.sunrise(on: newYear, in: sydney), near: try time(5, 47, on: newYear, in: sydney))
    try expectTime(sun.sunset(on: newYear, in: sydney), near: try time(20, 9, on: newYear, in: sydney))

  }

  @Test func hasNoSunriseOrSunsetInPolarSummerOrWinter() throws {

    let oslo = try calendar("Europe/Oslo")
    let tromso = SolarCalculator(location: try #require(GeographicCoordinate(latitude: 69.6492, longitude: 18.9553)))

    for date in [try day(2026, 6, 21, in: oslo), try day(2026, 12, 21, in: oslo)] {
      #expect(tromso.sunrise(on: date, in: oslo) == nil)
      #expect(tromso.sunset(on: date, in: oslo) == nil)
    }

  }

  @Test func drivesASunsetSchedule() throws {

    let denver = try calendar("America/Denver")
    let sun = SolarCalculator(location: try #require(GeographicCoordinate(latitude: 39.7392, longitude: -104.9903)))
    let schedules = ScheduleCalendar(calendar: denver, sunTimes: sun)
    let summer = try day(2026, 6, 21, in: denver)

    let run = schedules.nextRun(of: Schedule(time: .sunset(offset: .zero)), after: summer)

    try expectTime(run, near: try time(20, 31, on: summer, in: denver))

  }

  // Reykjavik's sunset on June 17 comes just after midnight, on June 18.
  @Test func keepsASunsetThatComesAfterMidnight() throws {

    let iceland = try calendar("Atlantic/Reykjavik")
    let reykjavik = SolarCalculator(location: try #require(GeographicCoordinate(latitude: 64.1466, longitude: -21.9426)))
    let june17 = try day(2026, 6, 17, in: iceland)
    let june18 = try day(2026, 6, 18, in: iceland)

    try expectTime(reykjavik.sunset(on: june17, in: iceland), near: try time(0, 1, on: june18, in: iceland))

  }

  @Test func refusesCoordinatesOutOfRange() {

    #expect(GeographicCoordinate(latitude: 90.5, longitude: 0) == nil)
    #expect(GeographicCoordinate(latitude: 0, longitude: 180.0001) == nil)
    #expect(GeographicCoordinate(latitude: .nan, longitude: 0) == nil)

  }

}
