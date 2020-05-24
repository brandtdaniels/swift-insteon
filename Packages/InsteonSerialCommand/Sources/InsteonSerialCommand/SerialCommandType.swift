//
//  SerialCommandType.swift
//  
//
//  Created by Brandt Daniels on 5/19/20.
//

import Foundation
import InsteonMessage

public enum SerialCommandType {
  
  case getInsteonModemInformation //60
  
  case sendAllLinkCommand(command: UInt8, group: UInt8, broadcastCommand2: UInt8) //61
  
  case sendInsteonStandardMessage(message: StandardLengthMessageProtocol) //62
  
  case sendInsteonExtendedMessage(message: ExtendedLengthMessageProtocol) //62
  
  case sendX10(rawX10: UInt8, x10Flag: X10Flag) //63
  
  case startAllLinking(linkCode: LinkCode, group: UInt8) //64
  
  case cancelAllLinking //65
  
  case setHostDeviceCategory(category: UInt8, subCategory: UInt8)  //66
  
  case resetInsteonModem //67
  
  case setInsteonAckMessageByte(command2: UInt8) //68
  
  case getFirstAllLinkRecord //69
  
  case getNextAllLinkRecord  //6A
  
  case setInsteonModemConfiguration(configurationFlags: ModemConfiguration) //6B
  
  case getAllLinkRecordForSender  //6C
  
  case ledOn //6D
  
  case ledOff //6E
  
  case manageAllLinkRecord(controlCode: ControlCode, recordFlags: RecordFlags, group: UInt8, insteonId: DeviceAddressProtocol, linkData1: UInt8, linkData2: UInt8, linkData3: UInt8) //6F
  
  case setInsteonNakMessageByte(command2: UInt8) //70
  
  case setInsteonAckMessageBytes(command1: UInt8, command2: UInt8) //71
  
  case rfSleep //72
  
  case getInsteonModemConfiguration //73
  
  public var stringValue: String {
    
    switch self {
      
    case .getInsteonModemInformation:
      
      return String(
        format: "%02X",
        SerialCommandNumber.getInsteonModemInformation.rawValue
      )
      
    case let .sendAllLinkCommand(command, group, broadcastCommand2):
      
      return String(
        format: "%02X%02X%02X%02X",
        SerialCommandNumber.sendAllLinkCommand.rawValue,
        command,
        group,
        broadcastCommand2
      )
      
    case let .sendInsteonStandardMessage(message):
      
      return String(
        format: "%02X%@",
        SerialCommandNumber.sendInsteonMessage.rawValue,
        message.rawValue
      )
      
    case let .sendInsteonExtendedMessage(message):
      
      return String(
        format: "%02X%@",
        SerialCommandNumber.sendInsteonMessage.rawValue,
        message.rawValue
      )
      
    case let .sendX10(rawX10, x10Flag):
      
      return String(
        format: "%02X%02X%02X",
        SerialCommandNumber.sendX10.rawValue,
        rawX10,
        x10Flag.rawValue
      )
      
    case let .startAllLinking(linkCode, group):
      
      return String(
        format: "%02X%02X%02X",
        SerialCommandNumber.startAllLinking.rawValue,
        linkCode.rawValue,
        group
      )
      
    case .cancelAllLinking:
      
      return String(
        format: "%02X",
        SerialCommandNumber.cancelAllLinking.rawValue
      )
      
    case let .setHostDeviceCategory(category, subCategory):
      
      return String(
        format: "%02X%02X%02X%02X",
        SerialCommandNumber.setHostDeviceCategory.rawValue,
        category,
        subCategory,
        0xFF
      )
      
    case .resetInsteonModem:
      
      return String(
        format: "%02X",
        SerialCommandNumber.resetInsteonModem.rawValue
      )
      
    case let .setInsteonAckMessageByte(command2):
      
      return String(
        format: "%02X%02X",
        SerialCommandNumber.setInsteonAckMessageByte.rawValue,
        command2
      )
      
    case .getFirstAllLinkRecord:
      
      return String(
        format: "%02X",
        SerialCommandNumber.getFirstAllLinkRecord.rawValue
      )
      
    case .getNextAllLinkRecord:
      
      return String(
        format: "%02X",
        SerialCommandNumber.getNextAllLinkRecord.rawValue
      )
      
    case let .setInsteonModemConfiguration(configurationFlags):
      
      return String(
        format: "%02X%02X",
        SerialCommandNumber.setInsteonModemConfiguration.rawValue,
        configurationFlags.rawValue
      )
      
    case .getAllLinkRecordForSender:
      
      return String(
        format: "%02X",
        SerialCommandNumber.getAllLinkRecordForSender.rawValue
      )
      
    case .ledOn:
      
      return String(
        format: "%02X",
        SerialCommandNumber.ledOn.rawValue
      )
      
    case .ledOff:
      
      return String(
        format: "%02X",
        SerialCommandNumber.ledOff.rawValue
      )
      
    case let .manageAllLinkRecord(controlCode, recordFlags, group, insteonId, linkData1, linkData2, linkData3):
      
      return String(
        format: "%02X%02X%02X%02X\(insteonId.rawValue)%02X%02X%02X",
        SerialCommandNumber.manageAllLinkRecord.rawValue,
        controlCode.rawValue,
        recordFlags.rawValue,
        group,
        linkData1,
        linkData2,
        linkData3
      )
      
    case let .setInsteonNakMessageByte(command2):
      
      return String(
        format: "%02X%02X",
        SerialCommandNumber.setInsteonNakMessageByte.rawValue,
        command2
      )
      
    case let .setInsteonAckMessageBytes(command1, command2):
      
      return String(
        format: "%02X%02X%02X",
        SerialCommandNumber.setInsteonAckMessageBytes.rawValue,
        command1,
        command2
      )
      
    case .rfSleep:
      
      return String(
        format: "%02X",
        SerialCommandNumber.rfSleep.rawValue
      )
      
    case .getInsteonModemConfiguration:
      
      return String(
        format: "%02X",
        SerialCommandNumber.getInsteonModemConfiguration.rawValue
      )
      
    }
    
  }
  
}
