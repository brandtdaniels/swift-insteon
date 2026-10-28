/// An option of a keypad, dimmer, switch or outlet, set with
/// ``StandardDirectCommand/setOperatingFlags(flag:)``.
///
/// Insteon's command workbook gives these flags for the KeypadLinc family, which includes
/// SwitchLinc dimmers, outlets and the FanLinc. Where an early sheet disagrees with the later
/// ones, such as on which of `0x06` and `0x07` selects 8 buttons, these follow the later
/// sheets. Devices that check integrity, which the workbook calls Yellow Filter devices, expect
/// the command in an ``ExtendedMessage`` with a checksum in D14.
///
/// ```swift
/// let eightButtons = StandardDirectCommand.setOperatingFlags(flag: LightingOption.eightButtons.rawValue)
/// ```
public enum LightingOption: UInt8, Hashable, Sendable, CaseIterable {

  /// The device can't be linked or programmed from its buttons (flag `0x00`).
  case programmingLockOn = 0x00

  /// The device can be linked and programmed from its buttons (flag `0x01`).
  case programmingLockOff = 0x01

  /// The LED blinks when the device sends a message (flag `0x02`).
  case ledOnTransmitOn = 0x02

  /// The LED doesn't blink when the device sends a message (flag `0x03`).
  case ledOnTransmitOff = 0x03

  /// The load returns to its previous level when turned on locally (flag `0x04`).
  case resumeDimOn = 0x04

  /// The load turns on to its on-level when turned on locally (flag `0x05`).
  case resumeDimOff = 0x05

  /// A keypad uses its 8-button layout (flag `0x06`).
  case eightButtons = 0x06

  /// A keypad uses its 6-button layout (flag `0x07`).
  case sixButtons = 0x07

  /// The LEDs' backlight is off (flag `0x08`).
  case backlightOff = 0x08

  /// The LEDs' backlight is on (flag `0x09`).
  case backlightOn = 0x09

  /// The buttons beep when pressed (flag `0x0A`).
  case keyBeepOn = 0x0A

  /// The buttons don't beep (flag `0x0B`).
  case keyBeepOff = 0x0B

  /// The device doesn't send or receive over RF (flag `0x0C`).
  case radioOff = 0x0C

  /// The device sends and receives over RF (flag `0x0D`).
  case radioOn = 0x0D

  /// The device doesn't send or receive over the power line (flag `0x0E`).
  case powerlineOff = 0x0E

  /// The device sends and receives over the power line (flag `0x0F`).
  case powerlineOn = 0x0F

  /// The LEDs blink when a message fails (flag `0x15`).
  case errorBlinkOn = 0x15

  /// The LEDs don't blink when a message fails (flag `0x14`).
  case errorBlinkOff = 0x14

  /// The device reports the result of its cleanups (flag `0x17`).
  case cleanupReportOn = 0x17

  /// The device doesn't report the result of its cleanups (flag `0x16`).
  case cleanupReportOff = 0x16

  /// A keypad's buttons no longer control its load, which joins group 9 instead (flag
  /// `0x1B`).
  case detachedLoadOn = 0x1B

  /// A keypad's main buttons control its load (flag `0x1A`).
  case detachedLoadOff = 0x1A

}
