//
//  ExtendedLengthMessage.swift
//  
//
//  Created by Brandt Daniels on 4/26/20.
//

public struct ExtendedLengthMessage: ExtendedLengthMessageProtocol {
  
  public var toAddress: DeviceAddressProtocol
  
  public let flags: MessageFlags
  
  public var command: CommandProtocol
  
  public var userData: UserDataProtocol

  public var rawValue: String {

    return String(
      format: "%@%02X%@%@",
      toAddress.rawValue,
      flags.rawValue,
      command.rawValue,
      userData.rawValue
    )

  }
  
  public init(
    to address: DeviceAddressProtocol,
    flags: MessageFlags = .extendedMessageFlags,
    command: CommandProtocol,
    userData: UserDataProtocol = ExtendedUserData()
  ) {
    
    self.toAddress = address
    self.flags = flags
    self.command = command
    self.userData = userData
    
  }
  
}
