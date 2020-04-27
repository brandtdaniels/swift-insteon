import XCTest
@testable import InsteonMessage

final class CommandTests: XCTestCase {

  var command: Command!

  override func setUp() {

    super.setUp()

    command = Command(
      command1: 0x01,
      command2: 0x02
    )

  }

  func testCommand1() {

    XCTAssertEqual(
      command.command1,
      0x01
    )

  }

  func testCommand2() {

    XCTAssertEqual(
      command.command2,
      0x02
    )

  }

  static var allTests = [
    ("testCommand1", testCommand1),
    ("testCommand2", testCommand2)
  ]

}
