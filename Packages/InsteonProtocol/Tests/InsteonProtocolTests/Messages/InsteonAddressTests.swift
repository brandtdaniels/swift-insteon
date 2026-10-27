import Testing
import InsteonProtocol

struct InsteonAddressTests {

  @Test func encodesBytesMostSignificantFirst() {

    let address = InsteonAddress(0x1A, 0x2B, 0x3C)

    #expect(address.bytes == [0x1A, 0x2B, 0x3C])
    #expect(address.hexString == "1A2B3C")

  }

  @Test func describesAsPeriodSeparatedHex() {

    #expect(InsteonAddress(0x0A, 0x0B, 0xFF).description == "0A.0B.FF")

  }

  @Test(arguments: ["1A.2B.3C", "1a.2b.3c", "1A2B3C", "1a2B3c"])
  func parsesValidText(_ text: String) {

    #expect(InsteonAddress(text) == InsteonAddress(0x1A, 0x2B, 0x3C))

  }

  @Test(arguments: ["", "1A.2B", "1A.2B.3C.4D", "1A2B3", "1A2B3C4D", "GG.00.00", "1A.2B.3", "+1.2B.3C", "1A..2B3C", "1A.2B.3C."])
  func rejectsInvalidText(_ text: String) {

    #expect(InsteonAddress(text) == nil)

  }

  @Test func roundTripsThroughDescription() {

    let address = InsteonAddress(0x00, 0x7F, 0xFF)

    #expect(InsteonAddress(address.description) == address)

  }

}
