import Foundation
import Testing
import InsteonDeviceCatalog
import InsteonProtocol

struct CommandSetTests {

  let keypad = InsteonAddress(0x1A, 0x2B, 0x3C)

  let modem = InsteonAddress(0x11, 0x22, 0x33)

  static let keypadSet = #"""
    {
      "id": "keypad",
      "name": "Keypad",
      "description": "Keypads.",
      "operatingFlags": [
        { "name": "keyBeep", "description": "Buttons beep.", "query": "0x00", "bit": "0x20", "on": "0x0A", "off": "0x0B" },
        { "name": "eightButtons", "description": "Eight buttons.", "query": "0x00", "bit": "0x08" }
      ],
      "readings": [{ "name": "databaseDelta", "description": "Delta.", "query": "0x01" }],
      "flagCommands": [{ "name": "smartHopsOn", "description": "Smart hops.", "command2": "0x1C" }],
      "extendedSettings": {
        "perButton": true,
        "values": [
          { "name": "offMask", "description": "Off mask.", "byte": 4, "kind": "buttons" },
          { "name": "rampRate", "description": "Ramp rate.", "byte": 7, "range": { "from": "0x00", "through": "0x1F" } },
          { "name": "triggerMask", "description": "Later.", "byte": 14, "kind": "somethingNewer" }
        ],
        "writes": [
          { "name": "offMask", "description": "Off mask.", "selector": "0x03", "perButton": true, "bytes": [{ "position": 3, "value": "offMask" }, { "position": 4, "value": "groupMask" }] },
          { "name": "ledBrightness", "description": "LEDs.", "selector": "0x07", "perButton": false, "bytes": [{ "position": 3, "value": "ledBrightness" }] }
        ]
      },
      "notes": ["A note."],
      "sources": ["Insteon command workbook"]
    }
    """#

  static let profile = #"""
    {
      "model": "2334",
      "name": "Dimmer Keypad",
      "identities": [{ "category": "0x01", "subcategory": "0x41" }, { "category": "0x01", "subcategory": "0x42" }],
      "commandSets": [{ "commandSet": "keypad", "category": "0x01", "subcategory": "0x41", "firmware": { "except": ["0x30"] } }],
      "capabilities": [],
      "sources": ["A"]
    }
    """#

  func catalog() throws -> DeviceCatalog {

    try DeviceCatalog(json: Data(#"{ "schemaVersion": 1, "devices": [\#(Self.profile)], "commandSets": [\#(Self.keypadSet)] }"#.utf8))

  }

  @Test func findsTheCommandSetForAnIdentityAndFirmware() throws {

    let catalog = try catalog()

    #expect(catalog.commandSet(category: 0x01, subcategory: 0x41, firmwareVersion: 0x45)?.name == "Keypad")
    #expect(catalog.commandSet(category: 0x01, subcategory: 0x41, firmwareVersion: 0x30) == nil)
    #expect(catalog.commandSet(category: 0x01, subcategory: 0x41, firmwareVersion: nil) == nil)
    #expect(catalog.commandSet(category: 0x01, subcategory: 0x42, firmwareVersion: 0x45) == nil)
    #expect(catalog.commandSet(id: "keypad")?.notes == ["A note."])
    #expect(catalog.profile(model: "2334")?.commandSets == [
      CommandSetEntry(commandSet: "keypad", category: 0x01, subcategory: 0x41, firmware: .except([0x30])),
    ])

  }

  @Test func readsAndSetsOperatingFlags() throws {

    let commands = try #require(try catalog().commandSet(id: "keypad"))
    let beep = try #require(commands.operatingFlag(named: "keyBeep"))
    let ack = ReceivedMessage(sender: keypad, destination: modem, flags: MessageFlags(messageType: .directAcknowledgement), command: Command(command1: 0x1F, command2: 0x28))

    #expect(beep.readCommand.command == Command(command1: 0x1F, command2: 0x00))
    #expect(beep.isSet(in: ack) == true)
    #expect(commands.operatingFlag(named: "eightButtons")?.isSet(in: ack) == true)
    #expect(beep.command(setting: false)?.command == Command(command1: 0x20, command2: 0x0B))
    #expect(beep.command(setting: true)?.command == Command(command1: 0x20, command2: 0x0A))
    #expect(commands.operatingFlag(named: "eightButtons")?.command(setting: true) == nil)
    #expect(commands.readings.first?.query == 0x01)
    #expect(commands.flagCommands.first?.command.command == Command(command1: 0x20, command2: 0x1C))

    let other = ReceivedMessage(sender: keypad, destination: modem, flags: MessageFlags(messageType: .directAcknowledgement), command: Command(command1: 0x19, command2: 0x28))
    #expect(beep.isSet(in: other) == nil)

  }

  @Test func readsAGetsReply() throws {

    let settings = try #require(try catalog().commandSet(id: "keypad")?.extendedSettings)
    let reply = ReceivedMessage(
      sender: keypad,
      destination: modem,
      flags: MessageFlags(messageType: .direct, isExtended: true),
      command: Command(command1: 0x2E),
      userData: try UserData([0x03, 0x01, 0x00, 0x38, 0x00, 0x00, 0x1C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04])
    )

    #expect(settings.isPerButton)
    #expect(settings.values.map(\.kind) == [.buttons, .number, .number])
    #expect(settings.values[1].range == 0x00...0x1F)
    #expect(settings.values(in: reply) == ["offMask": 0x38, "rampRate": 0x1C, "triggerMask": 0x04])
    #expect(settings.getUserData(button: 3).bytes.prefix(2) == [0x03, 0x00])

    let request = ReceivedMessage(sender: keypad, destination: modem, flags: MessageFlags(messageType: .direct, isExtended: true), command: Command(command1: 0x2E), userData: settings.getUserData(button: 3))
    #expect(settings.values(in: request) == nil)

  }

  // The radio group for buttons 3 to 6 from Insteon's command workbook: 03 03 38 3C for button 3.
  @Test func writesASetsBytes() throws {

    let settings = try #require(try catalog().commandSet(id: "keypad")?.extendedSettings)
    let offMask = try #require(settings.write(named: "offMask"))
    let leds = try #require(settings.write(named: "ledBrightness"))

    #expect(try offMask.userData(button: 3, values: ["offMask": 0x38, "groupMask": 0x3C]).bytes.prefix(4) == [0x03, 0x03, 0x38, 0x3C])
    #expect(try leds.userData(button: 3, values: ["ledBrightness": 0x7F]).bytes.prefix(3) == [0x01, 0x07, 0x7F])

    #expect(throws: SettingWriteError.missingValue("groupMask")) {

      try offMask.userData(button: 3, values: ["offMask": 0x38])

    }

  }

  @Test(arguments: [
    #""values": [{ "name": "a", "description": "A.", "byte": 2 }]"#,
    #""values": [{ "name": "a", "description": "A.", "byte": 7, "range": { "from": "0x1F", "through": "0x00" } }]"#,
    #""writes": [{ "name": "a", "description": "A.", "selector": "0x05", "perButton": false, "bytes": [{ "position": 15, "value": "a" }] }]"#,
  ])
  func refusesAMalformedLayout(_ layout: String) {

    let commandSet = #"{ "id": "a", "name": "A", "description": "A.", "extendedSettings": { "perButton": false, \#(layout) }, "sources": ["A"] }"#

    #expect(throws: DecodingError.self) {

      try DeviceCatalog(json: Data(#"{ "schemaVersion": 1, "devices": [], "commandSets": [\#(commandSet)] }"#.utf8))

    }

  }

  @Test func readsACatalogWithoutCommandSets() throws {

    let catalog = try DeviceCatalog(json: Data(#"{ "schemaVersion": 1, "devices": [] }"#.utf8))

    #expect(catalog.commandSets.isEmpty)

  }

  @Test func findsTheBundledDimmersSettings() throws {

    let catalog = try DeviceCatalog.bundled()
    let commands = try #require(catalog.commandSet(category: 0x01, subcategory: 0x20, firmwareVersion: 0x41))
    let rampRate = try #require(commands.extendedSettings?.write(named: "rampRate"))

    #expect(commands.id == "switchLincDimmer")
    #expect(commands.operatingFlag(named: "keyBeep")?.command(setting: false)?.command == Command(command1: 0x20, command2: 0x0B))
    #expect(try rampRate.userData(values: ["rampRate": 0x1C]).bytes.prefix(3) == [0x01, 0x05, 0x1C])

    // Every command set a profile names is in the catalog.
    for profile in catalog.profiles {

      for entry in profile.commandSets {

        #expect(catalog.commandSet(id: entry.commandSet) != nil)

      }

    }

  }

}
