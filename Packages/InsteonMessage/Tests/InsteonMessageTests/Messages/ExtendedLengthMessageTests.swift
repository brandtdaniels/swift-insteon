import XCTest
@testable import InsteonMessage

final class ExtendedLengthMessageTests: XCTestCase {

  var message: ExtendedLengthMessage!

  var expectedAddress = InsteonIdentifier(0xAA, 0xBB, 0xCC)

  var expectedCommand = Command(command1: 0x01, command2: 0x02)

  override func setUp() {

    super.setUp()

    message = ExtendedLengthMessage(
      to: expectedAddress,
      command: expectedCommand
    )

  }

  func testToAddress() {

    XCTAssertEqual(
      message.toAddress.highByte,
      expectedAddress.highByte
    )

    XCTAssertEqual(
      message.toAddress.middleByte,
      expectedAddress.middleByte
    )

    XCTAssertEqual(
      message.toAddress.lowByte,
      expectedAddress.lowByte
    )

  }

  func testExtendedMessageFlags() {

    XCTAssertEqual(
      message.flags,
      MessageFlags.extendedMessageFlags
    )

  }

  func testCommand() {

    XCTAssertEqual(
      message.command.command1,
      expectedCommand.command1
    )

    XCTAssertEqual(
      message.command.command2,
      expectedCommand.command2
    )

  }

  func testUserData() {

    XCTAssertEqual(
      message.userData.data1,
      0x00
    )

    XCTAssertEqual(
      message.userData.data2,
      0x00
    )

    XCTAssertEqual(
      message.userData.data3,
      0x00
    )

    XCTAssertEqual(
      message.userData.data4,
      0x00
    )

    XCTAssertEqual(
      message.userData.data5,
      0x00
    )

    XCTAssertEqual(
      message.userData.data6,
      0x00
    )

    XCTAssertEqual(
      message.userData.data7,
      0x00
    )

    XCTAssertEqual(
      message.userData.data8,
      0x00
    )

    XCTAssertEqual(
      message.userData.data9,
      0x00
    )

    XCTAssertEqual(
      message.userData.data10,
      0x00
    )

    XCTAssertEqual(
      message.userData.data11,
      0x00
    )

    XCTAssertEqual(
      message.userData.data12,
      0x00
    )

    XCTAssertEqual(
      message.userData.data13,
      0x00
    )

    XCTAssertEqual(
      message.userData.data14,
      0x00
    )

  }

  static var allTests = [
    ("testToAddress", testToAddress),
    ("testExtendedMessageFlags", testExtendedMessageFlags),
    ("testCommand", testCommand),
    ("testUserData", testUserData)
  ]

}
