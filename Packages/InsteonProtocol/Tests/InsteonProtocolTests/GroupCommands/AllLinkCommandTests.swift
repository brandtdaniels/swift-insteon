import Testing
import InsteonProtocol

struct AllLinkCommandTests {

  let keypad = InsteonAddress(0x00, 0x5E, 0x5D)

  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)

  // The Developer's Guide's toggle and paired button table, and its lighting defaults.
  @Test func pairsEachHighStateCommandWithItsLowState() {

    #expect(AllLinkCommand.recall.partner == .alias1Low)
    #expect(AllLinkCommand.alias2High.partner == .alias2Low)
    #expect(AllLinkCommand.alias3Low.partner == .alias3High)
    #expect(AllLinkCommand.alias4Low.partner == .alias4High)
    #expect(AllLinkCommand.alias5.partner == nil)

    for command in AllLinkCommand.allCases {

      #expect(command.partner?.partner ?? command == command)
      #expect(command.partner.map { $0.buttonState != command.buttonState } ?? (command.buttonState == nil))

    }

  }

  @Test func givesALightingControlsBuiltInSubstitutes() {

    #expect(AllLinkCommand.recall.lightingSubstitute == nil)
    #expect(AllLinkCommand.allCases.compactMap(\.lightingSubstitute?.hexString)
      == ["1200", "1300", "1400", "1500", "1600", "1700", "1800", "2100"])

  }

  @Test func namesTheAllLinkCommandOfAGroupCommand() {

    let off = GroupCommand(controller: keypad, group: 0x01, command1: 0x13, command2: 0x00, source: .broadcast)
    let motion = GroupCommand(controller: keypad, group: 0x01, command1: 0x6E, command2: 0x00, source: .broadcast)

    #expect(off.allLinkCommand == .alias1Low)
    #expect(motion.allLinkCommand == nil)

  }

  @Test func encodesAStandardSubstitute() {

    let alias = AllLinkCommandAlias(.alias2High, substitute: StandardDirectCommand.fastOn(level: 0xFF))
    let message = alias.message(to: lamp)

    #expect(alias.userData.hexString == "1212FF0000000000000000000000")
    #expect(message.command == Command(command1: 0x03, command2: 0x04))
    #expect(message.userData[14] == 0xD6)
    #expect(AllLinkCommandAlias.ignoring(.alias4High).userData.hexString == "1700000000000000000000000000")

  }

}
