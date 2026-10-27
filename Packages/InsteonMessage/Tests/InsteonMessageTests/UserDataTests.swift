import Testing
import InsteonMessage

struct UserDataTests {

  @Test func startsAsFourteenZeros() {

    #expect(UserData().bytes == Array(repeating: 0, count: 14))

  }

  @Test func padsShortInputWithZeros() throws {

    let userData = try UserData([0x01, 0x02])

    #expect(userData.bytes == [0x01, 0x02] + Array(repeating: 0, count: 12))

  }

  @Test func rejectsMoreThanFourteenBytes() {

    #expect(throws: UserDataError.tooManyBytes(15)) {

      try UserData(Array(repeating: 0, count: 15))

    }

  }

  @Test func subscriptIsOneBased() {

    var userData = UserData()
    userData[1] = 0xAA
    userData[14] = 0xBB

    #expect(userData.bytes.first == 0xAA)
    #expect(userData.bytes.last == 0xBB)
    #expect(userData[1] == 0xAA)

  }

}
