import XCTest
@testable import InsteonMessage

final class InsteonIdentifierTests: XCTestCase {
  
  var insteonId: InsteonIdentifier!
  
  override func setUp() {
    
    super.setUp()
    
    insteonId = InsteonIdentifier(
      0xAA,
      0xBB,
      0xCC
    )
    
  }
  
  func testHighByte() {
    
    XCTAssertEqual(
      insteonId.highByte,
      0xAA
    )
    
  }
  
  func testMiddleByte() {
    
    XCTAssertEqual(
      insteonId.middleByte,
      0xBB
    )
    
  }
  
  func testLowByte() {
    
    XCTAssertEqual(
      insteonId.lowByte,
      0xCC
    )
    
  }
  
  func testRawValue() {
    
    XCTAssertEqual(
      insteonId.rawValue,
      "AABBCC"
    )
    
  }
  
  static var allTests = [
    ("testHighByte", testHighByte),
    ("testMiddleByte", testMiddleByte),
    ("testLowByte", testLowByte),
    ("testRawValue", testRawValue)
  ]
  
}
