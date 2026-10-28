import Foundation
import Testing
import InsteonDeviceCatalog
import InsteonProtocol

struct MessageFieldTests {

  let thermostat = InsteonAddress(0x1A, 0x2B, 0x3C)

  let modem = InsteonAddress(0x11, 0x22, 0x33)

  func commandSet(_ id: CommandSetID) throws -> CommandSet {

    try #require(try DeviceCatalog.bundled().commandSet(id: id))

  }

  func message(_ type: MessageFlags.MessageType, _ command1: UInt8, _ command2: UInt8, userData: UserData? = nil) -> ReceivedMessage {

    ReceivedMessage(
      sender: thermostat,
      destination: modem,
      flags: MessageFlags(messageType: type, isExtended: userData != nil),
      command: Command(command1: command1, command2: command2),
      userData: userData
    )

  }

  @Test func findsEachThermostatsCommandSet() throws {

    let catalog = try DeviceCatalog.bundled()

    #expect(catalog.commandSet(category: 0x05, subcategory: 0x03, firmwareVersion: nil)?.id == "thermostatAdapter")
    #expect(catalog.commandSet(category: 0x05, subcategory: 0x0B, firmwareVersion: nil)?.id == "tempLinc")
    #expect(catalog.profile(model: "2441V")?.capabilities.contains(.thermostat(measuresHumidity: false)) == true)

  }

  @Test func writesAStandardCommandsValueInCommand2() throws {

    let adapter = try commandSet("thermostatAdapter")
    let setHeat = try #require(adapter.standardCommand(named: "setHeatSetpoint"))
    let setMode = try #require(adapter.standardCommand(named: "setMode"))

    // Setpoints are in half degrees.
    #expect(try setHeat.command(.number(68)) == Command(command1: 0x6D, command2: 0x88))
    #expect(try setMode.command(.named("heat")) == Command(command1: 0x6B, command2: 0x04))
    #expect(try adapter.standardCommand(named: "readMode")?.command() == Command(command1: 0x6B, command2: 0x02))
    #expect(setHeat.extendedWhen == "extendedCommandsOnly")
    #expect(DeviceStandardCommand.protectedUserData(for: Command(command1: 0x6D, command2: 0x88)).bytes.prefix(3) == [0x6D, 0x88, 0x00])

  }

  @Test func refusesValuesThatDontFit() throws {

    let adapter = try commandSet("thermostatAdapter")
    let setHeat = try #require(adapter.standardCommand(named: "setHeatSetpoint"))
    let setMode = try #require(adapter.standardCommand(named: "setMode"))

    #expect(throws: FieldError.missingValue("mode")) { try setMode.command() }
    #expect(throws: FieldError.unknownName("turbo")) { try setMode.command(.named("turbo")) }
    #expect(throws: FieldError.mismatchedKind("heatSetpoint")) { try setHeat.command(.named("heat")) }
    #expect(throws: FieldError.outOfRange("heatSetpoint")) { try setHeat.command(.number(128)) }
    #expect(throws: FieldError.outOfRange("heatSetpoint")) { try setHeat.command(.number(-1)) }

  }

  @Test func readsAnAcknowledgementAndItsFollowUp() throws {

    let readSetpoints = try #require(try commandSet("thermostatAdapter").standardCommand(named: "readSetpoints"))

    #expect(readSetpoints.reply(in: message(.directAcknowledgement, 0x6A, 0x88)) == .number(68))
    #expect(readSetpoints.followUp(in: message(.direct, 0x6A, 0x9C)) == .number(78))
    #expect(readSetpoints.reply(in: message(.direct, 0x6A, 0x88)) == nil)
    #expect(readSetpoints.reply(in: message(.directAcknowledgement, 0x6B, 0x88)) == nil)

  }

  // The two families report the same mode byte with different meanings.
  @Test func readsReportsByEachFamilysTable() throws {

    let adapter = try commandSet("thermostatAdapter")
    let tempLinc = try commandSet("tempLinc")
    let modeReport = message(.direct, 0x70, 0x03)

    #expect(adapter.directMessage(in: modeReport)?.value == .named("auto"))
    #expect(tempLinc.directMessage(in: modeReport)?.value == .named("programAuto"))
    #expect(tempLinc.directMessage(in: message(.direct, 0x70, 0x08))?.value == .named("fanAuto"))
    #expect(tempLinc.directMessage(in: message(.direct, 0x70, 0x06))?.value == .unnamed(6))
    #expect(tempLinc.directMessage(in: message(.direct, 0x6E, 0x8D))?.message.name == "temperatureReport")
    #expect(tempLinc.directMessage(in: message(.direct, 0x6E, 0x8D))?.value == .number(70.5))
    #expect(tempLinc.directMessage(in: message(.directAcknowledgement, 0x6E, 0x8D)) == nil)
    #expect(tempLinc.celsiusIndicator == "displayCelsius")

  }

  // Insteon for Hub sends the status request with 0x92 0x96 in D13 and D14.
  @Test func sealsAnExtendedCommandWithItsCRC() throws {

    let readStatus = try #require(try commandSet("tempLinc").extendedCommand(named: "readStatus"))
    let request = try readStatus.message(to: thermostat)

    #expect(request.command == Command(command1: 0x2E, command2: 0x02))
    #expect(request.userData.bytes == Array(repeating: 0x00, count: 12) + [0x92, 0x96])

  }

  @Test func readsAnExtendedReplysMaskedAndMultibyteValues() throws {

    let reply = try #require(try commandSet("tempLinc").extendedCommand(named: "readStatus")?.reply)
    var userData = try UserData([0x01, 0x03, 0x0E, 0x1E, 0x00, 0x21, 0x4E, 0x2D, 0x00, 0xD7, 0x09, 0x44])
    userData = CRCIntegrity().seal(userData, for: Command(command1: 0x2E, command2: 0x02))

    let values = try #require(reply.values(in: message(.direct, 0x2E, 0x02, userData: userData)))

    #expect(values["systemMode"] == .named("heat"))
    #expect(values["fanMode"] == .named("on"))
    #expect(values["temperature"] == .number(21.5))
    #expect(values["coolSetpoint"] == .number(78))
    #expect(values["humidity"] == .number(45))
    #expect(values["status"] == .flags(["cooling", "displayCelsius"]))

    var corrupted = userData
    corrupted[14] ^= 0xFF

    #expect(reply.values(in: message(.direct, 0x2E, 0x02, userData: corrupted)) == nil)

  }

  @Test func writesASignedValueAndFlagsIntoUserData() throws {

    let tempLinc = try commandSet("tempLinc")
    let setOffset = try #require(tempLinc.extendedCommand(named: "setTemperatureOffset"))
    let setFlags = try #require(tempLinc.extendedCommand(named: "setFlags"))

    // -1.5 degrees is -15 tenths, 0xF1, and the checksum makes the bytes sum to zero.
    let request = try setOffset.message(to: thermostat, values: ["temperatureOffset": .number(-1.5)])

    #expect(request.userData.bytes.prefix(3) == [0x01, 0x02, 0xF1])
    #expect(request.userData[14] == 0xDE)
    #expect(try setFlags.userData(values: ["flags": .flags(["beep", "displayCelsius"])])[4] == 0x0A)
    #expect(throws: FieldError.outOfRange("temperatureOffset")) { try setOffset.userData(values: ["temperatureOffset": .number(6)]) }
    #expect(throws: FieldError.missingValue("temperatureOffset")) { try setOffset.userData() }

  }

  @Test func readsASignedValue() throws {

    let reply = try #require(try commandSet("tempLinc").extendedCommand(named: "readSettings")?.reply)
    var userData = UserData()
    userData[2] = 0x01
    userData[6] = 0xF1

    #expect(reply.values(in: message(.direct, 0x2E, 0x00, userData: userData))?["temperatureOffset"] == .number(-1.5))

  }

  @Test func sharesAByteBetweenMaskedFields() throws {

    let mode = MessageField(name: "mode", summary: "Mode.", location: .userData([6]), mask: 0xF0)
    let fan = MessageField(name: "fan", summary: "Fan.", location: .userData([6]), mask: 0x0F, kind: .boolean)

    let withMode = try mode.encoded(.number(3), over: [0x01])

    #expect(withMode == [0x31])
    #expect(try fan.encoded(.boolean(false), over: withMode) == [0x30])
    #expect(throws: FieldError.outOfRange("mode")) { try mode.encoded(.number(16), over: [0x00]) }

  }

  @Test func readsTheAdaptersProtectionFlag() throws {

    let adapter = try commandSet("thermostatAdapter")

    #expect(adapter.operatingFlag(named: "humidityReportsOn")?.extendedWhen == "extendedCommandsOnly")
    #expect(adapter.flagCommands.first?.extendedWhen == "extendedCommandsOnly")

  }

  @Test func refusesAFieldWithAnEnumerationItDoesntHave() {

    let json = #"""
      { "schemaVersion": 1, "devices": [], "commandSets": [{
        "id": "a", "name": "A", "description": "A.", "sources": ["A"],
        "directMessages": [{ "name": "modeReport", "description": "Mode.", "command1": "0x70",
          "value": { "name": "mode", "description": "Mode.", "kind": "enumeration", "enumeration": "missing" } }]
      }] }
      """#

    #expect(throws: DecodingError.self) {

      try DeviceCatalog(json: Data(json.utf8))

    }

  }

}
