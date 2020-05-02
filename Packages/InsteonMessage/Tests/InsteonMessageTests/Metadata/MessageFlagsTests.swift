import XCTest
@testable import InsteonMessage

final class MessageFlagsTests: XCTestCase {

  func testStandardMessageFlags() {

    XCTAssertEqual(
      MessageFlags.standardMessageFlags.rawValue,
      0x0F
    )

  }

  func testExtendedMessageFlags() {

    XCTAssertEqual(
      MessageFlags.extendedMessageFlags.rawValue,
      0x1F
    )

  }

  func testMessageTypes() {

    XCTAssertEqual(
      MessageFlags.broadcastMessage.rawValue,
      0x80
    )

    XCTAssertEqual(
      MessageFlags.ackDirectMessage.rawValue,
      0x20
    )

    XCTAssertEqual(
      MessageFlags.nakDirectMessage.rawValue,
      0xA0
    )

    XCTAssertEqual(
      MessageFlags.allLinkBroadcastMessage.rawValue,
      0xC0
    )

    XCTAssertEqual(
      MessageFlags.allLinkCleanupMessage.rawValue,
      0x40
    )

    XCTAssertEqual(
      MessageFlags.ackAllLinkCleanupMessage.rawValue,
      0x60
    )

    XCTAssertEqual(
      MessageFlags.nakAllLinkCleanupMessage.rawValue,
      0xE0
    )

  }

  func testHopsLeft() {

    XCTAssertEqual(
      MessageFlags.oneRetransmissionRemaining.rawValue,
      0x04
    )

    XCTAssertEqual(
      MessageFlags.twoRetransmissionsRemaining.rawValue,
      0x08
    )

    XCTAssertEqual(
      MessageFlags.threeRetransmissionsRemaining.rawValue,
      0x0C
    )

  }

  func testMaxHops() {

    XCTAssertEqual(
      MessageFlags.oneRetransmissionMax.rawValue,
      0x01
    )

    XCTAssertEqual(
      MessageFlags.twoRetransmissionsMax.rawValue,
      0x02
    )

    XCTAssertEqual(
      MessageFlags.threeRetransmissionsMax.rawValue,
      0x03
    )
    
  }

  static var allTests = [
    ("testStandardMessageFlags", testStandardMessageFlags),
    ("testExtendedMessageFlags", testExtendedMessageFlags),
    ("testMessageTypes", testMessageTypes),
    ("testHopsLeft", testHopsLeft),
    ("testMaxHops", testMaxHops)
  ]

}
