/// Whether a modem's radio is on, and whether the setting outlasts a power cycle, for
/// ``SerialCommand/setRadio(_:)``.
public enum RadioSetting: UInt8, CaseIterable, Hashable, Sendable {

  /// Turns the radio on and saves the setting (`0x80`).
  case enabled = 0x80

  /// Turns the radio off and saves the setting (`0x81`).
  case disabled = 0x81

  /// Turns the radio on until the modem is power cycled (`0x00`).
  case enabledUntilPowerCycle = 0x00

  /// Turns the radio off until the modem is power cycled (`0x01`).
  case disabledUntilPowerCycle = 0x01

}
