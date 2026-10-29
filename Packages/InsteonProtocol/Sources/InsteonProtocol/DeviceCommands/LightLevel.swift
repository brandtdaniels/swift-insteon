/// Converts between the percentages people give and the levels from `0x00` to `0xFF` devices
/// use.
///
/// Devices take a level in commands such as ``StandardDirectCommand/on(level:)``, and report
/// one in their answer to ``StandardDirectCommand/statusRequest(variant:)``.
///
/// ```swift
/// let half = LightLevel.level(percent: 50)       // 0x80
/// let percent = LightLevel.percent(level: half)  // 50
/// ```
public enum LightLevel {

  /// The level for a percentage, rounded to the nearest: 0 is `0x00` and 100 is `0xFF`.
  ///
  /// - Parameter percent: A percentage from 0 to 100; values outside are clamped.
  /// - Returns: The level.
  public static func level(percent: Int) -> UInt8 {

    let clamped: Int = min(max(percent, 0), 100)

    return UInt8((clamped * 255 + 50) / 100)

  }

  /// The percentage for a level, rounded to the nearest: `0x00` is 0 and `0xFF` is 100.
  ///
  /// - Parameter level: The level.
  /// - Returns: The percentage, from 0 to 100.
  public static func percent(level: UInt8) -> Int {

    (Int(level) * 100 + 127) / 255

  }

}
