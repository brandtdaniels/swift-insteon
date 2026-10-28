import Testing
import InsteonProtocol

struct ThermostatTests {

  let thermostat = InsteonAddress(0x14, 0x25, 0x99)

  let modem = InsteonAddress(0x19, 0xC5, 0x98)

  @Test func encodesTheCommandTable() throws {

    let eighty = try #require(ThermostatTemperature(degrees: 80))

    #expect(ThermostatCommand.raiseSetpoint(halfDegrees: 2).command == Command(command1: 0x68, command2: 0x02))
    #expect(ThermostatCommand.lowerSetpoint(halfDegrees: 2).command == Command(command1: 0x69, command2: 0x02))
    #expect(ThermostatCommand.readTemperature.command == Command(command1: 0x6A, command2: 0x00))
    #expect(ThermostatCommand.readSetpoints.command == Command(command1: 0x6A, command2: 0x20))
    #expect(ThermostatCommand.readHumidity.command == Command(command1: 0x6A, command2: 0x60))
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
    #expect(report(0x70, 0x03) == .mode(.auto))
    #expect(report(0x70, 0x08) == nil)
    #expect(report(0x71, 0x30) == .coolSetpoint(ThermostatTemperature(rawValue: 0x30)))
    #expect(report(0x72, 0x24) == .heatSetpoint(ThermostatTemperature(rawValue: 0x24)))
    #expect(report(0x6E, 0x8C, flags: MessageFlags(messageType: .directAcknowledgement)) == nil)
    #expect(report(0x11, 0xFF) == nil)

  }

  @Test func namesTheDisplayFlags() {

    #expect(StandardDirectCommand.setOperatingFlags(flag: ThermostatDisplayOption.celsius.rawValue).command
      == Command(command1: 0x20, command2: 0x06))

  }

}
