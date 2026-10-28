import Testing
import InsteonProtocol

struct LightingTests {

  let keypad = InsteonAddress(0x1A, 0x2B, 0x3C)

  let modem = InsteonAddress(0x11, 0x22, 0x33)

  func button(_ number: UInt8) throws -> KeypadButton {

    try #require(KeypadButton(rawValue: number))

  }

  func buttons(_ numbers: UInt8...) throws -> KeypadButtonSet {

    try KeypadButtonSet(numbers.map(button))

  }

  @Test func refusesButtonsOutsideOneToEight() {

    #expect(KeypadButton(rawValue: 0) == nil)
    #expect(KeypadButton(rawValue: 9) == nil)
    #expect(KeypadButton.main.rawValue == 1)

  }

  @Test func masksButtonsFromBitZero() throws {

    let set = try buttons(1, 3, 8)

    #expect(set.rawValue == 0b1000_0101)
    #expect(set.buttons.map(\.rawValue) == [1, 3, 8])
    let three = try button(3)
    let two = try button(2)

    #expect(set.contains(three))
    #expect(!set.contains(two))

  }

  // The workbook's radio group for buttons 3 to 6: 2E 00 03 03 38 3C for button 3.
  @Test func writesTheWorkbooksRadioGroup() throws {

    let group = try buttons(3, 4, 5, 6)
    let third = try LightingSetting.buttonsTurnedOff(buttons(4, 5, 6), group: group).userData(for: button(3))
    let fourth = try LightingSetting.buttonsTurnedOff(buttons(3, 5, 6), group: group).userData(for: button(4))

    #expect(third.bytes.prefix(4) == [0x03, 0x03, 0x38, 0x3C])
    #expect(fourth.bytes.prefix(4) == [0x04, 0x03, 0x34, 0x3C])

  }

  @Test func writesEachSettingsSelectorAndValue() throws {

    let three = try button(3)
    let first = try buttons(1, 2)
    let second = try buttons(2)
    let eighth = try buttons(8)

    #expect(LightingSetting.onLevel(0x80).userData(for: three).bytes.prefix(3) == [0x03, 0x06, 0x80])
    #expect(LightingSetting.rampRate(.fastest).userData(for: three).bytes.prefix(3) == [0x03, 0x05, 0x1F])
    #expect(LightingSetting.ledBrightness(.brightest).userData().bytes.prefix(3) == [0x01, 0x07, 0x7F])
    #expect(LightingSetting.litLEDs(first).userData().bytes.prefix(3) == [0x01, 0x09, 0x03])
    #expect(LightingSetting.buttonsTurnedOn(second).userData(for: three).bytes.prefix(3) == [0x03, 0x02, 0x02])
    #expect(LightingSetting.nonToggleButtons(eighth).userData().bytes.prefix(3) == [0x01, 0x08, 0x80])
    #expect(LightingSetting.nonToggleButtonsSendingOn(eighth).userData().bytes.prefix(3) == [0x01, 0x0B, 0x80])

  }

  @Test func sealsASettingWithAChecksum() throws {

    let userData = try LightingSetting.onLevel(0x80).userData(for: button(3))
    let message = ExtendedMessage(to: keypad, command: ExtendedDirectCommand.getSet(), userData: userData)

    #expect(message.command == Command(command1: 0x2E, command2: 0x00))
    #expect((message.command.bytes + message.userData.bytes).reduce(UInt8(0), &+) == 0)

  }

  @Test func readsAButtonsSettings() throws {

    let userData = try UserData([0x03, 0x01, 0x04, 0x38, 0x20, 0x00, 0x1C, 0xBF, 0x40, 0x80, 0x05, 0x00, 0x80])
    let reply = ReceivedMessage(sender: keypad, destination: modem, flags: MessageFlags(messageType: .direct, isExtended: true), command: Command(command1: 0x2E), userData: userData)

    let settings = try #require(LightingSettings(reply))
    let expected = try LightingSettings(
      sender: keypad,
      button: button(3),
      buttonsTurnedOn: buttons(3),
      buttonsTurnedOff: buttons(4, 5, 6),
      rampRate: RampRate(rawValue: 0x1C),
      onLevel: 0xBF,
      ledBrightness: LEDBrightness(rawValue: 0x40),
      nonToggleButtons: buttons(8),
      litLEDs: buttons(1, 3),
      nonToggleButtonsSendingOn: buttons(8)
    )

    #expect(settings == expected)

  }

  @Test func ignoresARequestOrAnotherCommand() throws {

    let request = ReceivedMessage(
      sender: keypad, destination: modem, flags: MessageFlags(messageType: .direct, isExtended: true),
      command: Command(command1: 0x2E), userData: LightingSettings.requestUserData(for: .main)
    )
    let other = ReceivedMessage(sender: keypad, destination: modem, flags: .direct, command: Command(command1: 0x11, command2: 0xFF))

    #expect(LightingSettings(request) == nil)
    #expect(LightingSettings(other) == nil)
    let fifth = try LightingSettings.requestUserData(for: button(5))
    #expect(fifth.bytes.prefix(2) == [0x05, 0x00])

  }

  @Test func refusesOutOfRangeRampRatesAndBrightness() {

    #expect(RampRate(rawValue: 0x20) == nil)
    #expect(LEDBrightness(rawValue: 0x10) == nil)
    #expect(LEDBrightness(rawValue: 0x80) == nil)

  }

  // The later sheets: 0x06 selects 8 buttons, 0x08 turns the backlight off.
  @Test func namesTheKeypadFlagsAsTheLaterSheetsDo() {

    #expect(LightingOption.eightButtons.rawValue == 0x06)
    #expect(LightingOption.sixButtons.rawValue == 0x07)
    #expect(LightingOption.backlightOff.rawValue == 0x08)
    #expect(LightingOption.detachedLoadOn.rawValue == 0x1B)
    #expect(StandardDirectCommand.setOperatingFlags(flag: LightingOption.keyBeepOn.rawValue).command == Command(command1: 0x20, command2: 0x0A))

  }

  @Test func readsAndSetsFanSpeeds() {

    #expect(FanSpeed(level: 0x00) == .off)
    #expect(FanSpeed(level: 0x01) == .low)
    #expect(FanSpeed(level: 0x7F) == .low)
    #expect(FanSpeed(level: 0x80) == .medium)
    #expect(FanSpeed(level: 0xFE) == .medium)
    #expect(FanSpeed(level: 0xFF) == .high)

    for speed in FanSpeed.allCases {

      #expect(FanSpeed(level: speed.level) == speed)

    }

    #expect(FanSpeed.medium.command == Command(command1: 0x11, command2: 0xAA))
    #expect(FanSpeed.off.command == Command(command1: 0x13, command2: 0x00))
    #expect(FanSpeed.userData.bytes.first == 0x02)

  }

}
