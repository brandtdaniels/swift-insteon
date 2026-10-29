import Testing
import InsteonProtocol

struct ModemFrameTests {

  let standard = ReceivedMessage(
    sender: InsteonAddress(0x1A, 0x2B, 0x3C),
    destination: InsteonAddress(0x02, 0x7A, 0x41),
    flags: MessageFlags(rawValue: 0x8F),
    command: Command(command1: 0x01, command2: 0x00)
  )

  @Test func framesAStandardMessage() {

    let expected: [UInt8] = [0x02, 0x50, 0x1A, 0x2B, 0x3C, 0x02, 0x7A, 0x41, 0x8F, 0x01, 0x00]

    #expect(standard.modemFrame == expected)

  }

  @Test func framesAnExtendedMessageWithItsUserData() throws {

    var extended = standard
    extended.flags = MessageFlags(rawValue: 0x1F)
    extended.userData = try UserData([UInt8](repeating: 0x00, count: 13) + [0xD2])

    let frame: [UInt8] = extended.modemFrame

    #expect(frame.count == 25)
    #expect(Array(frame.prefix(2)) == [0x02, 0x51])
    #expect(frame.last == 0xD2)

  }

  @Test func parsesBackToTheSameMessage() throws {

    var extended = standard
    extended.flags = MessageFlags(rawValue: 0x1F)
    extended.userData = try UserData([UInt8](repeating: 0x11, count: 14))

    for message in [standard, extended] {

      var parser = ModemReplyParser()

      #expect(parser.parse(message.modemFrame) == [.messageReceived(message)])

    }

  }

}
