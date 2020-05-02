//
//  Command.swift
//  
//
//  Created by Brandt Daniels on 4/26/20.
//

public struct Command: CommandProtocol, Equatable {
  
  public var command1: UInt8
  
  public var command2: UInt8

  public var rawValue: String {
    
    return String(
      format: "%02X%02X",
      command1,
      command2
    )
    
  }
  
  init(
    command1: UInt8,
    command2: UInt8 = 0x00
  ) {
    
    self.command1 = command1
    self.command2 = command2
    
  }
  
}
