//
//  StandardLengthDirectCommand.swift
//  
//
//  Created by Brandt Daniels on 4/26/20.
//

public enum StandardLengthDirectCommand {
  
  case assign(toAllLinkGroup: UInt8)
  
  case delete(fromAllLinkGroup: UInt8)
  
  case cancelLinkingMode
  
  case enterLinkingMode(forGroup: UInt8)
  
  case enterUnlinkingMode(forGroup: UInt8)
  
  case getInsteonEngineVersion
  
  case ping
  
  case idRequest
  
  case lightOn(level: UInt8)
    
  case lightOnFast(level: UInt8)

  case lightOff
  
  case lightOffFast
  
  case lightBrightenOneStep
  
  case lightDimOneStep
  
  case lightStartManualChange(direction: LightStartManualChangeDirection)
  
  case lightStopManualChange
  
  case lightStatusRequest
  
  case getOperatingFlags(requested: OperatingFlagsRequested)
  
  case setOperatingFlags(flag: UInt8)
  
  case lightInstantChange(level: UInt8)
  
  case lightManuallyTurnedOff
  
  case lightManuallyTurnedOn
  
  case remoteSetButtonTap(count: SetButtonTapCount)
  
  /// 0x00 ⇒ 0xFF,
  /// Bits 0-3 = 2 x Ramp Rate + 1,
  /// Bits 4-7 = On-Level + 0x0F
  case lightOnAtRampRate(rampRateAndOnLevel: UInt8)
  
  /// 0x00 ⇒ 0x0F Ramp Rate
  case lightOffAtRampRate(rampRate: UInt8)
  
  public var command: Command {
    
    switch self {
      
    case .assign(toAllLinkGroup: let group):
      return Command(command1: 0x01, command2: group)
      
    case .delete(fromAllLinkGroup: let group):
      return Command(command1: 0x02, command2: group)
      
    case .cancelLinkingMode:
      return Command(command1: 0x08)
      
    case .enterLinkingMode(forGroup: let group):
      return Command(command1: 0x09, command2: group)
      
    case .enterUnlinkingMode(forGroup: let group):
      return Command(command1: 0x0A, command2: group)
      
    case .getInsteonEngineVersion:
      return Command(command1: 0x0D)
      
    case .ping:
      return Command(command1: 0x0F)
      
    case .idRequest:
      return Command(command1: 0x10)
      
    case .lightOn(level: let level):
      return Command(command1: 0x11, command2: level)
      
    case .lightOnFast(level: let level):
      return Command(command1: 0x12, command2: level)
      
    case .lightOff:
      return Command(command1: 0x13)
      
    case .lightOffFast:
      return Command(command1: 0x14)
      
    case .lightBrightenOneStep:
      return Command(command1: 0x15)
      
    case .lightDimOneStep:
      return Command(command1: 0x16)
      
    case .lightStartManualChange(direction: let direction):
      return Command(command1: 0x17, command2: direction.rawValue)
      
    case .lightStopManualChange:
      return Command(command1: 0x18)
      
    case .lightStatusRequest:
      return Command(command1: 0x19, command2: 0x00) // TODO: Revisit command2
      
    case .getOperatingFlags(requested: let requested):
      return Command(command1: 0x1F, command2: requested.rawValue)
      
    case .setOperatingFlags(flag: let flag):
      return Command(command1: 0x20, command2: flag)
      
    case .lightInstantChange(level: let level):
      return Command(command1: 0x21, command2: level)
      
    case .lightManuallyTurnedOff:
      return Command(command1: 0x22)
      
    case .lightManuallyTurnedOn:
      return Command(command1: 0x23)
      
    case .remoteSetButtonTap(count: let count):
      return Command(command1: 0x25, command2: count.rawValue)
      
    case .lightOnAtRampRate(rampRateAndOnLevel: let rampRateOnLevel):
      return Command(command1: 0x2E, command2: rampRateOnLevel)
      
    case .lightOffAtRampRate(rampRate: let rampRate):
      return Command(command1: 0x2F, command2: rampRate)
      
    }
    
  }
  
}

public enum LightStartManualChangeDirection: UInt8 {
  case down = 0x00
  case up = 0x01
}

public enum OperatingFlagsRequested: UInt8 {
  case operatingFlags = 0x00
  case allLinkDatabaseDelta = 0x01
  case signalToNoiseValue = 0x02
}

public enum SetButtonTapCount: UInt8 {
  case oneTap = 0x01
  case twoTaps = 0x02
}

