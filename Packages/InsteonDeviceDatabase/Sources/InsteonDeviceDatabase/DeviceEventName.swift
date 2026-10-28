/// The name a device profile gives to what a group command means, such as `wet` or `motion`.
///
/// Names are lower camel case, and the same name means the same thing across products, so an
/// app can act on `lowBattery` whichever sensor sends it.
///
/// ```swift
/// let event: DeviceEventName = "wet"
/// print(event == .lowBattery)   // "false"
/// ```
public struct DeviceEventName: RawRepresentable, Hashable, Sendable {

  /// The name.
  public var rawValue: String

  /// A battery-powered device's battery is low.
  public static let lowBattery = DeviceEventName(rawValue: "lowBattery")

  /// Creates an event name.
  ///
  /// - Parameter rawValue: The name.
  public init(rawValue: String) {

    self.rawValue = rawValue

  }

}

extension DeviceEventName: ExpressibleByStringLiteral {

  /// Creates an event name from a string literal, such as `"wet"`.
  ///
  /// - Parameter value: The name.
  public init(stringLiteral value: String) {

    self.init(rawValue: value)

  }

}

extension DeviceEventName: CustomStringConvertible {

  /// The name.
  public var description: String {

    rawValue

  }

}
