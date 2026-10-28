import Testing
import InsteonProtocol

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
      command: Command(command1: 0x11),
      messageType: .allLinkBroadcast,
      maxHops: .one
    )

    // An ALL-Link broadcast to group 1: the group in the destination, cmd2 0x00.
    #expect(message.flags.rawValue == 0xC5)
    #expect(message.bytes == [0x00, 0x00, 0x01, 0xC5, 0x11, 0x00])

  }

  @Test func acceptsRawCommands() {

    let message = StandardMessage(to: address, command: Command(command1: 0x45, command2: 0x01))

    #expect(message.hexString == "AABBCC0F4501")

  }

  @Test func encodesExtendedMessageWithChecksumByDefault() throws {

    let message = ExtendedMessage(
      to: address,
      command: ExtendedDirectCommand.getSet(),
      userData: try UserData([0x01])
    )

    #expect(message.flags == .extendedDirect)
    #expect(message.bytes.count == 20)
    #expect(message.hexString == "AABBCC1F2E00" + "01" + String(repeating: "00", count: 12) + "D1")

  }

  // A captured message: enter linking mode for group 8,
  // sent extended with its checksum.
  @Test func checksumMatchesInsteonTrace() {

    let message = ExtendedMessage(
      to: InsteonAddress(0x10, 0xA3, 0x0F),
      command: StandardDirectCommand.enterLinkingMode(group: 0x08)
    )

    #expect(message.hexString == "10A30F1F0908" + String(repeating: "00", count: 13) + "EF")

  }

  @Test func extendedMessageFlagsFollowTheRequestedTypeAndHops() {

    let message = ExtendedMessage(
      to: address,
      command: ExtendedDirectCommand.getSet(),
      messageType: .broadcast,
      maxHops: .one
    )

    // 100 broadcast, extended, one hop left, one max hop.
    #expect(message.flags.rawValue == 0x95)

  }

  @Test func extendedMessageUsesRequestedIntegrity() throws {

    let message = ExtendedMessage(
      to: address,
      command: ExtendedDirectCommand.getSet(),
      userData: try UserData([0x01]),
      integrity: CRCIntegrity()
    )

    #expect(message.userData[13] == 0x9A)
    #expect(message.userData[14] == 0x88)

  }

}
