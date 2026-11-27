import Foundation

/// Compares a Hub's own clock with the service's, for a health note. Nothing is ever written to the Hub.
enum HubClockDrift {
  /// How far apart the clocks may be before the service says so, in seconds.
  static let toleranceSeconds = 60

  /// The seconds the Hub's clock is ahead of the service's, or `nil` when it is within a minute or its time can't be read.
  ///
  /// - Parameters:
  ///   - reported: The Hub's local time, such as `11/20/2026 02:38:39 PM`.
  ///   - zone: The network's time zone, which the Hub's local time is in.
  ///   - date: The service's time.
  static func seconds(reported: String, in zone: TimeZone, at date: Date) -> Int? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = zone
    formatter.dateFormat = "MM/dd/yyyy hh:mm:ss a"
    guard let hub = formatter.date(from: reported) else { return nil }
    let difference = Int(hub.timeIntervalSince(date).rounded())
    return abs(difference) > toleranceSeconds ? difference : nil
  }
}
