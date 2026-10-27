/// An ALL-Link group: the number that ties a controller's button or event to the devices that
/// respond to it.
///
/// A controller sends an ALL-Link broadcast to a group, and every device linked to it as a
/// responder in that group acts on it. Integer literals create groups:
///
/// ```swift
/// let group: AllLinkGroup = 1
/// SerialCommand.startAllLinking(mode: .controller, group: group)
/// ```
public struct AllLinkGroup: RawRepresentable, Hashable, Sendable {

  /// The group number.
  public var rawValue: UInt8

  /// Creates a group from its number.
  ///
  /// - Parameter rawValue: The group number.
  public init(rawValue: UInt8) {

    self.rawValue = rawValue

  }

}

extension AllLinkGroup: ExpressibleByIntegerLiteral {

  /// Creates a group from an integer literal, such as `1`.
  ///
  /// - Parameter value: The group number.
  public init(integerLiteral value: UInt8) {

    self.init(rawValue: value)

  }

}

extension AllLinkGroup: CustomStringConvertible {

  /// The group number in decimal, such as `"1"`.
  public var description: String {

    String(rawValue)

  }

}
