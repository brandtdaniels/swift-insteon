/// How quickly a dimmer moves to a new level, from `0x00`, the slowest, to `0x1F`, the
/// fastest.
///
/// Insteon's command workbook gives the keypad family's range as 9 minutes to 0.1 seconds, and
/// the SwitchLinc, LampLinc and ApplianceLinc family's as 8 minutes to 0.1 seconds, with
/// `0x00` there meaning 2 seconds. The values in between aren't given, so this type keeps the
/// device's number rather than a duration.
public struct RampRate: RawRepresentable, Hashable, Sendable, Comparable {

  /// The fastest rate (`0x1F`), about 0.1 seconds.
  public static let fastest = RampRate(rawValue: 0x1F)!

  /// The rate's number, from `0x00` to `0x1F`.
  public let rawValue: UInt8

  /// Creates a rate from its number.
  ///
  /// - Parameter rawValue: The rate's number, from `0x00` to `0x1F`.
  /// - Returns: `nil` if the number is above `0x1F`.
  public init?(rawValue: UInt8) {

    guard rawValue <= 0x1F else {

      return nil

    }

    self.rawValue = rawValue

  }

  /// Whether one rate is slower than another.
  ///
  /// - Parameters:
  ///   - lhs: A rate.
  ///   - rhs: Another rate.
  /// - Returns: `true` if `lhs` is slower.
  public static func < (lhs: RampRate, rhs: RampRate) -> Bool {

    lhs.rawValue < rhs.rawValue

  }

}

/// How brightly a device's LEDs glow, from `0x11`, the dimmest, to `0x7F`, the brightest.
public struct LEDBrightness: RawRepresentable, Hashable, Sendable, Comparable {

  /// The dimmest setting (`0x11`).
  public static let dimmest = LEDBrightness(rawValue: 0x11)!

  /// The brightest setting (`0x7F`).
  public static let brightest = LEDBrightness(rawValue: 0x7F)!

  /// The brightness, from `0x11` to `0x7F`.
  public let rawValue: UInt8

  /// Creates a brightness.
  ///
  /// - Parameter rawValue: The brightness, from `0x11` to `0x7F`.
  /// - Returns: `nil` if the value is outside `0x11` to `0x7F`.
  public init?(rawValue: UInt8) {

    guard (0x11...0x7F).contains(rawValue) else {

      return nil

    }

    self.rawValue = rawValue

  }

  /// Whether one brightness is dimmer than another.
  ///
  /// - Parameters:
  ///   - lhs: A brightness.
  ///   - rhs: Another brightness.
  /// - Returns: `true` if `lhs` is dimmer.
  public static func < (lhs: LEDBrightness, rhs: LEDBrightness) -> Bool {

    lhs.rawValue < rhs.rawValue

  }

}
