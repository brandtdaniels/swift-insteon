import Testing
import InsteonProtocol

struct AllLinkingTests {

  @Test func recordFlagsUseDocumentedBits() {

    #expect(AllLinkRecordFlags.inUse.rawValue == 0x80)
    #expect(AllLinkRecordFlags.controller.rawValue == 0x40)
    #expect(AllLinkRecordFlags.usedBefore.rawValue == 0x02)

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
