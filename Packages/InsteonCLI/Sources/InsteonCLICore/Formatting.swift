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

  private static func digits(_ value: UInt64, count: Int) -> String {

    let digits = String(value, radix: 16, uppercase: true)

    return String(repeating: "0", count: max(0, count - digits.count)) + digits

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
