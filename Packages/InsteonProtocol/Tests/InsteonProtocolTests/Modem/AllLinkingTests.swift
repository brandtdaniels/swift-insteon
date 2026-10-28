import Testing
import InsteonProtocol

struct AllLinkingTests {

  @Test func recordFlagsUseDocumentedBits() {

    #expect(AllLinkRecordFlags.inUse.rawValue == 0x80)
    #expect(AllLinkRecordFlags.controller.rawValue == 0x40)
    #expect(AllLinkRecordFlags.usedBefore.rawValue == 0x02)

  }

  // Smart hops set on a controller record.
  @Test func readsSmartHops() {

    #expect(AllLinkRecordFlags(rawValue: 0xE2).smartHops == 0)
    #expect(AllLinkRecordFlags(rawValue: 0xEA).smartHops == 1)
    #expect(AllLinkRecordFlags(rawValue: 0xF2).smartHops == 2)
    #expect(AllLinkRecordFlags(rawValue: 0xFA).smartHops == 3)

  }

  @Test func groupNumberForEveryGroupIsFF() {

    #expect(AllLinkGroupNumber.all.rawValue == 0xFF)
    #expect(AllLinkGroupNumber.all.description == "255")

  }

  @Test func encodesRecord() {

    let record = AllLinkRecord(flags: [.inUse], group: 0xFF, address: InsteonAddress(0x01, 0x02, 0x03))

    #expect(record.bytes == [0x80, 0xFF, 0x01, 0x02, 0x03, 0x00, 0x00, 0x00])

  }

  @Test(arguments: [
    (AllLinkMode.responder, UInt8(0x00)),
    (.controller, 0x01),
    (.controllerOrResponder, 0x03),
    (.delete, 0xFF)
  ] as [(AllLinkMode, UInt8)])
  func linkModeValues(_ mode: AllLinkMode, _ expected: UInt8) {

    #expect(mode.rawValue == expected)

  }

  @Test(arguments: [
    (AllLinkRecordAction.findFirst, UInt8(0x00)),
    (.findNext, 0x01),
    (.modifyFirstOrAdd, 0x20),
    (.modifyFirstControllerOrAdd, 0x40),
    (.modifyFirstResponderOrAdd, 0x41),
    (.deleteFirst, 0x80)
  ] as [(AllLinkRecordAction, UInt8)])
  func recordActionValues(_ action: AllLinkRecordAction, _ expected: UInt8) {

    #expect(action.rawValue == expected)

  }

}
