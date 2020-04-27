import XCTest
@testable import InsteonMessage

final class FormatterTests: XCTestCase {

  let insteonId = InsteonIdentifier(0xAA, 0xBB, 0xCC)

  let command = Command(command1: 0x01)

  func testStandardLengthMessageFormat() {

    let message = StandardLengthMessage(
      to: insteonId,
      command: command
    )

    XCTAssertEqual(
      Formatter.format(message),
      "AABBCC0F0100"
    )

  }

  func testExtendedLengthMessageFormat() {

    let message = ExtendedLengthMessage(
      to: insteonId,
      command: command
    )

    XCTAssertEqual(
      Formatter.format(message),
      "AABBCC1F01000000000000000000000000000000"
    )

  }

  func testDeviceAddressFormat() {

    XCTAssertEqual(
      Formatter.format(insteonId),
      "AABBCC"
    )

    XCTAssertEqual(
      Formatter.prettyFormat(insteonId),
      "AA.BB.CC"
    )

  }

  static var allTests = [
    ("testStandardLengthMessageFormat", testStandardLengthMessageFormat),
    ("testExtendedLengthMessageFormat", testExtendedLengthMessageFormat),
    ("testDeviceAddressFormat", testDeviceAddressFormat)
  ]

}
