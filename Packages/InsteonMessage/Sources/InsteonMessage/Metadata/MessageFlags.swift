//
//  MessageFlags.swift
//  
//
//  Created by Brandt Daniels on 4/26/20.
//

public struct MessageFlags: OptionSet {
  
  public let rawValue: UInt8
  
  public init(rawValue: UInt8) {
    
    self.rawValue = rawValue
    
  }
  
  static let maxHopsLowBit = MessageFlags(rawValue: 1 << 0)
  static let maxHopsHighBit = MessageFlags(rawValue: 1 << 1)
  static let hopsLeftLowBit = MessageFlags(rawValue: 1 << 2)
  static let hopsLeftHighBit = MessageFlags(rawValue: 1 << 3)
  static let extendedMessage = MessageFlags(rawValue: 1 << 4)
  static let acknowledgement = MessageFlags(rawValue: 1 << 5)
  static let allLink = MessageFlags(rawValue: 1 << 6)
  static let broadcastNAK = MessageFlags(rawValue: 1 << 7)
  
  // Max Hops
  // Empty set - Do not retransmit this message
  static let oneRetransmissionMax: MessageFlags = .maxHopsLowBit
  static let twoRetransmissionsMax: MessageFlags = .maxHopsHighBit
  static let threeRetransmissionsMax: MessageFlags = [.maxHopsLowBit, .maxHopsHighBit]
  
  // Hops Left
  // Empty set - 0 message retransmissions remaining
  static let oneRetransmissionRemaining: MessageFlags =  .hopsLeftLowBit
  static let twoRetransmissionsRemaining: MessageFlags = .hopsLeftHighBit
  static let threeRetransmissionsRemaining: MessageFlags = [.hopsLeftLowBit, .hopsLeftHighBit]
  
  // Message Types
  // Empty set - Direct Message Type
  static let broadcastMessage: MessageFlags = .broadcastNAK
  static let ackDirectMessage: MessageFlags = .acknowledgement
  static let nakDirectMessage: MessageFlags = [.acknowledgement, .broadcastNAK]
  static let allLinkBroadcastMessage: MessageFlags = [.allLink, .broadcastNAK]
  static let allLinkCleanupMessage: MessageFlags = .allLink
  static let ackAllLinkCleanupMessage: MessageFlags = [.acknowledgement, .allLink]
  static let nakAllLinkCleanupMessage: MessageFlags = [.acknowledgement, .allLink, .broadcastNAK]
  
  // Convenience
  public static let standardMessageFlags: MessageFlags = [.threeRetransmissionsMax, .threeRetransmissionsRemaining]
  public static let extendedMessageFlags: MessageFlags = [.threeRetransmissionsMax, .threeRetransmissionsRemaining, .extendedMessage]
  
}
