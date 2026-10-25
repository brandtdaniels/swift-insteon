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
    
}
