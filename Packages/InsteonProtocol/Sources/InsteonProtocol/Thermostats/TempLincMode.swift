/// The mode a TempLinc Thermostat (2441TH) or TempLinc Wireless Zone Thermostat (2441ZTH)
/// reports in a mode ``ThermostatStatusReport``, as Insteon's command workbook gives them for
/// the status report.
///
/// The thermostat keeps its mode internally as different values, 0 to 4 for off, manual auto,
/// heat, cool and auto, which its product requirements give; the status report uses these
/// instead, which agree with ``ThermostatMode`` from off through fan and differ after it.
///
/// ```swift
/// if case let .mode(code) = report, let mode = TempLincMode(rawValue: code.rawValue) {
///   print(mode)
/// }
/// ```
public enum TempLincMode: UInt8, Hashable, Sendable, CaseIterable {

  /// Heating and cooling are off.
  case off = 0x00

  /// Heating to the heat setpoint.
  case heat = 0x01

  /// Cooling to the cool setpoint.
  case cool = 0x02

  /// Heating or cooling, following the thermostat's program.
  case auto = 0x03

  /// The fan runs all the time.
  case fanOn = 0x04

  /// Heating or cooling, whichever the temperature needs, at the setpoints set by hand.
  case manualAuto = 0x05

  /// The fan runs only while heating or cooling.
  case fanAuto = 0x08

}
