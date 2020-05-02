//
//  ExtendedLengthDirectCommand.swift
//  
//
//  Created by Brandt Daniels on 4/26/20.
//

public enum ExtendedLengthDirectCommand {
  
  case extendedSetGet
  
  case readWriteAllLinkDatabase
  
  public var command: Command {
    
    switch self {
      
    case .extendedSetGet:
      return Command(command1: 0x2E)
      
    case .readWriteAllLinkDatabase:
      return Command(command1: 0x2F)
      
    }
    
  }
  
}
