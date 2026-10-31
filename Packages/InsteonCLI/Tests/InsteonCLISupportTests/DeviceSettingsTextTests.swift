import Testing
import InsteonCLISupport
import InsteonCore
import InsteonDeviceCatalog
import InsteonProtocol

/// A made-up dimmer's settings, whose names and values no real product's are.
enum ExampleSettings {

  static let keyBeep = OperatingFlag(
    name: "keyBeep",
    summary: "Buttons beep.",
    query: 0x00,
    bit: 0x20,
    on: 0x0A,
    off: 0x0B,
    label: "Beep on button press",
    section: .buttons,
    defaultValue: false
  )

  static let loadSense = OperatingFlag(name: "loadSense", summary: "Load sense.", query: 0x00, bit: 0x01, label: "Load sense", section: .load)

  static let radioOff = OperatingFlag(
    name: "radioOff",
    summary: "Radio off.",
    query: 0x05,
    bit: 0x40,
    on: 0x0C,
    off: 0x0D,
    label: "Turn off radio",
    section: .communication,
    isAdvanced: true
  )

  static let delta = OperatingReading(name: "databaseDelta", summary: "Delta.", query: 0x01, label: "ALL-Link database changes", section: .diagnostics)

  static let rampRate = SettingValue(
    name: "rampRate",
    summary: "Ramp rate.",
    position: 7,
    range: 0x00...0x1F,
    label: "Ramp rate",
    section: .load,
    defaultValue: 0x1C,
    table: "rampRate"
  )

  static let onLevel = SettingValue(name: "onLevel", summary: "On-level.", position: 8, label: "On-level", section: .load, unit: .percent, scale: 100.0 / 255.0)

  static let commands = CommandSet(
    id: "exampleDimmer",
    name: "Example Dimmer",
    summary: "A made-up dimmer.",
    operatingFlags: [keyBeep, loadSense, radioOff],
    readings: [delta],
    extendedSettings: ExtendedSettings(
      isPerButton: true,
      values: [rampRate, onLevel],
      writes: [
        SettingWrite(name: "rampRate", summary: "Ramp rate.", selector: 0x05, isPerButton: true, bytes: [.init(position: 3, value: "rampRate")]),
        SettingWrite(name: "onLevel", summary: "On-level.", selector: 0x06, isPerButton: false, bytes: [.init(position: 3, value: "onLevel")])
      ]
    ),
    valueTables: [ValueTable(name: "rampRate", entries: [.init(value: 0x1C, label: "0.5 s", duration: .milliseconds(500)), .init(value: 0x1F, label: "0.1 s", duration: .milliseconds(100))])]
  )

  /// A reading of the dimmer's settings, as `Device.readSettings(includingAdvanced:beforeReading:)`
  /// returns it.
  static func reading(
    showsAdvanced: Bool,
    operatingFlags: [OperatingFlagsRequest: UInt8] = [:],
    values: [UInt8: [SettingName: UInt8]] = [:],
    buttons: [UInt8] = [0x01]
  ) -> DeviceSettingsReading {

    DeviceSettingsReading(
      productName: "Example Dimmer 9001",
      commandSet: commands,
      items: commands.settingItems.filter { (item: SettingItem) -> Bool in showsAdvanced || !item.isAdvanced },
      operatingFlags: operatingFlags,
      values: values,
      buttons: buttons
    )

  }

}

struct DeviceSettingsTextTests {

  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)

  // MARK: - Lines

  @Test func listsSettingsBySectionWithTheirValuesAndDefaults() {

    let reading = ExampleSettings.reading(showsAdvanced: false, operatingFlags: [0x00: 0x21, 0x01: 0x07], values: [0x01: ["rampRate": 0x1F, "onLevel": 0x80]])
    let lines: [SettingLine] = SettingsText.lines(for: reading)
    let texts: [String] = lines.map { "\($0.section) | \($0.title): \($0.valueText) (\($0.notes))" }

    #expect(texts == [
      "Load | Load sense: on (read-only)",
      "Load | Ramp rate: 0.1 s (default 0.5 s, writable)",
      "Load | On-level: 50% (writable)",
      "Buttons | Beep on button press: on (default off, writable)",
      "Diagnostics | ALL-Link database changes: 7 (read-only)"
    ])
    #expect(lines.first { $0.name == "rampRate" }?.raw == "0x1F")
    #expect(reading.advancedSettingsLeftOut == 1)

  }

  @Test func marksWhatTheDeviceDidntReport() throws {

    let lines: [SettingLine] = SettingsText.lines(for: ExampleSettings.reading(showsAdvanced: true))
    let radio = try #require(lines.first { $0.name == "radioOff" })

    #expect(radio.value == nil)
    #expect(radio.valueText == "not reported")
    #expect(radio.isAdvanced)
    #expect(lines.count == 6)

  }

  @Test func showsTheRadioFlagAsReadOnlyThoughTheCatalogGivesItsCommands() throws {

    let lines: [SettingLine] = SettingsText.lines(for: ExampleSettings.reading(showsAdvanced: true, operatingFlags: [0x05: 0x00]))
    let radio = try #require(lines.first { $0.name == "radioOff" })

    #expect(radio.value == "off")
    #expect(!radio.isWritable)
    #expect(radio.notes == "read-only")

  }

  @Test func listsAPerButtonValueForEachButton() {

    let reading = ExampleSettings.reading(
      showsAdvanced: false,
      values: [0x01: ["rampRate": 0x1C, "onLevel": 0xFF], 0x02: ["rampRate": 0x1F, "onLevel": 0x00]],
      buttons: [0x01, 0x02]
    )
    let lines: [SettingLine] = SettingsText.lines(for: reading)
    let titles: [String] = lines.filter { $0.section == "Load" }.map { "\($0.title): \($0.valueText)" }

    // The on-level's write is the whole device's, so it's read from button 1 only.
    #expect(titles == ["Load sense: not reported", "Ramp rate (button 1): 0.5 s", "Ramp rate (button 2): 0.1 s", "On-level: 100%"])

  }

  @Test func saysWhatAValueTakes() {

    let rampRate = DeviceSettingInput(form: .label(examples: ["0.5 s", "0.1 s"], durationExample: "0.5s"), bytes: 0x00...0x1F)
    let onLevel = DeviceSettingInput(form: .number(unit: "percent", symbol: "%"), bytes: 0x00...0xFF)
    let mask = DeviceSettingInput(form: .buttons, bytes: 0x00...0xFF)
    let count = DeviceSettingInput(form: .range(0x01...0x0A), bytes: 0x01...0x0A)
    let byte = DeviceSettingInput(form: .byte, bytes: 0x00...0xFF)

    #expect(SettingsText.expectedInput(rampRate) == "a label such as 0.5 s, 0.1 s, or a duration such as 0.5s, or a byte from 0x00 to 0x1F")
    #expect(SettingsText.expectedInput(onLevel) == "a number in percent such as 50%, or a byte from 0x00 to 0xFF")
    #expect(SettingsText.expectedInput(mask) == "buttons such as 1,3, or none, or a byte from 0x00 to 0xFF")
    #expect(SettingsText.expectedInput(count) == "a number from 1 to 10, or a byte from 0x01 to 0x0A")
    #expect(SettingsText.expectedInput(byte) == "a byte from 0x00 to 0xFF")

    let unreadable = SettingsText.failure(.unreadableValue("bright", label: "On-level", accepts: onLevel), device: "1A.2B.3C")
    let outOfRange = SettingsText.failure(.valueOutOfRange("0x20", label: "Ramp rate", accepts: rampRate), device: "1A.2B.3C")

    #expect(unreadable == "'bright' isn't a value On-level takes: expected a number in percent such as 50%, or a byte from 0x00 to 0xFF.")
    #expect(outOfRange == "That's outside what Ramp rate takes: expected a label such as 0.5 s, 0.1 s, or a duration such as 0.5s, or a byte from 0x00 to 0x1F.")

  }

  @Test func explainsTheSettingsThatAreNeverWritten() {

    let radio: String = SettingsText.failure(.neverWritten(label: "Turn off radio"), device: "1A.2B.3C")
    let lock: String = SettingsText.failure(.leavesProgrammingLocked(label: "Programming lock"), device: "1A.2B.3C")

    #expect(radio == "Turn off radio is never changed, since a wrong value can cut the device off from the modem.")
    #expect(lock == "Programming lock is never turned on, so the device isn't left locked. Turning it off is allowed.")

  }

  @Test func explainsWhyASettingWasntWritten() {

    #expect(SettingsText.failure(.engineRejected, device: "1A.2B.3C").hasSuffix("Link it first with 'insteon link 1A.2B.3C'."))
    #expect(SettingsText.failure(.missingValue(label: "Ramp rate", other: "onLevel"), device: "1A.2B.3C")
      == "Writing Ramp rate also writes onLevel, which the device didn't report, so nothing was changed.")
    #expect(SettingsText.failure(.unwritableValue(.outOfRange("level"), label: "Ramp rate", value: "0.1 s"), device: "1A.2B.3C")
      == "The Insteon device catalog's command for Ramp rate can't take 0.1 s: it's outside what its parameter level takes, so nothing was changed.")
    #expect(SettingsText.failure(.noCommandForState(label: "Key beep", isOn: true), device: "1A.2B.3C")
      == "Key beep can't be turned on on this device: the Insteon device catalog gives no command that does it.")

  }

  @Test func saysWhatASettingChangedFromAndTo() {

    let setting = DeviceSetting(
      key: "rampRate",
      label: "Ramp rate",
      section: "Load",
      summary: "Ramp rate.",
      isAdvanced: false,
      isWritable: true,
      isPerButton: true,
      control: .choice(["0.5 s", "0.1 s"])
    )
    let confirmed = DeviceSettingChange(setting: setting, button: 2, before: "0.5 s", requested: "0.1 s", after: "0.1 s")
    let unconfirmed = DeviceSettingChange(setting: setting, button: nil, before: nil, requested: "0.1 s", after: nil)

    #expect(SettingsText.change(confirmed) == "Ramp rate (button 2): 0.5 s → 0.1 s")
    #expect(SettingsText.change(unconfirmed) == "Ramp rate: not reported → 0.1 s, not confirmed: the device didn't report the value afterward.")

  }

  // MARK: - Bytes typed in

  @Test func readsAByteWithOrWithout0x() {

    #expect(HexInput.byte("0x2E") == 0x2E)
    #expect(HexInput.byte("2e") == 0x2E)
    #expect(HexInput.byte("5") == 0x05)
    #expect(HexInput.byte("0x123") == nil)
    #expect(HexInput.byte("0x") == nil)
    #expect(HexInput.byte("zz") == nil)

  }

  @Test func readsBytesRunTogetherOrApart() {

    #expect(HexInput.bytes("0277") == [0x02, 0x77])
    #expect(HexInput.bytes("02 77 01") == [0x02, 0x77, 0x01])
    #expect(HexInput.bytes("0x02 0x77") == [0x02, 0x77])
    #expect(HexInput.bytes("027") == nil)
    #expect(HexInput.bytes("") == nil)
    #expect(HexInput.bytes("02 7G") == nil)

  }

  @Test func printsBytesAsPairs() {

    #expect(Hex.pairs([0x02, 0x77, 0x06]) == "02 77 06")

  }

}

struct ExploringArgumentTests {

  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)

  // MARK: - device ADDRESS on, off and instant

  @Test func turnsOnAndOffFast() throws {

    #expect(try Invocation.parse(["device", "1A.2B.3C", "on", "--fast"]).subcommand == .device(lamp, .onFast(levelPercent: nil)))
    #expect(try Invocation.parse(["device", "1A.2B.3C", "on", "30%", "--fast"]).subcommand == .device(lamp, .onFast(levelPercent: 30)))
    #expect(try Invocation.parse(["device", "1A.2B.3C", "off", "--fast"]).subcommand == .device(lamp, .offFast))

  }

  @Test func changesInstantly() throws {

    #expect(try Invocation.parse(["device", "1A.2B.3C", "instant", "40%"]).subcommand == .device(lamp, .instant(levelPercent: 40)))

    #expect(throws: ArgumentError.missingArgument("a level, such as 50%", subcommand: "device ADDRESS instant")) {

      try Invocation.parse(["device", "1A.2B.3C", "instant"])

    }

    #expect(throws: ArgumentError.invalidValue(option: "instant", value: "120", expected: "a level from 0 to 100, such as 50%")) {

      try Invocation.parse(["device", "1A.2B.3C", "instant", "120"])

    }

  }

  @Test func beepsADeviceOrTheModem() throws {

    #expect(try Invocation.parse(["device", "1A.2B.3C", "beep"]).subcommand == .device(lamp, .beep))
    #expect(try Invocation.parse(["beep"]).subcommand == .beep(isDouble: false))
    #expect(try Invocation.parse(["beep", "--double"]).subcommand == .beep(isDouble: true))

  }

  // MARK: - settings and set

  @Test func readsSettingsWithOrWithoutAdvancedOnes() throws {

    #expect(try Invocation.parse(["device", "1A.2B.3C", "settings"]).subcommand == .device(lamp, .settings(showsAdvanced: false)))

    let invocation = try Invocation.parse(["device", "1A.2B.3C", "settings", "--json", "--advanced"])

    #expect(invocation.subcommand == .device(lamp, .settings(showsAdvanced: true)))
    #expect(invocation.printsJSON)

  }

  @Test func setsASettingForAButton() throws {

    #expect(try Invocation.parse(["device", "1A.2B.3C", "set", "rampRate", "0.5s"]).subcommand
      == .device(lamp, .set(SettingRequest(name: "rampRate", value: "0.5s"))))
    #expect(try Invocation.parse(["device", "1A.2B.3C", "set", "rampRate", "0.5", "s", "--button", "3"]).subcommand
      == .device(lamp, .set(SettingRequest(name: "rampRate", value: "0.5 s", button: 3))))

  }

  @Test func needsASettingsNameValueAndAButtonInRange() {

    #expect(throws: ArgumentError.missingArgument("a VALUE for keyBeep", subcommand: "device ADDRESS set")) {

      try Invocation.parse(["device", "1A.2B.3C", "set", "keyBeep"])

    }

    #expect(throws: ArgumentError.invalidValue(option: "--button", value: "0", expected: "a button or group from 1 to 254")) {

      try Invocation.parse(["device", "1A.2B.3C", "set", "rampRate", "0x1C", "--button", "0"])

    }

  }

  // MARK: - send

  @Test func sendsAStandardOrExtendedMessage() throws {

    #expect(try Invocation.parse(["device", "1A.2B.3C", "send", "0x19", "00"]).subcommand
      == .device(lamp, .send(DirectMessageRequest(command1: 0x19, command2: 0x00))))
    #expect(try Invocation.parse(["device", "1A.2B.3C", "send", "2E", "00", "--extended", "01", "--wait", "5"]).subcommand
      == .device(lamp, .send(DirectMessageRequest(command1: 0x2E, command2: 0x00, userData: [0x01], waitSeconds: 5))))
    #expect(try Invocation.parse(["device", "1A.2B.3C", "send", "2E", "00", "--extended", "--no-checksum"]).subcommand
      == .device(lamp, .send(DirectMessageRequest(command1: 0x2E, command2: 0x00, userData: [], hasChecksum: false))))

  }

  @Test func sendsAll14DataBytesAsGiven() throws {

    let data: [String] = (1...14).map { String($0, radix: 16) }
    let invocation = try Invocation.parse(["device", "1A.2B.3C", "send", "2E", "00", "--extended"] + data)
    let userData: [UInt8] = Array(1...14)
    let expected = DirectMessageRequest(command1: 0x2E, command2: 0x00, userData: userData, hasChecksum: false)

    #expect(invocation.subcommand == .device(lamp, .send(expected)))

  }

  @Test func refusesAMalformedMessage() {

    #expect(throws: ArgumentError.missingArgument("CMD1 and CMD2, such as 0x19 0x00", subcommand: "device ADDRESS send")) {

      try Invocation.parse(["device", "1A.2B.3C", "send", "19"])

    }

    #expect(throws: ArgumentError.invalidValue(option: "CMD2", value: "0x100", expected: "a byte in hexadecimal, such as 0x2E")) {

      try Invocation.parse(["device", "1A.2B.3C", "send", "19", "0x100"])

    }

    #expect(throws: ArgumentError.invalidValue(option: "--extended", value: "0F", expected: "up to 14 bytes in hexadecimal, D1 through D14")) {

      try Invocation.parse(["device", "1A.2B.3C", "send", "2E", "00", "--extended"] + Array(repeating: "00", count: 14) + ["0F"])

    }

  }

  @Test func refusesPokeBeforeOpeningTheModem() throws {

    #expect(throws: ArgumentError.neverSent(.protected(.poke))) {

      try Invocation.parse(["device", "1A.2B.3C", "send", "29", "00"])

    }

    // Whether a protected Set Operating Flags is sent depends on the device's command set, so
    // the network decides; Set Address MSB writes nothing.
    #expect(try Invocation.parse(["device", "1A.2B.3C", "send", "20", "19"]).subcommand
      == .device(lamp, .send(DirectMessageRequest(command1: 0x20, command2: 0x19))))
    #expect(try Invocation.parse(["device", "1A.2B.3C", "send", "28", "0F"]).subcommand
      == .device(lamp, .send(DirectMessageRequest(command1: 0x28, command2: 0x0F))))

  }

  // MARK: - scene

  @Test func sendsAGroupOnOrOff() throws {

    #expect(try Invocation.parse(["scene", "3", "on"]).subcommand == .scene(group: 3, isOn: true))
    #expect(try Invocation.parse(["group", "0", "off"]).subcommand == .scene(group: 0, isOn: false))
    #expect(try Invocation.parse(["help", "group"]).subcommand == .help(topic: "scene"))

    #expect(throws: ArgumentError.invalidValue(option: "scene", value: "dim", expected: "on or off")) {

      try Invocation.parse(["scene", "3", "dim"])

    }

    #expect(throws: ArgumentError.invalidValue(option: "GROUP", value: "255", expected: "a group number from 0 to 254")) {

      try Invocation.parse(["scene", "255", "on"])

    }

  }

  // MARK: - modem send

  @Test func sendsTheModemASerialCommand() throws {

    #expect(try Invocation.parse(["modem", "send", "0277"]).subcommand == .modemSend(RawSerialRequest(bytes: [0x02, 0x77])))
    #expect(try Invocation.parse(["modem", "send", "02", "77", "01", "--wait", "2"]).subcommand
      == .modemSend(RawSerialRequest(bytes: [0x02, 0x77, 0x01], waitSeconds: 2)))
    #expect(try Invocation.parse(["modem", "send", "0267", "--force"]).subcommand == .modemSend(RawSerialRequest(bytes: [0x02, 0x67], isForced: true)))

  }

  @Test func refusesAModemCommandThatCouldDoHarmWithoutForce() throws {

    #expect(throws: ArgumentError.refusedSerialCommand("Reset the IM (0x67) erases the modem's ALL-Link database and configuration.")) {

      try Invocation.parse(["modem", "send", "0267"])

    }

    #expect(throws: ArgumentError.invalidValue(option: "send", value: "0360", expected: "a serial command, which starts with 02")) {

      try Invocation.parse(["modem", "send", "0360"])

    }

    #expect(throws: ArgumentError.missingArgument("an action: send", subcommand: "modem")) {

      try Invocation.parse(["modem"])

    }

    // Start ALL-Linking in delete mode, and messages that write to a device.
    let deleteLinking: [UInt8] = [0x02, 0x64, 0xFF, 0x00]
    let databaseWrite: [UInt8] = [0x02, 0x62, 0x1A, 0x2B, 0x3C, 0x1F, 0x2F, 0x00] + [UInt8](repeating: 0x00, count: 14)
    let databaseRead: [UInt8] = [0x02, 0x62, 0x1A, 0x2B, 0x3C, 0x0F, 0x2F, 0x00]
    let operatingFlags: [UInt8] = [0x02, 0x62, 0x1A, 0x2B, 0x3C, 0x0F, 0x20, 0x04]
    var extendedSet: [UInt8] = [0x02, 0x62, 0x1A, 0x2B, 0x3C, 0x1F, 0x2E, 0x00] + [UInt8](repeating: 0x00, count: 14)
    extendedSet[9] = 0x06

    #expect(SerialCommandPolicy.refusal(for: deleteLinking) != nil)
    #expect(SerialCommandPolicy.refusal(for: databaseWrite) != nil)
    #expect(SerialCommandPolicy.refusal(for: databaseRead) != nil)
    #expect(SerialCommandPolicy.refusal(for: operatingFlags) != nil)
    #expect(SerialCommandPolicy.refusal(for: extendedSet) != nil)

    #expect(throws: ArgumentError.self) {

      try Invocation.parse(["modem", "send", "0264FF00"])

    }

    // Commands with the wrong length.
    let wrongLength: [[UInt8]] = [
      [0x02, 0x64, 0x01],
      [0x02, 0x62, 0x1A, 0x2B, 0x3C, 0x0F, 0x11],
      [0x02, 0x62, 0x1A, 0x2B, 0x3C, 0x1F, 0x2E, 0x00],
      [0x02, 0x77, 0x01, 0x00],
      [0x02, 0x60, 0x00],
      [0x02, 0x62, 0x1A]
    ]

    for bytes in wrongLength {

      #expect(SerialCommandPolicy.refusal(for: bytes) != nil, "\(bytes)")

    }

    // Commands with the right length, which are sent.
    let extendedGet: [UInt8] = [0x02, 0x62, 0x1A, 0x2B, 0x3C, 0x1F, 0x2E, 0x00] + [UInt8](repeating: 0x00, count: 14)
    let rightLength: [[UInt8]] = [
      [0x02, 0x60],
      [0x02, 0x64, 0x01, 0x00],
      [0x02, 0x62, 0x1A, 0x2B, 0x3C, 0x0F, 0x11, 0xFF],
      [0x02, 0x77],
      [0x02, 0x77, 0x01],
      [0x02, 0x73],
      [0x02, 0x7A, 0x03],
      extendedGet
    ]

    for bytes in rightLength {

      #expect(SerialCommandPolicy.refusal(for: bytes) == nil, "\(bytes)")

    }

    #expect(try Invocation.parse(["modem", "send", "0264FF00", "--force"]).subcommand == .modemSend(RawSerialRequest(bytes: deleteLinking, isForced: true)))

  }

  @Test func neverWritesAProtectedCommandEvenWhenForced() {

    for forcing in [[], ["--force"]] {

      #expect(throws: ArgumentError.neverSent(.protected(.checksumOn))) {

        try Invocation.parse(["modem", "send", "02621A2B3C0F2019"] + forcing)

      }

      #expect(throws: ArgumentError.neverSent(.protected(.powerlineOff))) {

        try Invocation.parse(["modem", "send", "0261", "01", "200E"] + forcing)

      }

      #expect(throws: ArgumentError.neverSent(.protected(.poke))) {

        try Invocation.parse(["modem", "send", "02621A2B3C0F29FF"] + forcing)

      }

      #expect(throws: ArgumentError.neverSent(.incompleteMessage)) {

        try Invocation.parse(["modem", "send", "02621A2B3C0F20"] + forcing)

      }

    }

  }

  @Test func wordsEveryRefusalInOneLine() {

    let refusals: [SendRefusal] = ProtectedCommand.allCases.map { (command: ProtectedCommand) -> SendRefusal in .protected(command) } + [
      .neverSentToDevice(product: "Example"),
      .writesGuardedFlags(label: "Programming lock"),
      .extendedSetWithoutCommandSet,
      .notSerialCommand,
      .incompleteMessage,
      .serialCommand("Reset the IM (0x67) erases the modem's ALL-Link database and configuration.")
    ]

    for refusal in refusals {

      let sentence: String = SendRefusalText.sentence(refusal)

      #expect(!sentence.isEmpty)
      #expect(!sentence.contains("\n"))
      #expect(sentence.hasSuffix("."))
      #expect(ArgumentError.neverSent(refusal).description == sentence)

    }

    #expect(SendRefusalText.sentence(.protected(.radioOff)).hasPrefix("Turning radio off would cut the device off the network; insteon sends it only"))
    #expect(SendRefusalText.sentence(.protected(.poke)).hasSuffix("insteon never sends it."))
    #expect(SendRefusalText.sentence(.serialCommand("Reset.")).hasSuffix("Pass --force to send it anyway."))

  }

  @Test func explainsTheNewErrorsInOneLine() {

    let errors: [ArgumentError] = [
      .missingArgument("a VALUE", subcommand: "device ADDRESS set"),
      .refusedSerialCommand("Reset the IM (0x67) erases the modem's ALL-Link database and configuration.")
    ]

    for error in errors {

      #expect(!error.description.isEmpty)
      #expect(!error.description.contains("\n"))

    }

  }

}
