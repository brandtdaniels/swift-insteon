import Testing
import InsteonProtocol

struct ThermostatTests {

  let thermostat = InsteonAddress(0x14, 0x25, 0x99)

  let modem = InsteonAddress(0x19, 0xC5, 0x98)

  @Test func encodesTheCommandTable() throws {

    let eighty = try #require(ThermostatTemperature(degrees: 80))

    #expect(ThermostatCommand.raiseSetpoint(halfDegrees: 2).command == Command(command1: 0x68, command2: 0x02))
    #expect(ThermostatCommand.lowerSetpoint(halfDegrees: 2).command == Command(command1: 0x69, command2: 0x02))
    #expect(ThermostatCommand.readZone(.temperature).command == Command(command1: 0x6A, command2: 0x00))
    #expect(ThermostatCommand.readZone(.setpoint).command == Command(command1: 0x6A, command2: 0x20))
    #expect(ThermostatCommand.readZone(.humidity).command == Command(command1: 0x6A, command2: 0x60))
    #expect(ThermostatCommand.readMode.command == Command(command1: 0x6B, command2: 0x02))
    #expect(ThermostatCommand.setMode(.programAuto).command == Command(command1: 0x6B, command2: 0x0C))
    #expect(ThermostatCommand.setFan(.auto).command == Command(command1: 0x6B, command2: 0x08))
    #expect(ThermostatCommand.setCoolSetpoint(eighty).command == Command(command1: 0x6C, command2: 0xA0))
    // The sheet's example: set the heat setpoint to 80 degrees.
    #expect(ThermostatCommand.setHeatSetpoint(eighty).command == Command(command1: 0x6D, command2: 0xA0))

  }

  // The sheet's example of the same command when only extended commands are accepted.
  @Test func repeatsTheCommandInProtectedUserData() throws {

    let command = ThermostatCommand.setHeatSetpoint(try #require(ThermostatTemperature(degrees: 80)))

    #expect(command.protectedUserData.bytes == [0x6D, 0xA0] + [UInt8](repeating: 0x00, count: 12))

  }

  @Test func convertsHalfDegrees() {

    #expect(ThermostatTemperature(rawValue: 0x24).degrees == 18)
    #expect(ThermostatTemperature(degrees: 20.5)?.rawValue == 0x29)
    #expect(ThermostatTemperature(degrees: 20.25) == nil)
    #expect(ThermostatTemperature(degrees: -1) == nil)
    #expect(ThermostatTemperature(degrees: 128) == nil)

  }

  @Test func readsStatusReports() {

    func report(_ command1: UInt8, _ command2: UInt8, flags: MessageFlags = .direct) -> ThermostatStatusReport? {

      ThermostatStatusReport(ReceivedMessage(sender: thermostat, destination: modem, flags: flags, command: Command(command1: command1, command2: command2)))

    }

    #expect(report(0x6E, 0x8C) == .temperature(ThermostatTemperature(rawValue: 0x8C)))
    #expect(report(0x6F, 0x2D) == .humidity(percent: 45))
    #expect(report(0x70, 0x03) == .mode(ThermostatModeCode(rawValue: 0x03)))
    #expect(report(0x71, 0x30) == .coolSetpoint(ThermostatTemperature(rawValue: 0x30)))
    #expect(report(0x72, 0x24) == .heatSetpoint(ThermostatTemperature(rawValue: 0x24)))
    #expect(report(0x6E, 0x8C, flags: MessageFlags(messageType: .directAcknowledgement)) == nil)
    #expect(report(0x11, 0xFF) == nil)

  }

  @Test func namesTheDisplayFlags() {

    #expect(StandardDirectCommand.setOperatingFlags(flag: ThermostatOption.celsius.rawValue).command
      == Command(command1: 0x20, command2: 0x06))

  }

  // The datasheet: bits 0 to 4 are the zone, bits 5 and 6 the value.
  @Test func addressesAZone() throws {

    let zone3 = try #require(ThermostatZone(rawValue: 3))

    #expect(ThermostatCommand.readZone(.deadband, zone: zone3).command == Command(command1: 0x6A, command2: 0x43))
    #expect(ThermostatCommand.readZone(.humidity, zone: try #require(ThermostatZone(rawValue: 31))).command.command2 == 0x7F)
    #expect(ThermostatZone(rawValue: 32) == nil)

  }

  // The same mode report means auto to a Venstar adapter and cool to a TempLinc.
  @Test func readsAModeCodeByTheThermostatsModel() {

    let code = ThermostatModeCode(rawValue: 0x03)

    #expect(ThermostatMode(rawValue: code.rawValue) == .auto)
    #expect(TempLincMode(rawValue: code.rawValue) == .cool)
    #expect(TempLincMode(rawValue: 0x05) == nil)

  }

}
