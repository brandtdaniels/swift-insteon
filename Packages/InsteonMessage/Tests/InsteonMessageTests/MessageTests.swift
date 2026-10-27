import Testing
import InsteonMessage

struct MessageTests {

  let address = InsteonAddress(0xAA, 0xBB, 0xCC)

  @Test func encodesStandardDirectMessage() {

    let message = StandardMessage(to: address, command: StandardDirectCommand.on(level: 0x80))

    #expect(message.flags == .direct)
    #expect(message.hexString == "AABBCC0F1180")

  }

  @Test func encodesStandardMessageWithCustomTypeAndHops() {

    let message = StandardMessage(
      to: InsteonAddress(0x00, 0x00, 0x01),
      command: StandardDirectCommand.on(level: 0xFF),
      messageType: .allLinkBroadcast,
      maxHops: .one
    )

    #expect(message.flags.rawValue == 0xC5)
    #expect(message.bytes == [0x00, 0x00, 0x01, 0xC5, 0x11, 0xFF])

  }

  @Test func acceptsRawCommands() {

    let message = StandardMessage(to: address, command: Command(command1: 0x45, command2: 0x01))

    #expect(message.hexString == "AABBCC0F4501")

  }

  @Test func encodesExtendedMessageWithChecksumByDefault() throws {

    let message = ExtendedMessage(
      to: address,
      command: ExtendedDirectCommand.extendedGetSet,
      userData: try UserData([0x01])
    )

    #expect(message.flags == .extendedDirect)
    #expect(message.bytes.count == 20)
    #expect(message.hexString == "AABBCC1F2E00" + "01" + String(repeating: "00", count: 12) + "D1")

  }

  @Test func extendedMessageUsesRequestedIntegrity() throws {

    let message = ExtendedMessage(
      to: address,
      command: ExtendedDirectCommand.extendedGetSet,
      userData: try UserData([0x01]),
      integrity: CRCIntegrity()
    )

    #expect(message.userData[13] == 0x9A)
    #expect(message.userData[14] == 0x88)

  }

}
