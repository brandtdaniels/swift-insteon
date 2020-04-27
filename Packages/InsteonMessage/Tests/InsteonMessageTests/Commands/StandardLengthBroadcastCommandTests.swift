import XCTest
@testable import InsteonMessage

final class StandardLengthBroadcastCommandTests: XCTestCase {

  func testSetButtonPressedResponderCommand() {

    let setButtonPressedResponder = StandardLengthBroadcastCommand.setButtonPressedResponder

    XCTAssertEqual(
      setButtonPressedResponder.command,
      Command(command1: 0x01, command2: 0x00)
    )

  }

  func testSetButtonPressedControllerCommand() {

    let setButtonPressedController = StandardLengthBroadcastCommand.setButtonPressedController

    XCTAssertEqual(
      setButtonPressedController.command,
      Command(command1: 0x02, command2: 0x00)
    )

  }

  func testTestPowerlinePhaseCommand() {

    let testPowerLinePhase = StandardLengthBroadcastCommand.testPowerlinePhase

    XCTAssertEqual(
      testPowerLinePhase.command,
      Command(command1: 0x03, command2: 0x00)
    )

  }

  func testHeartbeatCommand() {

    let heartbeat = StandardLengthBroadcastCommand.heartbeat(
      batteryLevel: 0xFF
    )

    XCTAssertEqual(
      heartbeat.command,
      Command(command1: 0x04, command2: 0xFF)
    )

  }

  func testDeviceStatusChangedCommand() {

    let deviceStatusChanged = StandardLengthBroadcastCommand.deviceStatusChanged

    XCTAssertEqual(
      deviceStatusChanged.command,
      Command(command1: 0x27, command2: 0x00)
    )

  }

  static var allTests = [
    ("testSetButtonPressedResponderCommand", testSetButtonPressedResponderCommand),
    ("testSetButtonPressedControllerCommand", testSetButtonPressedControllerCommand),
    ("testTestPowerlinePhaseCommand", testTestPowerlinePhaseCommand),
    ("testHeartbeatCommand", testHeartbeatCommand),
    ("testDeviceStatusChangedCommand", testDeviceStatusChangedCommand)
  ]

}
