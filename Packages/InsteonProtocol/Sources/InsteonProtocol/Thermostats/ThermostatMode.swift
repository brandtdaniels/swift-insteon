/// The mode a thermostat reports, in the acknowledgement to
/// ``ThermostatCommand/readMode`` or in a ``ThermostatStatusReport``.
public enum ThermostatMode: UInt8, Hashable, Sendable, CaseIterable {

  /// Heating and cooling are off.
  case off = 0x00

  /// Heating to the heat setpoint.
  case heat = 0x01

  /// Cooling to the cool setpoint.
  case cool = 0x02

  /// Heating or cooling, whichever the temperature needs.
  case auto = 0x03

  /// The fan runs all the time.
  case fan = 0x04

  /// Following the thermostat's program.
  case program = 0x05

  /// Heating, following the thermostat's program.
  case programHeat = 0x06

  /// Cooling, following the thermostat's program.
  case programCool = 0x07

}
