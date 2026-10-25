import XCTest
import InsteonMessage
@testable import InsteonSerialCommand

final class SerialCommandTests: XCTestCase {
  
  func testGetInsteonModemInformation() {
    
    XCTAssertEqual(
      SerialCommand(
        .getInsteonModemInformation
      ).stringValue,
      "0260"
    )
    
  }
  
  func testSendAllLinkCommand() {
    
    XCTAssertEqual(
      SerialCommand(
        .sendAllLinkCommand(
          command: 0x01,
          group: 0x02,
          broadcastCommand2: 0x03
        )
      ).stringValue,
      "0261010203"
    )
    
  }
  
  func testSendInsteonStandardMessage() {
    
    let insteonId = InsteonIdentifier(0xAA, 0xBB, 0xCC)
    
    let command = StandardLengthDirectCommand.lightOnFull.command
    
    let standardMessage = StandardLengthMessage(
      to: insteonId,
      command: command
    )
    
    XCTAssertEqual(
      SerialCommand(
        .sendInsteonStandardMessage(
          message: standardMessage
        )
      ).stringValue,
      "0262AABBCC0F1100"
    )
    
  }
  
  func testSendInsteonExtendedMessage() {
    
    let insteonId = InsteonIdentifier(0xAA, 0xBB, 0xCC)
    
    let command = ExtendedLengthDirectCommand.extendedSetGet.command
    
    let extendedMessage = ExtendedLengthMessage(
      to: insteonId,
      command: command
    )
    
    XCTAssertEqual(
      SerialCommand(
        .sendInsteonExtendedMessage(
          message: extendedMessage
        )
      ).stringValue,
      "0262AABBCC1F2E000000000000000000000000000000"
    )
    
  }
  
  func testSendX10() {
    
    var rawX10 = X10HouseCode.a.rawValue | X10UnitCode.one.rawValue
    
    XCTAssertEqual(
      SerialCommand(
        .sendX10(
          rawX10: rawX10,
          x10Flag: .unitCode
        )
      ).stringValue,
      "02636600"
    )
    
    rawX10 = X10HouseCode.a.rawValue | X10Command.allLightsOff.rawValue
    
    XCTAssertEqual(
      SerialCommand(
        .sendX10(
          rawX10: rawX10,
          x10Flag: .command
        )
      ).stringValue,
      "02636680"
    )
    
  }
  
  func testStartAllLinking() {
    
    XCTAssertEqual(
      SerialCommand(
        .startAllLinking(
          linkCode: .modemAsControllerOrResponder,
          group: 0x01
        )
      ).stringValue,
      "02640301"
    )
    
  }
  
  func testCancellAllLinking() {
    
    XCTAssertEqual(
      SerialCommand(
        .cancelAllLinking
      ).stringValue,
      "0265"
    )
    
  }
  
  func testSetHostDeviceCategory() {
    
    XCTAssertEqual(
      SerialCommand(
        .setHostDeviceCategory(
          category: 0x01,
          subCategory: 0x01
        )
      ).stringValue,
      "02660101FF"
    )
    
  }
  
  func testResetInsteonModem() {
    
    XCTAssertEqual(
      SerialCommand(
        .resetInsteonModem
      ).stringValue,
      "0267"
    )
    
  }
  
  func testSetInsteonAckMessageByte() {
    
    XCTAssertEqual(
      SerialCommand(
        .setInsteonAckMessageByte(
          command2: 0x01
        )
      ).stringValue,
      "026801"
    )
    
  }
  
  func testGetFirstAllLinkRecord() {
    
    XCTAssertEqual(
      SerialCommand(
        .getFirstAllLinkRecord
      ).stringValue,
      "0269"
    )
    
  }
  
  func testGetNextAllLinkRecord() {
    
    XCTAssertEqual(
      SerialCommand(
        .getNextAllLinkRecord
      ).stringValue,
      "026A"
    )
    
  }
  
  func testSetInsteonModemConfiguration() {
    
    XCTAssertEqual(
      SerialCommand(
        .setInsteonModemConfiguration(
          configurationFlags: []
        )
      ).stringValue,
      "026B00"
    )
    
  }
  
  func testGetAllLinkRecordForSender() {
    
    XCTAssertEqual(
      SerialCommand(
        .getAllLinkRecordForSender
      ).stringValue,
      "026C"
    )
    
  }
  
  func testLedOn() {
    
    XCTAssertEqual(
      SerialCommand(
        .ledOn
      ).stringValue,
      "026D"
    )
    
  }
  
  func testLedOff() {
    
    XCTAssertEqual(
      SerialCommand(
        .ledOff
      ).stringValue,
      "026E"
    )
    
  }
  
  func testManageAllLinkRecord() {
    
    let insteonId = InsteonIdentifier(
      0xAA,
      0xBB,
      0xCC
    )
    
    XCTAssertEqual(
      SerialCommand(
        .manageAllLinkRecord(
          controlCode: .findNext,
          recordFlags: .isController,
          group: 0x01,
          insteonId: insteonId,
          linkData1: 0x01,
          linkData2: 0x01,
          linkData3: 0x01
        )
      ).stringValue,
      "026F014001AABBCC010101"
    )
    
  }
  
  func testSetInsteonNakMessageByte() {
    
    XCTAssertEqual(
      SerialCommand(
        .setInsteonNakMessageByte(
          command2: 0x01
        )
      ).stringValue,
      "027001"
    )
    
  }
  
  func testSetInsteonAckMessageBytes() {
    
    XCTAssertEqual(
      SerialCommand(
        .setInsteonAckMessageBytes(
          command1: 0x01,
          command2: 0x01
        )
      ).stringValue,
      "02710101"
    )
    
  }
  
  func testRfSleep() {
    
    XCTAssertEqual(
      SerialCommand(
        .rfSleep
      ).stringValue,
      "0272"
    )
    
  }
  
  func testGetInsteonModemConfiguration() {
    
    XCTAssertEqual(
      SerialCommand(
        .getInsteonModemConfiguration
      ).stringValue,
      "0273"
    )
    
  }
  
  static var allTests = [
    ("testGetInsteonModemInformation", testGetInsteonModemInformation),
    ("testSendAllLinkCommand", testSendAllLinkCommand),
    ("testSendInsteonStandardMessage", testSendInsteonStandardMessage),
    ("testSendInsteonExtendedMessage", testSendInsteonExtendedMessage),
    ("testSendX10", testSendX10),
    ("testStartAllLinking", testStartAllLinking),
    ("testCancellAllLinking", testCancellAllLinking),
    ("testSetHostDeviceCategory", testSetHostDeviceCategory),
    ("testResetInsteonModem", testResetInsteonModem),
    ("testSetInsteonAckMessageByte", testSetInsteonAckMessageByte),
    ("testGetFirstAllLinkRecord", testGetFirstAllLinkRecord),
    ("testGetNextAllLinkRecord", testGetNextAllLinkRecord),
    ("testSetInsteonModemConfiguration", testSetInsteonModemConfiguration),
    ("testGetAllLinkRecordForSender", testGetAllLinkRecordForSender),
    ("testLedOn", testLedOn),
    ("testLedOff", testLedOff),
    ("testManageAllLinkRecord", testManageAllLinkRecord),
    ("testSetInsteonNakMessageByte", testSetInsteonNakMessageByte),
    ("testSetInsteonAckMessageBytes", testSetInsteonAckMessageBytes),
    ("testRfSleep", testRfSleep),
    ("testGetInsteonModemConfiguration", testGetInsteonModemConfiguration)
  ]
  
}
