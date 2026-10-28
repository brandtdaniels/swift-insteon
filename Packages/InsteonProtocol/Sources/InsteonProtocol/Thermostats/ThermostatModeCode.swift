/// A mode as a thermostat reports it in a ``ThermostatStatusReport``, in the thermostat's own
/// values.
///
/// Thermostats don't agree on the values: read the code with ``ThermostatMode`` for a
/// thermostat that uses Insteon's command table values, such as the Venstar adapter, or with
/// ``TempLincMode`` for a TempLinc.
public struct ThermostatModeCode: Hashable, Sendable, RawRepresentable {

  /// The value the thermostat sent.
  public let rawValue: UInt8

  /// Creates a mode code.
  ///
  /// - Parameter rawValue: The value the thermostat sent.
  public init(rawValue: UInt8) {

    self.rawValue = rawValue

  }

}
