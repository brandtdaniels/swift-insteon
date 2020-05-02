import XCTest
@testable import InsteonMessage

final class StandardLengthMessageTests: XCTestCase {
  
  var message: StandardLengthMessage!
  
  var expectedAddress = InsteonIdentifier(0xAA, 0xBB, 0xCC)
  
  var expectedCommand = Command(command1: 0x01, command2: 0x02)
  
  override func setUp() {
    
    super.setUp()
    
    message = StandardLengthMessage(
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
  
  func testStandardMessageFlags() {
    
    XCTAssertEqual(
      message.flags,
      MessageFlags.standardMessageFlags
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
  
  func testRawValue() {
    
    XCTAssertEqual(
      message.rawValue,
      "AABBCC0F0102"
    )
    
  }
  
  static var allTests = [
    ("testToAddress", testToAddress),
    ("testStandardMessageFlags", testStandardMessageFlags),
    ("testCommand", testCommand),
    ("testRawValue", testRawValue)
  ]
  
}
