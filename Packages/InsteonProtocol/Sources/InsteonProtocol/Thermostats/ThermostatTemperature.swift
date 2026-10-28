/// A temperature or setpoint as a thermostat sends it: a count of half degrees.
///
/// Thermostats send temperatures and setpoints doubled, in one byte, so `0xA0` is 80 degrees.
/// The degrees are in whichever scale the thermostat displays, Fahrenheit or Celsius, which
/// ``ThermostatOption`` sets.
public struct ThermostatTemperature: Hashable, Sendable, RawRepresentable {

  /// The temperature in half degrees.
  public let rawValue: UInt8

  /// Creates a temperature from its count of half degrees.
  ///
  /// - Parameter rawValue: The temperature in half degrees, such as `0xA0` for 80 degrees.
  public init(rawValue: UInt8) {

    self.rawValue = rawValue

  }

  /// Creates a temperature from degrees, or `nil` unless they're a whole or half degree from
  /// 0 to 127.5.
  ///
  /// - Parameter degrees: The temperature in degrees.
  public init?(degrees: Double) {

    let halves = degrees * 2

    guard halves.rounded() == halves, (0...255).contains(halves) else {

      return nil

    }

    self.init(rawValue: UInt8(halves))

  }

  /// The temperature in degrees, in the thermostat's scale.
  public var degrees: Double {

    Double(rawValue) / 2

  }

}
