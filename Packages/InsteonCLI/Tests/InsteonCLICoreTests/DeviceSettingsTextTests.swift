import Testing
import InsteonCLICore
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

}

struct DeviceSettingsTextTests {

  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)

  // MARK: - Lines

  @Test func listsSettingsBySectionWithTheirValuesAndDefaults() {

    let reported = ReportedSettings(operatingFlags: [0x00: 0x21, 0x01: 0x07], values: [0x01: ["rampRate": 0x1F, "onLevel": 0x80]])
    let lines: [SettingLine] = SettingsText.lines(for: ExampleSettings.commands, reported: reported, showsAdvanced: false)
    let texts: [String] = lines.map { "\($0.section) | \($0.title): \($0.valueText) (\($0.notes))" }

    #expect(texts == [
      "Load | Load sense: on (read-only)",
      "Load | Ramp rate: 0.1 s (default 0.5 s, writable)",
      "Load | On-level: 50% (writable)",
      "Buttons | Beep on button press: on (default off, writable)",
      "Diagnostics | ALL-Link database changes: 7 (read-only)"
    ])

  }

  @Test func marksWhatTheDeviceDidntReport() throws {

    let lines: [SettingLine] = SettingsText.lines(for: ExampleSettings.commands, reported: ReportedSettings(), showsAdvanced: true)
    let radio = try #require(lines.first { $0.name == "radioOff" })

    #expect(radio.value == nil)
    #expect(radio.valueText == "not reported")
    #expect(radio.isAdvanced)
    #expect(lines.count == 6)

  }

  @Test func listsAPerButtonValueForEachButton() {

    let reported = ReportedSettings(values: [0x01: ["rampRate": 0x1C, "onLevel": 0xFF], 0x02: ["rampRate": 0x1F, "onLevel": 0x00]])
    let lines: [SettingLine] = SettingsText.lines(for: ExampleSettings.commands, reported: reported, buttons: [0x01, 0x02], showsAdvanced: false)
    let titles: [String] = lines.filter { $0.section == "Load" }.map { "\($0.title): \($0.valueText)" }

    // The on-level's write is the whole device's, so it's read from button 1 only.
    #expect(titles == ["Load sense: not reported", "Ramp rate (button 1): 0.5 s", "Ramp rate (button 2): 0.1 s", "On-level: 100%"])

  }

  @Test func saysWhatAValueTakes() {

    let commands = ExampleSettings.commands

    #expect(SettingsText.expectedInput(for: ExampleSettings.rampRate, in: commands) == "a label such as 0.5 s, 0.1 s, or a duration such as 0.5s, or a byte from 0x00 to 0x1F")
    #expect(SettingsText.expectedInput(for: ExampleSettings.onLevel, in: commands) == "a number in percent such as 50%, or a byte from 0x00 to 0xFF")

    let problem = SettingsText.inputProblem(SettingInputError.unreadable("onLevel", "bright"), value: ExampleSettings.onLevel, label: "On-level", in: commands)

    #expect(problem == "'bright' isn't a value On-level takes: expected a number in percent such as 50%, or a byte from 0x00 to 0xFF.")

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

  @Test func refusesSerialCommandsThatChangeWhatTheModemKeeps() {

    #expect(SerialCommandPolicy.refusal(for: [0x02, 0x77]) == nil)
    #expect(SerialCommandPolicy.refusal(for: [0x02, 0x60]) == nil)
    #expect(SerialCommandPolicy.refusal(for: [0x02, 0x67]) != nil)
    #expect(SerialCommandPolicy.refusal(for: [0x02, 0x6F, 0x80]) != nil)
    #expect(SerialCommandPolicy.refusal(for: [0x02, 0x76]) != nil)
    #expect(SerialCommandPolicy.refusal(for: [0x02, 0x99]) != nil)
    #expect(SerialCommandPolicy.refusal(for: [0x02]) != nil)

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
    #expect(try Invocation.parse(["modem", "send", "0267", "--force"]).subcommand == .modemSend(RawSerialRequest(bytes: [0x02, 0x67])))

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

    #expect(try Invocation.parse(["modem", "send", "0264FF00", "--force"]).subcommand == .modemSend(RawSerialRequest(bytes: deleteLinking)))

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
