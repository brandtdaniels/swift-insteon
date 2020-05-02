//
//  StandardLengthMessage.swift
//  
//
//  Created by Brandt Daniels on 4/26/20.
//

public struct StandardLengthMessage: StandardLengthMessageProtocol {
  
  public var toAddress: DeviceAddressProtocol
  
  public let flags: MessageFlags
  
  public var command: CommandProtocol

  public var rawValue: String {

    return String(
      format: "%@%02X%@",
      toAddress.rawValue,
      flags.rawValue,
      command.rawValue
    )

  }

  public init(
    to address: DeviceAddressProtocol,
    flags: MessageFlags = .standardMessageFlags,
    command: CommandProtocol
  ) {
    
    self.toAddress = address
    self.flags = flags
    self.command = command
    
  }
  
}
