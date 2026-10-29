/// Writes bytes and addresses as the docs do: `0x` and uppercase hexadecimal digits.
public enum Hex {

  /// A byte as `0x` and two digits, such as `"0x0F"`.
  ///
  /// - Parameter value: The byte.
  /// - Returns: The byte in hexadecimal.
  public static func byte(_ value: UInt8) -> String {

    "0x" + digits(UInt64(value), count: 2)

  }

  /// A two-byte address in an ALL-Link database as `0x` and four digits, such as `"0x0FFF"`.
  ///
  /// - Parameter value: The address.
  /// - Returns: The address in hexadecimal.
  public static func address(_ value: UInt16) -> String {

    "0x" + digits(UInt64(value), count: 4)

  }

  /// Bytes as space-separated pairs of digits, such as `"02 77 06"`.
  ///
  /// - Parameter values: The bytes.
  /// - Returns: The bytes in hexadecimal.
  public static func pairs(_ values: [UInt8]) -> String {

    values.map { digits(UInt64($0), count: 2) }.joined(separator: " ")

  }

  private static func digits(_ value: UInt64, count: Int) -> String {

    let digits = String(value, radix: 16, uppercase: true)

    return String(repeating: "0", count: max(0, count - digits.count)) + digits

  }

}

/// Converts between the percentages people give and the levels from `0x00` to `0xFF` devices
/// use.
public enum LightLevel {

  /// The level for a percentage, rounded to the nearest: 0 is `0x00` and 100 is `0xFF`.
  ///
  /// - Parameter percent: A percentage from 0 to 100; values outside are clamped.
  /// - Returns: The level.
  public static func level(percent: Int) -> UInt8 {

    let clamped = min(max(percent, 0), 100)

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

/// The exit statuses of the `insteon` command.
public enum ExitStatus {

  /// The command did what was asked: `0`.
  public static let success: Int32 = 0

  /// The command failed, such as when a device didn't answer: `1`.
  public static let failure: Int32 = 1

  /// The command line or configuration can't be used: `64`, as in BSD's `sysexits.h`.
  public static let usage: Int32 = 64

  /// The person interrupted the command with Control-C: `130`.
  public static let interrupted: Int32 = 130

}
