/// A keypad, dimmer, switch or outlet button's settings, as the device reports them in reply
/// to an extended get/set.
///
/// Ask for a button's settings with an extended get/set (cmd1 `0x2E`, cmd2 `0x00`) whose user
/// data is ``LightingSettings/requestUserData(for:)``. The device acknowledges, then sends its
/// settings in an extended message with the same command and `0x01` in D2.
///
/// ```swift
/// try await modem.request(ExtendedMessage(
///   to: keypad,
///   command: ExtendedDirectCommand.getSet(),
///   userData: LightingSettings.requestUserData(for: .main)
/// ))
///
/// // Then, among the messages the modem receives:
/// if let settings = LightingSettings(message) {
///   print(settings.onLevel, settings.litLEDs.buttons)
/// }
/// ```
///
/// The layout is the KeypadLinc family's in Insteon's command workbook. D14, which the
/// workbooks call the group mask in one place and the trigger mask in another, isn't read.
public struct LightingSettings: Hashable, Sendable {

  /// The device that sent the settings.
  public var sender: InsteonAddress

  /// The button the settings are for (D1).
  public var button: KeypadButton

  /// The buttons that turn on when the button does (D3).
  public var buttonsTurnedOn: KeypadButtonSet

  /// The buttons that turn off when the button turns on (D4).
  public var buttonsTurnedOff: KeypadButtonSet

  /// How quickly the button's load moves to a new level (D7), or `nil` if the device reports
  /// a value above `0x1F`.
  public var rampRate: RampRate?

  /// The level the button's load turns on to (D8).
  public var onLevel: UInt8

  /// How brightly the LEDs glow (D9), or `nil` if the device reports a value outside `0x11`
  /// to `0x7F`.
  public var ledBrightness: LEDBrightness?

  /// The buttons that send the same command on every press (D10).
  public var nonToggleButtons: KeypadButtonSet

  /// Which LEDs are lit (D11).
  public var litLEDs: KeypadButtonSet

  /// Of the non-toggle buttons, those that send on (D13).
  public var nonToggleButtonsSendingOn: KeypadButtonSet

  /// Creates settings.
  ///
  /// - Parameters:
  ///   - sender: The device that sent the settings.
  ///   - button: The button the settings are for.
  ///   - buttonsTurnedOn: The buttons that turn on with it.
  ///   - buttonsTurnedOff: The buttons that turn off when it turns on.
  ///   - rampRate: The ramp rate.
  ///   - onLevel: The on-level.
  ///   - ledBrightness: The LED brightness.
  ///   - nonToggleButtons: The non-toggle buttons.
  ///   - litLEDs: The lit LEDs.
  ///   - nonToggleButtonsSendingOn: The non-toggle buttons that send on.
  public init(
    sender: InsteonAddress,
    button: KeypadButton,
    buttonsTurnedOn: KeypadButtonSet,
    buttonsTurnedOff: KeypadButtonSet,
    rampRate: RampRate?,
    onLevel: UInt8,
    ledBrightness: LEDBrightness?,
    nonToggleButtons: KeypadButtonSet,
    litLEDs: KeypadButtonSet,
    nonToggleButtonsSendingOn: KeypadButtonSet
  ) {

    self.sender = sender
    self.button = button
    self.buttonsTurnedOn = buttonsTurnedOn
    self.buttonsTurnedOff = buttonsTurnedOff
    self.rampRate = rampRate
    self.onLevel = onLevel
    self.ledBrightness = ledBrightness
    self.nonToggleButtons = nonToggleButtons
    self.litLEDs = litLEDs
    self.nonToggleButtonsSendingOn = nonToggleButtonsSendingOn

  }

  /// Reads settings from a received message.
  ///
  /// - Parameter message: A message the modem received.
  /// - Returns: `nil` unless the message is an extended direct get/set reply (cmd1 `0x2E`,
  ///   cmd2 `0x00`, `0x01` in D2) for a button from 1 to 8. A thermostat's get/set replies,
  ///   whose cmd2 isn't `0x00`, read as `nil`.
  public init?(_ message: ReceivedMessage) {

    guard
      message.flags.messageType == .direct,
      message.command == Command(command1: 0x2E, command2: 0x00),
      let userData = message.userData,
      userData[2] == 0x01,
      let button = KeypadButton(rawValue: userData[1])
    else {

      return nil

    }

    self.init(
      sender: message.sender,
      button: button,
      buttonsTurnedOn: KeypadButtonSet(rawValue: userData[3]),
      buttonsTurnedOff: KeypadButtonSet(rawValue: userData[4]),
      rampRate: RampRate(rawValue: userData[7]),
      onLevel: userData[8],
      ledBrightness: LEDBrightness(rawValue: userData[9]),
      nonToggleButtons: KeypadButtonSet(rawValue: userData[10]),
      litLEDs: KeypadButtonSet(rawValue: userData[11]),
      nonToggleButtonsSendingOn: KeypadButtonSet(rawValue: userData[13])
    )

  }

  /// The user data that asks for a button's settings: the button in D1 and `0x00` in D2.
  ///
  /// - Parameter button: The button whose settings to read.
  /// - Returns: The user data.
  public static func requestUserData(for button: KeypadButton) -> UserData {

    var userData = UserData()
    userData[1] = button.rawValue

    return userData

  }

}
