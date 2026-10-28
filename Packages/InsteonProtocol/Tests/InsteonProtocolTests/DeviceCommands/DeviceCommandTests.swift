import Testing
import InsteonProtocol

struct DeviceCommandTests {

  static let extendedDirectCommands: [(ExtendedDirectCommand, Command)] = [
    (.getSet(), Command(command1: 0x2E)),
    (.getSet(variant: 0x02), Command(command1: 0x2E, command2: 0x02)),
    (.readWriteAllLinkDatabase, Command(command1: 0x2F)),
    (.triggerAllLinkGroup, Command(command1: 0x30))
  ]

  static let standardDirectCommands: [(StandardDirectCommand, Command)] = [
    (.productDataRequest, Command(command1: 0x03, command2: 0x00)),
    (.exitLinkingMode, Command(command1: 0x08)),
    (.assignToAllLinkGroup(group: 0x01), Command(command1: 0x01, command2: 0x01)),
    (.deleteFromAllLinkGroup(group: 0x02), Command(command1: 0x02, command2: 0x02)),
    (.enterLinkingMode(group: 0x01), Command(command1: 0x09, command2: 0x01)),
    (.enterUnlinkingMode(group: 0x02), Command(command1: 0x0A, command2: 0x02)),
    (.getEngineVersion, Command(command1: 0x0D)),
    (.ping, Command(command1: 0x0F)),
    (.idRequest, Command(command1: 0x10)),
    (.on(level: 0xFF), Command(command1: 0x11, command2: 0xFF)),
    (.fastOn(level: 0x80), Command(command1: 0x12, command2: 0x80)),
    (.off, Command(command1: 0x13)),
    (.fastOff, Command(command1: 0x14)),
    (.brightenOneStep, Command(command1: 0x15)),
    (.dimOneStep, Command(command1: 0x16)),
    (.startManualChange(direction: .down), Command(command1: 0x17, command2: 0x00)),
    (.startManualChange(direction: .up), Command(command1: 0x17, command2: 0x01)),
    (.stopManualChange, Command(command1: 0x18)),
    (.statusRequest(), Command(command1: 0x19, command2: 0x00)),
    (.statusRequest(variant: 0x01), Command(command1: 0x19, command2: 0x01)),
    (.getOperatingFlags(.operatingFlags), Command(command1: 0x1F, command2: 0x00)),
    (.getOperatingFlags(.allLinkDatabaseDelta), Command(command1: 0x1F, command2: 0x01)),
    (.getOperatingFlags(.signalToNoise), Command(command1: 0x1F, command2: 0x02)),
    (.getOperatingFlags(0x05), Command(command1: 0x1F, command2: 0x05)),
    (.setOperatingFlags(flag: 0x05), Command(command1: 0x20, command2: 0x05)),
    (.instantChange(level: 0x40), Command(command1: 0x21, command2: 0x40)),
    (.remoteSetButtonTap(.one), Command(command1: 0x25, command2: 0x01)),
    (.remoteSetButtonTap(.two), Command(command1: 0x25, command2: 0x02)),
    (.onAtRampRate(onLevel: 0x0A, rampRate: 0x03), Command(command1: 0x2E, command2: 0xA3)),
    (.offAtRampRate(rampRate: 0x07), Command(command1: 0x2F, command2: 0x07)),
    (.beep, Command(command1: 0x30))
  ]

  @Test(arguments: standardDirectCommands)
  func standardDirectCommandBytes(_ command: StandardDirectCommand, _ expected: Command) {

    #expect(command.command == expected)

  }

  @Test func rampRateCommandsIgnoreHighBits() {

    #expect(StandardDirectCommand.onAtRampRate(onLevel: 0xFA, rampRate: 0xF3).command.command2 == 0xA3)
    #expect(StandardDirectCommand.offAtRampRate(rampRate: 0xF7).command.command2 == 0x07)

  }

  @Test(arguments: extendedDirectCommands)
  func extendedDirectCommandBytes(_ command: ExtendedDirectCommand, _ expected: Command) {

    #expect(command.command == expected)

  }

  @Test func encodesCommandBytes() {

    let command = Command(command1: 0x11, command2: 0x80)

    #expect(command.bytes == [0x11, 0x80])
    #expect(command.hexString == "1180")

  }

}
