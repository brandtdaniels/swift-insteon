import XCTest
@testable import InsteonMessage

final class StandardLengthDirectCommandTests: XCTestCase {

  func testAssignCommand() {

    let assign = StandardLengthDirectCommand.assign(
      toAllLinkGroup: 0xFF
    )

    XCTAssertEqual(
      assign.command,
      Command(command1: 0x01, command2: 0xFF)
    )

  }

  func testDeleteCommand() {

    let delete = StandardLengthDirectCommand.delete(
      fromAllLinkGroup: 0xFF
    )

    XCTAssertEqual(
      delete.command,
      Command(command1: 0x02, command2: 0xFF)
    )

  }

  func testCancelLinkingModeCommand() {

    let cancelLinkingMode = StandardLengthDirectCommand.cancelLinkingMode

    XCTAssertEqual(
      cancelLinkingMode.command,
      Command(command1: 0x08, command2: 0x00)
    )

  }

  func testEnterLinkingModeCommand() {

    let enterLinkingMode = StandardLengthDirectCommand.enterLinkingMode(
      forGroup: 0xFF
    )

    XCTAssertEqual(
      enterLinkingMode.command,
      Command(command1: 0x09, command2: 0xFF)
    )

  }

  func testEnterUnlinkingModeCommand() {

    let enterUnlinkingMode = StandardLengthDirectCommand.enterUnlinkingMode(
      forGroup: 0xFF
    )

    XCTAssertEqual(
      enterUnlinkingMode.command,
      Command(command1: 0x0A, command2: 0xFF)
    )

  }

  func testGetInsteonEngineVersionCommand() {

    let getEngineVersion = StandardLengthDirectCommand.getInsteonEngineVersion

    XCTAssertEqual(
      getEngineVersion.command,
      Command(command1: 0x0D, command2: 0x00)
    )

  }

  static var allTests = [
    ("testAssignCommand", testAssignCommand),
    ("testDeleteCommand", testDeleteCommand),
    ("testCancelLinkingModeCommand", testCancelLinkingModeCommand),
    ("testEnterLinkingModeCommand", testEnterLinkingModeCommand),
    ("testEnterUnlinkingModeCommand", testEnterUnlinkingModeCommand),
    ("testGetInsteonEngineVersionCommand", testGetInsteonEngineVersionCommand)
  ]

}
