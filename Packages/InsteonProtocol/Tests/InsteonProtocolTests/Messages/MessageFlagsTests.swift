import Testing
import InsteonProtocol

struct MessageFlagsTests {

  static let messageTypeBits: [(MessageFlags.MessageType, UInt8)] = [
    (.direct, 0x00),
    (.directAcknowledgment, 0x20),
    (.allLinkCleanup, 0x40),
    (.allLinkCleanupAcknowledgment, 0x60),
    (.broadcast, 0x80),
    (.directNegativeAcknowledgment, 0xA0),
    (.allLinkBroadcast, 0xC0),
    (.allLinkCleanupNegativeAcknowledgment, 0xE0)
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

  @Test func findsHopsLeftThatExceedMaxHops() {

    #expect(MessageFlags(rawValue: 0x0F).hasConsistentHops)
    #expect(MessageFlags(rawValue: 0x0B).hasConsistentHops)
    #expect(!MessageFlags(rawValue: 0x0D).hasConsistentHops)

  }

  @Test func hopsLeftDefaultsToMaxHops() {

    #expect(MessageFlags(messageType: .direct, maxHops: .two).hopsLeft == .two)
    #expect(MessageFlags(messageType: .direct, maxHops: .one, hopsLeft: .three).hopsLeft == .one)

  }

  @Test(arguments: UInt8.min...UInt8.max)
  func decodingRoundTripsEveryByte(_ byte: UInt8) {

    #expect(MessageFlags(rawValue: byte).rawValue == byte)

  }

  @Test func decodesFields() {

    let flags = MessageFlags(rawValue: 0x2B)

    #expect(flags.messageType == .directAcknowledgment)
    #expect(flags.isExtended == false)
    #expect(flags.hopsLeft == .two)
    #expect(flags.maxHops == .three)

  }

}
