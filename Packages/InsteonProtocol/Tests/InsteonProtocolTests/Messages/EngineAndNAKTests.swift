import Testing
import InsteonProtocol

struct EngineAndNAKTests {

  @Test func readsTheEngineFromItsVersionByte() {

    #expect(InsteonEngine(rawValue: 0x00) == .i1)
    #expect(InsteonEngine(rawValue: 0x01) == .i2)
    #expect(InsteonEngine(rawValue: 0x02) == .i2cs)
    #expect(InsteonEngine(rawValue: 0x03) == nil)

  }

  @Test func laterEnginesSortAfterEarlierOnes() {

    #expect(InsteonEngine.allCases.sorted() == [.i1, .i2, .i2cs])

  }

  static let minimumEngines: [(StandardDirectCommand, InsteonEngine?)] = [
    (.on(level: 0xFF), .i1),
    (.enterLinkingMode(group: 0x01), .i1),
    (.statusRequest(variant: 0x00), .i1),
    (.statusRequest(variant: 0x02), .i2),
    (.exitLinkingMode, .i2),
    (.getOperatingFlags(.operatingFlags), .i2),
    (.beep, nil),
    (.onAtRampRate(onLevel: 0xF, rampRate: 0xF), nil),
  ]

  @Test(arguments: minimumEngines)
  func commandsKnowTheirMinimumEngine(_ command: StandardDirectCommand, _ engine: InsteonEngine?) {

    #expect(command.minimumEngine == engine)

  }

  @Test func extendedCommandsNeedTheI2Engine() {

    #expect(ExtendedDirectCommand.getSet.minimumEngine == .i2)
    #expect(Command(command1: 0x30).minimumEngine == nil)

  }

  @Test func namesTheNAKCodes() {

    #expect(NAKReason(rawValue: 0xFF) == .notLinked)
    #expect(NAKReason.invalidCommand.rawValue == 0xFD)
    #expect(NAKReason.databaseFull.rawValue == 0xF9)

  }

}
