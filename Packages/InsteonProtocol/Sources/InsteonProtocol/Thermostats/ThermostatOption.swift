/// A thermostat's display, button and lock options, set with
/// ``StandardDirectCommand/setOperatingFlags(flag:)``.
///
/// Insteon's command table gives flags `0x00` to `0x09` for thermostats, and the TempLinc
/// product requirements add `0x0A` to `0x0D`. Thermostats that check integrity, such as the
/// TempLinc, expect the command in an ``ExtendedMessage`` with a checksum in D14.
///
/// ```swift
/// let celsius = StandardDirectCommand.setOperatingFlags(flag: ThermostatOption.celsius.rawValue)
/// ```
public enum ThermostatOption: UInt8, Hashable, Sendable, CaseIterable {

  /// The thermostat can't be linked or programmed from its buttons (flag `0x00`).
  case programmingLockOn = 0x00

  /// The thermostat can be linked and programmed from its buttons (flag `0x01`).
  case programmingLockOff = 0x01

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

  /// The buttons are locked by software, on a TempLinc (flag `0x0A`).
  case softwareButtonLockOn = 0x0A

  /// The buttons are unlocked by software, on a TempLinc (flag `0x0B`).
  case softwareButtonLockOff = 0x0B

  /// The LED lights while heating or cooling, on a TempLinc (flag `0x0C`).
  case heatingCoolingLEDOn = 0x0C

  /// The LED stays off while heating or cooling, on a TempLinc (flag `0x0D`).
  case heatingCoolingLEDOff = 0x0D

}
