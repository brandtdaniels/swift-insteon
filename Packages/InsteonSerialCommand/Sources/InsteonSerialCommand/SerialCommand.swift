//
//  SerialCommand.swift
//  
//
//  Created by Brandt Daniels on 5/17/20.
//

import Foundation

public let acknowledgement = 0x06

public let negativeAcknowledgement = 0x15

public let startOfText = 0x02

// MARK: - SerialCommand

public struct SerialCommand {
  
  public let type: SerialCommandType
  
  public init(_ type: SerialCommandType) {
    
    self.type = type
    
  }
  
}

// MARK: - SerialCommandProtocol

extension SerialCommand: SerialCommandProtocol {
  
  public var number: SerialCommandNumber {
    
    switch type {
      
    case .getInsteonModemInformation:
      
      return SerialCommandNumber.getInsteonModemInformation
      
    case .sendAllLinkCommand(_, _, _):
      
      return SerialCommandNumber.sendAllLinkCommand
      
    case .sendInsteonStandardMessage(_):
      
      return SerialCommandNumber.sendInsteonMessage
      
    case .sendInsteonExtendedMessage(_):
      
      return SerialCommandNumber.sendInsteonMessage
      
    case .sendX10(_, _):
      
      return SerialCommandNumber.sendX10
      
    case .startAllLinking(_, _):
      
      return SerialCommandNumber.startAllLinking
      
    case .cancelAllLinking:
      
      return SerialCommandNumber.cancelAllLinking
      
    case .setHostDeviceCategory(_, _):
      
      return SerialCommandNumber.setHostDeviceCategory
      
    case .resetInsteonModem:
      
      return SerialCommandNumber.resetInsteonModem
      
    case .setInsteonAckMessageByte(_):
      
      return SerialCommandNumber.setInsteonAckMessageByte
      
    case .getFirstAllLinkRecord:
      
      return SerialCommandNumber.getFirstAllLinkRecord
      
    case .getNextAllLinkRecord:
      
      return SerialCommandNumber.getNextAllLinkRecord
      
    case .setInsteonModemConfiguration(_):
      
      return SerialCommandNumber.setInsteonModemConfiguration
      
    case .getAllLinkRecordForSender:
      
      return SerialCommandNumber.getAllLinkRecordForSender
      
    case .ledOn:
      
      return SerialCommandNumber.ledOn
      
    case .ledOff:
      
      return SerialCommandNumber.ledOff
      
    case .manageAllLinkRecord(_, _, _, _, _, _, _):
      
      return SerialCommandNumber.manageAllLinkRecord
      
    case .setInsteonNakMessageByte(_):
      
      return SerialCommandNumber.setInsteonNakMessageByte
      
    case .setInsteonAckMessageBytes(_, _):
      
      return SerialCommandNumber.setInsteonAckMessageBytes
      
    case .rfSleep:
      
      return SerialCommandNumber.rfSleep
      
    case .getInsteonModemConfiguration:
      
      return SerialCommandNumber.getInsteonModemConfiguration
      
    }
    
  }
  
  public var stringValue: String {
    
    return String(
      format: "%02X%02X%@", startOfText, number.rawValue, parameterStringValue
    )
    
  }
  
  private var parameterStringValue: String {
    
    switch type {
      
    case let .sendAllLinkCommand(command, group, broadcastCommand2):
      
      return String(
        format: "%02X%02X%02X",
        command,
        group,
        broadcastCommand2
      )
      
    case let .sendInsteonStandardMessage(message):
      
      return message.rawValue
      
    case let .sendInsteonExtendedMessage(message):
      
      return message.rawValue
      
    case let .sendX10(rawX10, x10Flag):
      
      return String(
        format: "%02X%02X",
        rawX10,
        x10Flag.rawValue
      )
      
    case let .startAllLinking(linkCode, group):
      
      return String(
        format: "%02X%02X",
        linkCode.rawValue,
        group
      )
      
    case let .setHostDeviceCategory(category, subCategory):
      
      return String(
        format: "%02X%02X%02X",
        category,
        subCategory,
        0xFF
      )
      
    case let .setInsteonAckMessageByte(command2):
      
      return String(
        format: "%02X",
        command2
      )
      
    case let .setInsteonModemConfiguration(configurationFlags):
      
      return String(
        format: "%02X",
        configurationFlags.rawValue
      )
      
    case let .manageAllLinkRecord(controlCode, recordFlags, group, insteonId, linkData1, linkData2, linkData3):
      
      return String(
        format: "%02X%02X%02X\(insteonId.rawValue)%02X%02X%02X",
        controlCode.rawValue,
        recordFlags.rawValue,
        group,
        linkData1,
        linkData2,
        linkData3
      )
      
    case let .setInsteonNakMessageByte(command2):
      
      return String(
        format: "%02X",
        command2
      )
      
    case let .setInsteonAckMessageBytes(command1, command2):
      
      return String(
        format: "%02X%02X",
        command1,
        command2
      )
      
    default: return ""
      
    }
    
  }
  
  
}
