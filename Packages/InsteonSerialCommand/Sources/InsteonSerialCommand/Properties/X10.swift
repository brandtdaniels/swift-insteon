//
//  X10.swift
//  
//
//  Created by Brandt Daniels on 5/18/20.
//

public enum X10HouseCode: UInt8 {
  
  case a = 0x60
  case b = 0xE0
  case c = 0x20
  case d = 0xA0
  case e = 0x10
  case f = 0x90
  case g = 0x50
  case h = 0xD0
  case i = 0x70
  case j = 0xF0
  case k = 0x30
  case l = 0xB0
  case m = 0x00
  case n = 0x80
  case o = 0x40
  case p = 0xC0
  
}

public enum X10UnitCode: UInt8 {
  
  case one = 0x06
  case two = 0x0E
  case three = 0x02
  case four = 0x0A
  case five = 0x01
  case six = 0x09
  case seven = 0x05
  case eight = 0x0D
  case nine = 0x07
  case ten = 0x0F
  case eleven = 0x03
  case twelve = 0x0B
  case thirteen = 0x00
  case fourteen = 0x08
  case fifteen = 0x04
  case sixteen = 0x0C
  
}

public enum X10Command: UInt8 {
  
  case allUnitsOff = 0x00
  case allLightsOn = 0x01
  case on = 0x02
  case off = 0x03
  case dim = 0x04
  case bright = 0x05
  case allLightsOff = 0x06
  case extendedCode = 0x07
  case hailRequest = 0x08
  case hailAcknowledge = 0x09
  case presetDim = 0x0A
  case presetDim2 = 0x0B
  case extendedData = 0x0C
  case statusOn = 0x0D
  case statusOff = 0x0E
  case statusRequest = 0x0F
  
}

public enum X10Flag: UInt8 {
  
  /// 0x00 indicates that the X10 Key Code is an X10 Unit Code.
  case unitCode = 0x00
  
  /// 0x80 indicates that the X10 Key Code is an X10 Command.
  case command = 0x80
  
}
