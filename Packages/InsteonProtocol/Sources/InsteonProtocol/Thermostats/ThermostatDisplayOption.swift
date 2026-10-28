/// A thermostat's display and button options, set with
/// ``StandardDirectCommand/setOperatingFlags(flag:)``.
///
/// Insteon's command table gives these flags for thermostats. Thermostats that check
/// integrity expect the command in an ``ExtendedMessage`` with a checksum.
///
/// ```swift
/// let celsius = StandardDirectCommand.setOperatingFlags(flag: ThermostatDisplayOption.celsius.rawValue)
/// ```
public enum ThermostatDisplayOption: UInt8, Hashable, Sendable, CaseIterable {

  /// The buttons beep when pressed (flag `0x02`).
  case buttonBeepOn = 0x02

  /// The buttons don't beep (flag `0x03`).
  case buttonBeepOff = 0x03

  /// The buttons are locked (flag `0x04`).
  case buttonLockOn = 0x04

  /// The buttons are unlocked (flag `0x05`).
  case buttonLockOff = 0x05

  /// Temperatures are shown and sent in Celsius (flag `0x06`).
  case celsius = 0x06

  /// Temperatures are shown and sent in Fahrenheit (flag `0x07`).
  case fahrenheit = 0x07

  /// Times are shown in 24-hour format (flag `0x08`).
  case twentyFourHour = 0x08

  /// Times are shown with a.m. and p.m. (flag `0x09`).
  case twelveHour = 0x09

}
