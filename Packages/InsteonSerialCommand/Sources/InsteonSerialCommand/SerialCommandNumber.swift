//
//  SerialCommandNumber.swift
//  
//
//  Created by Brandt Daniels on 5/17/20.
//

public enum SerialCommandNumber: UInt8 {
  
  // Commands sent from an IM to the Host
  case standardMessageReceived = 0x50
  case extendedMessageReceived = 0x51
  case x10Received = 0x52
  case allLinkingCompleted = 0x53
  case buttonEventReport = 0x54
  case userResetDetected = 0x55
  case allLinkCleanupFailureReport = 0x56
  case allLinkRecordResponse = 0x57
  case allLinkCleanupStatusReport = 0x58
  case databaseRecordFound = 0x59
  
  // Commands sent from the Host to an IM
  case getInsteonModemInformation = 0x60
  case sendAllLinkCommand = 0x61
  case sendInsteonMessage = 0x62
  case sendX10 = 0x63
  case startAllLinking = 0x64
  case cancelAllLinking = 0x65
  case setHostDeviceCategory = 0x66
  case resetInsteonModem = 0x67
  case setInsteonAckMessageByte = 0x68
  case getFirstAllLinkRecord = 0x69
  case getNextAllLinkRecord = 0x6A
  case setInsteonModemConfiguration = 0x6B
  case getAllLinkRecordForSender = 0x6C
  case ledOn = 0x6D
  case ledOff = 0x6E
  case manageAllLinkRecord = 0x6F
  case setInsteonNakMessageByte = 0x70
  case setInsteonAckMessageBytes = 0x71
  case rfSleep = 0x72
  case getInsteonModemConfiguration = 0x73
  case cancelCleanup = 0x74
  case readEightBytesFromDatabase = 0x75
  case writeEightBytesToDatabase = 0x76
  case beep = 0x77
  case setStatus = 0x78
  
  // RF Modem only commands
  case setDatabaseLinkDataForNextLink = 0x79
  case setApplicationRetriesForNextLink = 0x7A
  case setRFFrequencyOffset = 0x7B
  case setAcknowledgeForTempLincCommand = 0x7C
  
}
