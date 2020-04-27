import XCTest
@testable import InsteonMessage

final class ExtendedLengthDirectCommandTests: XCTestCase {

  func testExtendedSetGetCommand() {

    let extendedSetGet = ExtendedLengthDirectCommand.extendedSetGet

    XCTAssertEqual(
      extendedSetGet.command,
      Command(command1: 0x2E, command2: 0x00)
    )

  }

  func testReadWriteAllLinkDbCommand() {

    let readWriteAllLinkDb = ExtendedLengthDirectCommand.readWriteAllLinkDatabase

    XCTAssertEqual(
      readWriteAllLinkDb.command,
      Command(command1: 0x2F, command2: 0x00)
    )

  }

  static var allTests = [
    ("testExtendedSetGetCommand", testExtendedSetGetCommand),
    ("testReadWriteAllLinkDbCommand", testReadWriteAllLinkDbCommand)
  ]

}
