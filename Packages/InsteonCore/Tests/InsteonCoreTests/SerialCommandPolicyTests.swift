import Testing
import InsteonCore

/// Which serial commands a raw passthrough writes without being forced.
struct SerialCommandPolicyTests {

  @Test func recognizesSerialCommandsByTheirFirstByte() {

    #expect(SerialCommandPolicy.isSerialCommand([0x02, 0x77]))
    #expect(!SerialCommandPolicy.isSerialCommand([0x03, 0x60]))
    #expect(!SerialCommandPolicy.isSerialCommand([]))

  }

  @Test func refusesSerialCommandsThatChangeWhatTheModemKeeps() {

    #expect(SerialCommandPolicy.refusal(for: [0x02, 0x77]) == nil)
    #expect(SerialCommandPolicy.refusal(for: [0x02, 0x60]) == nil)
    #expect(SerialCommandPolicy.refusal(for: [0x02, 0x67]) != nil)
    #expect(SerialCommandPolicy.refusal(for: [0x02, 0x6F, 0x80]) != nil)
    #expect(SerialCommandPolicy.refusal(for: [0x02, 0x76]) != nil)
    #expect(SerialCommandPolicy.refusal(for: [0x02, 0x99]) != nil)
    #expect(SerialCommandPolicy.refusal(for: [0x02]) != nil)

  }

  @Test func namesAnUnknownCommandNumberInHexadecimal() {

    #expect(SerialCommandPolicy.refusal(for: [0x02, 0x09]) == "0x09 isn't a serial command the package knows, so the modem's answer can't be read.")

  }

}
