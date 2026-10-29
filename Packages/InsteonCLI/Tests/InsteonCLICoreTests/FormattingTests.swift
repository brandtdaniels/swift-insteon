import Testing
import InsteonCLICore

struct FormattingTests {

  @Test func writesBytesAndAddressesInHexadecimal() {

    #expect(Hex.byte(0x0F) == "0x0F")
    #expect(Hex.byte(0xAB) == "0xAB")
    #expect(Hex.address(0x0FFF) == "0x0FFF")
    #expect(Hex.address(0x0007) == "0x0007")

  }

}
