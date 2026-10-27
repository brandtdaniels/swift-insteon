/// The firmware version a device or modem reports.
///
/// What a device can do may depend on its firmware, so a ``ProductDatabase`` looks devices up
/// by firmware version as well as by category and subcategory. Versions compare by number, so
/// a database can find the closest earlier version it has a record for.
///
/// ```swift
/// let version: FirmwareVersion = 0x41
/// print(version >= 0x40)   // "true"
/// print(version)           // "0x41"
/// ```
public struct FirmwareVersion: RawRepresentable, Hashable, Sendable {

  /// The version number.
  public var rawValue: UInt8

  /// Creates a firmware version from its number.
  ///
  /// - Parameter rawValue: The version number.
  public init(rawValue: UInt8) {

    self.rawValue = rawValue

  }

}

extension FirmwareVersion: ExpressibleByIntegerLiteral {

  /// Creates a firmware version from an integer literal, such as `0x41`.
  ///
  /// - Parameter value: The version number.
  public init(integerLiteral value: UInt8) {

    self.init(rawValue: value)

  }

}

extension FirmwareVersion: Comparable {

  /// Whether one version is earlier than another.
  ///
  /// - Parameters:
  ///   - lhs: A version.
  ///   - rhs: Another version.
  /// - Returns: `true` if `lhs` is the earlier version.
  public static func < (lhs: FirmwareVersion, rhs: FirmwareVersion) -> Bool {

    lhs.rawValue < rhs.rawValue

  }

}

extension FirmwareVersion: CustomStringConvertible {

  /// The version number in hexadecimal, such as `"0x41"`.
  public var description: String {

    "0x" + rawValue.hexDigits

  }

}
