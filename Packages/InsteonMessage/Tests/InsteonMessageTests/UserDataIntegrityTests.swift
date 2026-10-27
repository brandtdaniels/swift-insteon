import Testing
import InsteonMessage

struct UserDataIntegrityTests {

  static let crcReferenceValues: [([UInt8], UInt8, UInt8)] = [
    ([0x01], 0x9A, 0x88),
    (Array(UInt8(1)...12), 0x04, 0x52)
  ]

  let extendedGet = Command(command1: 0x2E, command2: 0x00)

  @Test func checksumMatchesReferenceExample() throws {

    let sealed = ChecksumIntegrity().seal(try UserData([0x01]), for: extendedGet)

    #expect(sealed[14] == 0xD1)

  }

  @Test func checksumMakesAllBytesSumToZero() throws {

    let command = Command(command1: 0x2F, command2: 0x00)
    let sealed = ChecksumIntegrity().seal(try UserData(Array(UInt8(1)...13)), for: command)

    #expect(sealed[14] == 0x76)
    #expect((command.bytes + sealed.bytes).reduce(UInt8(0), &+) == 0)

  }

  @Test func checksumIgnoresExistingD14() throws {

    var userData = try UserData([0x01])
    userData[14] = 0x55

    #expect(ChecksumIntegrity().seal(userData, for: extendedGet)[14] == 0xD1)

  }

  // Reference values computed with pyinsteon's CRC implementation.
  @Test(arguments: crcReferenceValues)
  func crcMatchesReferenceImplementation(_ data: [UInt8], _ high: UInt8, _ low: UInt8) throws {

    let sealed = CRCIntegrity().seal(try UserData(data), for: extendedGet)

    #expect(sealed[13] == high)
    #expect(sealed[14] == low)

  }

  @Test func unprotectedLeavesDataUnchanged() throws {

    let userData = try UserData([0x01, 0x02])

    #expect(UnprotectedIntegrity().seal(userData, for: extendedGet) == userData)

  }

}
