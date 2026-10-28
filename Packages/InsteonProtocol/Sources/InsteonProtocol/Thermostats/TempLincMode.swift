/// The mode a TempLinc Thermostat (2441TH) or TempLinc Wireless Zone Thermostat (2441ZTH)
/// reports in a mode ``ThermostatStatusReport``, as the final revisions of Insteon's TempLinc
/// product requirements give it.
///
/// Earlier revisions and the TempLinc engineering specification give only off, auto (`0x01`),
/// heat and cool; the final revisions call `0x01` manual auto and add the programmed auto mode
/// as `0x04`.
///
/// ```swift
/// if case let .mode(code) = report, let mode = TempLincMode(rawValue: code.rawValue) {
///   print(mode)
/// }
/// ```
public enum TempLincMode: UInt8, Hashable, Sendable, CaseIterable {

  /// Heating and cooling are off.
  case off = 0x00

  /// Heating or cooling, whichever the temperature needs, at the setpoints set by hand.
  case manualAuto = 0x01

  /// Heating to the heat setpoint.
  case heat = 0x02

  /// Cooling to the cool setpoint.
  case cool = 0x03

  /// Heating or cooling, following the thermostat's program.
  case auto = 0x04

}
