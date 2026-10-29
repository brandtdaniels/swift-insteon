import Foundation
import Testing
import InsteonDeviceCatalog
import InsteonProtocol

struct DeviceSettingsTests {

  let dimmer = InsteonAddress(0x1A, 0x2B, 0x3C)

  static let dimmerSet = #"""
    {
      "id": "exampleDimmer",
      "name": "Example Dimmer",
      "description": "A made-up dimmer.",
      "operatingFlags": [
        { "name": "radioOff", "description": "Radio off.", "query": "0x00", "bit": "0x40", "on": "0x0C", "off": "0x0D",
          "label": "Turn off radio", "section": "Communication", "advanced": true },
        { "name": "keyBeep", "description": "Buttons beep.", "query": "0x00", "bit": "0x20", "on": "0x0A", "off": "0x0B",
          "label": "Beep on button press", "section": "Buttons", "default": false },
        { "name": "nightMode", "description": "Night.", "query": "0x05", "bit": "0x02",
          "onCommand": "nightModeOn", "offCommand": "nightModeOff", "label": "Night mode", "section": "Night" },
        { "name": "loadSense", "description": "Load sense.", "query": "0x00", "bit": "0x01", "label": "Load sense", "section": "Load" },
        { "name": "fromLater", "description": "A later section.", "query": "0x00", "bit": "0x80", "section": "Somewhere" }
      ],
      "readings": [
        { "name": "databaseDelta", "description": "Delta.", "query": "0x01", "label": "ALL-Link database changes",
          "section": "Diagnostics", "advanced": true }
      ],
      "standardCommands": [
        { "name": "nightModeOn", "description": "Night on.", "command1": "0x3B" },
        { "name": "nightModeOff", "description": "Night off.", "command1": "0x3C" }
      ],
      "extendedCommands": [
        { "name": "writeOnLevel", "description": "Sets the on-level.", "command1": "0x2E", "command2": "0x00",
          "fixed": [{ "position": 2, "value": "0x06" }], "integrity": "checksum",
          "parameters": [{ "name": "onLevel", "description": "On-level.", "byte": 3 }] }
      ],
      "extendedSettings": {
        "perButton": true,
        "values": [
          { "name": "x10HouseCode", "description": "House code.", "byte": 5, "label": "X10 house code", "section": "X10", "advanced": true },
          { "name": "x10UnitCode", "description": "Unit code.", "byte": 6, "label": "X10 unit code", "section": "X10", "advanced": true },
          { "name": "rampRate", "description": "Ramp rate.", "byte": 7, "range": { "from": "0x00", "through": "0x1F" },
            "label": "Ramp rate", "section": "Load", "table": "rampRate", "default": "0x1C" },
          { "name": "onLevel", "description": "On-level.", "byte": 8, "label": "On-level", "section": "Load",
            "unit": "percent", "scale": 0.392157, "write": "writeOnLevel" },
          { "name": "ledBrightness", "description": "LEDs.", "byte": 9, "range": { "from": "0x11", "through": "0x7F" },
            "label": "LED brightness", "section": "LEDs" },
          { "name": "offMask", "description": "Off mask.", "byte": 10, "kind": "buttons", "label": "Buttons turned off", "section": "Buttons" },
          { "name": "signalToNoise", "description": "Signal.", "byte": 11, "section": "Diagnostics" }
        ],
        "writes": [
          { "name": "x10Address", "description": "X10.", "selector": "0x04", "perButton": true,
            "bytes": [{ "position": 3, "value": "x10HouseCode" }, { "position": 4, "value": "x10UnitCode" }] },
          { "name": "rampRate", "description": "Ramp rate.", "selector": "0x05", "perButton": true,
            "bytes": [{ "position": 3, "value": "rampRate" }] },
          { "name": "ledBrightness", "description": "LEDs.", "selector": "0x07", "perButton": false,
            "bytes": [{ "position": 3, "value": "ledBrightness" }] },
          { "name": "offMask", "description": "Off mask.", "selector": "0x03", "perButton": false,
            "bytes": [{ "position": 3, "value": "offMask" }] }
        ]
      },
      "valueTables": [
        { "name": "rampRate", "description": "Ramp rates.", "values": [
          { "value": "0x00", "label": "2 s", "seconds": 2 },
          { "value": "0x1C", "label": "0.5 s", "seconds": 0.5 },
          { "value": "0x1F", "label": "0.1 s", "seconds": 0.1 },
          { "value": "0x01", "label": "8 min", "seconds": 480 }
        ] }
      ],
      "sources": ["Insteon Developer's Guide"]
    }
    """#

  func commands() throws -> CommandSet {

    try JSONDecoder().decode(CommandSet.self, from: Data(Self.dimmerSet.utf8))

  }

  func value(_ name: SettingName) throws -> SettingValue {

    try #require(try commands().extendedSettings?.value(named: name))

  }

  // MARK: - Decoding

  @Test func readsWhatASettingsPageNeeds() throws {

    let commands = try commands()
    let beep = try #require(commands.operatingFlag(named: "keyBeep"))
    let night = try #require(commands.operatingFlag(named: "nightMode"))
    let rampRate = try value("rampRate")
    let onLevel = try value("onLevel")

    #expect(beep.label == "Beep on button press")
    #expect(beep.section == .buttons)
    #expect(beep.defaultValue == false)
    #expect(beep.isAdvanced == false)
    #expect(commands.operatingFlag(named: "radioOff")?.isAdvanced == true)
    #expect(night.onCommand == "nightModeOn")
    #expect(night.offCommand == "nightModeOff")
    #expect(commands.readings.first?.section == .diagnostics)
    #expect(rampRate.table == "rampRate")
    #expect(rampRate.defaultValue == 0x1C)
    #expect(onLevel.unit == .percent)
    #expect(onLevel.scale == 0.392157)
    #expect(onLevel.write == "writeOnLevel")

  }

  @Test func readsASectionFromALaterCatalogAsNone() throws {

    #expect(try commands().operatingFlag(named: "fromLater")?.section == nil)

  }

  @Test func refusesAScaleOfZero() {

    let json = Self.dimmerSet.replacingOccurrences(of: #""scale": 0.392157"#, with: #""scale": 0"#)

    #expect(throws: DecodingError.self) {

      try JSONDecoder().decode(CommandSet.self, from: Data(json.utf8))

    }

  }

  // MARK: - Items

  @Test func ordersItemsBySectionThenTheCommandSetsOrder() throws {

    let names: [String] = try commands().settingItems.map(\.name.rawValue)

    #expect(names == [
      "loadSense", "rampRate", "onLevel",
      "keyBeep", "offMask",
      "ledBrightness",
      "nightMode",
      "radioOff",
      "x10HouseCode", "x10UnitCode",
      "databaseDelta", "signalToNoise",
      "fromLater"
    ])

  }

  @Test func labelsAnItemWithItsNameWhenTheCatalogDoesnt() throws {

    let item = try #require(try commands().settingItem(named: "signalToNoise"))

    #expect(item.label == "signalToNoise")
    #expect(item.section == .diagnostics)

  }

  @Test func findsAnItemByItsNameOrLabelInAnyCase() throws {

    let commands = try commands()

    #expect(commands.settingItem(named: "rampRate")?.name == "rampRate")
    #expect(commands.settingItem(named: "RAMPRATE")?.name == "rampRate")
    #expect(commands.settingItem(named: "beep on button press")?.name == "keyBeep")
    #expect(commands.settingItem(named: "volume") == nil)

  }

  @Test func ordersSectionsAsTheCatalogDoes() {

    #expect(SettingSection.load < SettingSection.leds)
    #expect(SettingSection.x10 < SettingSection.diagnostics)
    #expect(SettingSection.allCases.first == .load)

  }

  // MARK: - Writing

  @Test func setsAFlagWithSetOperatingFlagsOrItsCommands() throws {

    let commands = try commands()
    let beep = try #require(commands.operatingFlag(named: "keyBeep"))
    let night = try #require(commands.operatingFlag(named: "nightMode"))
    let loadSense = try #require(commands.operatingFlag(named: "loadSense"))
    let nightModeOn = try #require(commands.standardCommand(named: "nightModeOn"))

    #expect(commands.change(for: beep, setting: true) == .setOperatingFlags(0x0A))
    #expect(commands.change(for: beep, setting: false) == .setOperatingFlags(0x0B))
    #expect(commands.change(for: night, setting: true) == .standardCommand(nightModeOn))
    #expect(commands.change(for: loadSense, setting: true) == nil)
    #expect(commands.isWritable(SettingItem(flag: loadSense)) == false)
    #expect(commands.isWritable(SettingItem(flag: night)))

  }

  @Test func setsAValueWithAnExtendedSetOrItsCommand() throws {

    let commands = try commands()
    let rampRate = try value("rampRate")
    let onLevel = try value("onLevel")
    let signal = try value("signalToNoise")
    let write = try #require(commands.extendedSettings?.write(named: "rampRate"))
    let writeOnLevel = try #require(commands.extendedCommand(named: "writeOnLevel"))

    #expect(commands.change(for: rampRate) == .extendedSet(write))
    #expect(commands.change(for: onLevel) == .extendedCommand(writeOnLevel))
    #expect(commands.change(for: signal) == nil)
    #expect(commands.isWritable(SettingItem(reading: commands.readings[0])) == false)

  }

  @Test func saysWhichValuesArePerButton() throws {

    let settings = try #require(try commands().extendedSettings)

    #expect(settings.isValuePerButton("rampRate"))
    #expect(settings.isValuePerButton("ledBrightness") == false)
    #expect(settings.isValuePerButton("signalToNoise") == false)

  }

  @Test func writesAnExtendedSetKeepingTheOtherBytes() throws {

    let commands = try commands()
    let change = try #require(commands.change(for: try value("x10HouseCode")))
    let message = try change.message(to: dimmer, button: 0x03, setting: "x10HouseCode", to: 0x06, current: ["x10HouseCode": 0x20, "x10UnitCode": 0x02])

    #expect(message.command == Command(command1: 0x2E, command2: 0x00))
    #expect(Array(message.userData.bytes[0..<4]) == [0x03, 0x04, 0x06, 0x02])

  }

  @Test func refusesAnExtendedSetWithoutTheOtherBytes() throws {

    let change = try #require(try commands().change(for: try value("x10HouseCode")))

    #expect(throws: SettingWriteError.missingValue("x10UnitCode")) {

      try change.message(to: dimmer, setting: "x10HouseCode", to: 0x06)

    }

  }

  @Test func writesAValueWithItsExtendedCommand() throws {

    let change = try #require(try commands().change(for: try value("onLevel")))
    let message = try change.message(to: dimmer, setting: "onLevel", to: 0x80)

    #expect(message.userData[2] == 0x06)
    #expect(message.userData[3] == 0x80)

  }

  // MARK: - Text

  @Test func showsAValueByItsTableUnitButtonsOrRange() throws {

    let commands = try commands()

    let rampRate = try value("rampRate")
    let onLevel = try value("onLevel")
    let ledBrightness = try value("ledBrightness")
    let offMask = try value("offMask")
    let houseCode = try value("x10HouseCode")

    #expect(commands.text(for: rampRate, raw: 0x1C) == "0.5 s")
    #expect(commands.text(for: rampRate, raw: 0x10) == "16")
    #expect(commands.text(for: onLevel, raw: 0x80) == "50%")
    #expect(commands.text(for: onLevel, raw: 0xFF) == "100%")
    #expect(commands.text(for: ledBrightness, raw: 0x40) == "64")
    #expect(commands.text(for: offMask, raw: 0x05) == "buttons 1, 3")
    #expect(commands.text(for: offMask, raw: 0x00) == "no buttons")
    #expect(commands.text(for: houseCode, raw: 0x20) == "0x20")

  }

  @Test func readsFlagStates() {

    #expect(OperatingFlag.state(parsing: "on") == true)
    #expect(OperatingFlag.state(parsing: "TRUE") == true)
    #expect(OperatingFlag.state(parsing: "off") == false)
    #expect(OperatingFlag.state(parsing: "0") == false)
    #expect(OperatingFlag.state(parsing: "maybe") == nil)

  }

  static let rampRateTexts: [(String, UInt8)] = [
    ("0.5 s", 0x1C),
    ("0.5S", 0x1C),
    ("0.1 seconds", 0x1F),
    ("8 min", 0x01),
    ("2 sec", 0x00),
    ("0x10", 0x10)
  ]

  @Test(arguments: rampRateTexts)
  func readsATablesLabelDurationOrByte(text: String, raw: UInt8) throws {

    let commands = try commands()
    let rampRate = try value("rampRate")

    #expect(try commands.raw(for: rampRate, parsing: text) == raw)

  }

  @Test func readsANumberInItsUnit() throws {

    let commands = try commands()
    let onLevel = try value("onLevel")

    // 50 / 0.392157 is just under 127.5.
    #expect(try commands.raw(for: onLevel, parsing: "50%") == 0x7F)
    #expect(try commands.raw(for: onLevel, parsing: "50") == 0x7F)
    #expect(try commands.raw(for: onLevel, parsing: "100 %") == 0xFF)
    let ledBrightness = try value("ledBrightness")

    #expect(try commands.raw(for: ledBrightness, parsing: "64") == 0x40)

  }

  @Test func readsButtons() throws {

    let commands = try commands()
    let offMask = try value("offMask")

    #expect(try commands.raw(for: offMask, parsing: "1,3") == 0x05)
    #expect(try commands.raw(for: offMask, parsing: "none") == 0x00)

    #expect(throws: SettingInputError.outOfRange("offMask")) {

      try commands.raw(for: offMask, parsing: "9")

    }

  }

  @Test func refusesAValueOutsideItsRange() throws {

    let commands = try commands()

    #expect(throws: SettingInputError.outOfRange("ledBrightness")) {

      try commands.raw(for: try value("ledBrightness"), parsing: "0x05")

    }

    #expect(throws: SettingInputError.outOfRange("onLevel")) {

      try commands.raw(for: try value("onLevel"), parsing: "150%")

    }

    #expect(throws: SettingInputError.outOfRange("rampRate")) {

      try commands.raw(for: try value("rampRate"), parsing: "3 s")

    }

  }

  @Test func refusesTextThatIsntAValue() throws {

    let commands = try commands()

    #expect(throws: SettingInputError.unreadable("onLevel", "bright")) {

      try commands.raw(for: try value("onLevel"), parsing: "bright")

    }

    #expect(throws: SettingInputError.unreadable("onLevel", "50 s")) {

      try commands.raw(for: try value("onLevel"), parsing: "50 s")

    }

    // A bare number for a value with a table could be a byte or a duration.
    #expect(throws: SettingInputError.unreadable("rampRate", "2")) {

      try commands.raw(for: try value("rampRate"), parsing: "2")

    }

    #expect(throws: SettingInputError.unreadable("ledBrightness", "0x123")) {

      try commands.raw(for: try value("ledBrightness"), parsing: "0x123")

    }

  }

  @Test func readsTheBundledDimmersSettings() throws {

    let catalog = try DeviceCatalog.bundled()
    let commands = try #require(catalog.commandSet(id: "switchLincDimmer"))
    let rampRate = try #require(commands.extendedSettings?.value(named: "rampRate"))

    #expect(rampRate.label == "Ramp rate")
    #expect(rampRate.section == .load)
    #expect(commands.settingItems.first?.section == .load)
    #expect(commands.operatingFlag(named: "keyBeep")?.label == "Beep on button press")

  }

}
