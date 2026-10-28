/// An ALL-Link group number, which identifies one of a controller's ALL-Link groups.
///
/// An ALL-Link group ties a controller's button or event to the responders that joined it. The
/// controller sends an ALL-Link broadcast with the group number in the low byte of its To
/// address, and every responder linked to that group acts on it. Integer literals create group
/// numbers:
///
/// ```swift
/// let group: AllLinkGroupNumber = 1
/// SerialCommand.startAllLinking(mode: .controller, group: group)
/// ```
public struct AllLinkGroupNumber: RawRepresentable, Hashable, Sendable {

  /// The group number.
  public var rawValue: UInt8

  /// Every group (`0xFF`): responders treat it as matching any group they've joined.
  public static let all = AllLinkGroupNumber(rawValue: 0xFF)

  /// Creates a group number.
  ///
  /// - Parameter rawValue: The group number.
  public init(rawValue: UInt8) {

    self.rawValue = rawValue

  }

}

extension AllLinkGroupNumber: ExpressibleByIntegerLiteral {

  /// Creates a group number from an integer literal, such as `1`.
  ///
  /// - Parameter value: The group number.
  public init(integerLiteral value: UInt8) {

    self.init(rawValue: value)

  }

}

extension AllLinkGroupNumber: CustomStringConvertible {

  /// The group number in decimal, such as `"1"`.
  public var description: String {

    String(rawValue)

  }

}
