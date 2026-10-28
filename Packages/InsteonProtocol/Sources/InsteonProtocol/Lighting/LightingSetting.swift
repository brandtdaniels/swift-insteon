/// A setting of a keypad, dimmer, switch or outlet that's written with an extended get/set
/// (cmd1 `0x2E`, cmd2 `0x00`).
///
/// Insteon's command workbook gives these for the KeypadLinc family, which includes SwitchLinc
/// dimmers, outlets and the FanLinc. D1 is the button the setting applies to and D2 selects
/// the setting. Settings that apply to the whole device, such as LED brightness, go to
/// button 1. Devices that check integrity expect a checksum in D14, which ``ExtendedMessage``
/// adds by default.
///
/// ```swift
/// let message = ExtendedMessage(
///   to: keypad,
///   command: ExtendedDirectCommand.getSet(),
///   userData: LightingSetting.onLevel(0x80).userData(for: KeypadButton(rawValue: 3)!)
/// )
/// ```
///
/// Read the settings back with ``LightingSettings``.
public enum LightingSetting: Hashable, Sendable {

  /// The buttons that turn on when the button does (D2 `0x02`).
  case buttonsTurnedOn(KeypadButtonSet)

  /// The buttons that turn off when the button turns on, and the buttons grouped with it
  /// (D2 `0x03`, with the turned-off buttons in D3 and the group in D4).
  ///
  /// Giving each button in a group the others as its turned-off buttons makes them a radio
  /// group, where turning one on turns the rest off. The workbook's example for buttons 3
  /// to 6 sets button 3's turned-off buttons to 4, 5 and 6, and the group to 3 to 6.
  case buttonsTurnedOff(KeypadButtonSet, group: KeypadButtonSet)

  /// How quickly the button's load moves to a new level (D2 `0x05`).
  case rampRate(RampRate)

  /// The level the button's load turns on to (D2 `0x06`).
  case onLevel(UInt8)

  /// How brightly the LEDs glow (D2 `0x07`).
  case ledBrightness(LEDBrightness)

  /// The buttons that send the same command on every press rather than toggling (D2 `0x08`).
  case nonToggleButtons(KeypadButtonSet)

  /// Which LEDs are lit (D2 `0x09`).
  case litLEDs(KeypadButtonSet)

  /// Of the non-toggle buttons, those that send on; the rest send off (D2 `0x0B`).
  case nonToggleButtonsSendingOn(KeypadButtonSet)

  /// The setting's selector, which goes in D2.
  public var selector: UInt8 {

    switch self {
    case .buttonsTurnedOn: 0x02
    case .buttonsTurnedOff: 0x03
    case .rampRate: 0x05
    case .onLevel: 0x06
    case .ledBrightness: 0x07
    case .nonToggleButtons: 0x08
    case .litLEDs: 0x09
    case .nonToggleButtonsSendingOn: 0x0B
    }

  }

  /// The user data that writes the setting for a button.
  ///
  /// - Parameter button: The button the setting applies to. Defaults to button 1, which
  ///   settings that apply to the whole device use.
  /// - Returns: The button in D1, the selector in D2 and the value from D3.
  public func userData(for button: KeypadButton = .main) -> UserData {

    var userData = UserData()
    userData[1] = button.rawValue
    userData[2] = selector

    switch self {
    case let .buttonsTurnedOn(buttons), let .nonToggleButtons(buttons), let .litLEDs(buttons), let .nonToggleButtonsSendingOn(buttons):
      userData[3] = buttons.rawValue
    case let .buttonsTurnedOff(buttons, group):
      userData[3] = buttons.rawValue
      userData[4] = group.rawValue
    case let .rampRate(rate):
      userData[3] = rate.rawValue
    case let .onLevel(level):
      userData[3] = level
    case let .ledBrightness(brightness):
      userData[3] = brightness.rawValue
    }

    return userData

  }

}
