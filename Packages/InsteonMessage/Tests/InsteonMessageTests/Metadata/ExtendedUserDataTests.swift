import XCTest
@testable import InsteonMessage

final class ExtendedUserDataTests: XCTestCase {
  
  var userData: ExtendedUserData!
  
  override func setUp() {
    
    super.setUp()
    
    userData = ExtendedUserData()
    
  }
  
  func testData1() {
    
    XCTAssertEqual(
      userData.data1,
      0x00
    )
    
  }
  
  func testData2() {
    
    XCTAssertEqual(
      userData.data2,
      0x00
    )
    
  }
  
  func testData3() {
    
    XCTAssertEqual(
      userData.data3,
      0x00
    )
    
  }
  
  func testData4() {
    
    XCTAssertEqual(
      userData.data4,
      0x00
    )
    
  }
  
  func testData5() {
    
    XCTAssertEqual(
      userData.data5,
      0x00
    )
    
  }
  
  func testData6() {
    
    XCTAssertEqual(
      userData.data6,
      0x00
    )
    
  }
  
  func testData7() {
    
    XCTAssertEqual(
      userData.data7,
      0x00
    )
    
  }
  
  func testData8() {
    
    XCTAssertEqual(
      userData.data8,
      0x00
    )
    
  }
  
  func testData9() {
    
    XCTAssertEqual(
      userData.data9,
      0x00
    )
    
  }
  
  func testData10() {
    
    XCTAssertEqual(
      userData.data10,
      0x00
    )
    
  }
  
  func testData11() {
    
    XCTAssertEqual(
      userData.data11,
      0x00
    )
    
  }
  
  func testData12() {
    
    XCTAssertEqual(
      userData.data12,
      0x00
    )
    
  }
  
  func testData13() {
    
    XCTAssertEqual(
      userData.data13,
      0x00
    )
    
  }
  
  func testData14() {
    
    XCTAssertEqual(
      userData.data14,
      0x00
    )
    
  }
  
  func testRawValue() {
    
    XCTAssertEqual(
      userData.rawValue,
      "0000000000000000000000000000"
    )
    
  }
  
  static var allTests = [
    ("testData1", testData1),
    ("testData2", testData2),
    ("testData3", testData3),
    ("testData4", testData4),
    ("testData5", testData5),
    ("testData6", testData6),
    ("testData7", testData7),
    ("testData8", testData8),
    ("testData9", testData9),
    ("testData10", testData10),
    ("testData11", testData11),
    ("testData12", testData12),
    ("testData13", testData13),
    ("testData14", testData14),
    ("testRawValue", testRawValue)
  ]
  
}
