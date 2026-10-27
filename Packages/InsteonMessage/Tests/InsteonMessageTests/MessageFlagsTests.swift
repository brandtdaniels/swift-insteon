import Testing
import InsteonMessage

struct MessageFlagsTests {

  static let messageTypeBits: [(MessageFlags.MessageType, UInt8)] = [
    (.direct, 0x00),
    (.directAcknowledgement, 0x20),
    (.allLinkCleanup, 0x40),
    (.allLinkCleanupAcknowledgement, 0x60),
    (.broadcast, 0x80),
    (.directNegativeAcknowledgement, 0xA0),
    (.allLinkBroadcast, 0xC0),
    (.allLinkCleanupNegativeAcknowledgement, 0xE0)
  ]

  @Test func directFlagsAreThreeHopStandardDirect() {

    #expect(MessageFlags.direct.rawValue == 0x0F)

  }

  @Test func extendedDirectFlagsSetTheExtendedBit() {

    #expect(MessageFlags.extendedDirect.rawValue == 0x1F)

  }

  @Test(arguments: messageTypeBits)
  func encodesMessageTypeInTopThreeBits(_ type: MessageFlags.MessageType, _ expected: UInt8) {

    #expect(MessageFlags(messageType: type, maxHops: .zero).rawValue == expected)

  }

  @Test func encodesHopFields() {

    let flags = MessageFlags(messageType: .direct, maxHops: .three, hopsLeft: .one)

    #expect(flags.rawValue == 0b0000_0111)

  }

  @Test func hopsLeftDefaultsToMaxHops() {

    #expect(MessageFlags(messageType: .direct, maxHops: .two).hopsLeft == .two)

  }

  @Test(arguments: UInt8.min...UInt8.max)
  func decodingRoundTripsEveryByte(_ byte: UInt8) {

    #expect(MessageFlags(rawValue: byte).rawValue == byte)

  }

  @Test func decodesFields() {

    let flags = MessageFlags(rawValue: 0x2B)

    #expect(flags.messageType == .directAcknowledgement)
    #expect(flags.isExtended == false)
    #expect(flags.hopsLeft == .two)
    #expect(flags.maxHops == .three)

  }

}
