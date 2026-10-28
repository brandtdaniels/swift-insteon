/// A thermostat zone, from 0 to 31, for ``ThermostatCommand/readZone(_:zone:)``.
///
/// A thermostat that controls one zone reports it as zone 0, ``ThermostatZone/main``.
public struct ThermostatZone: Hashable, Sendable, RawRepresentable {

  /// The main zone, zone 0.
  public static let main = ThermostatZone(uncheckedRawValue: 0)

  /// The zone number.
  public let rawValue: UInt8

  /// Creates a zone, or `nil` unless the number is from 0 to 31.
  ///
  /// - Parameter rawValue: The zone number.
  public init?(rawValue: UInt8) {

    guard rawValue < 32 else {

      return nil

    }

    self.rawValue = rawValue

  }

  private init(uncheckedRawValue: UInt8) {

    rawValue = uncheckedRawValue

  }

}

/// A value to read from a thermostat zone with ``ThermostatCommand/readZone(_:zone:)``.
public enum ThermostatReading: UInt8, Hashable, Sendable, CaseIterable {

  /// The current temperature, as a ``ThermostatTemperature``.
  case temperature = 0b00

  /// The setpoint, as a ``ThermostatTemperature``.
  ///
  /// With two setpoints, as in auto mode, the acknowledgement carries the heat setpoint, and
  /// the thermostat sends the cool setpoint in a second message with cmd1 `0x6A`.
  case setpoint = 0b01

  /// The deadband between the heat and cool setpoints. Insteon's Venstar/Totaline adapter
  /// doesn't support it.
  case deadband = 0b10

  /// The relative humidity, in percent, on thermostats that measure it.
  case humidity = 0b11

}
