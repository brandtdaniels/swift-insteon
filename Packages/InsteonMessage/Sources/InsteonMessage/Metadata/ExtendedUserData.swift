//
//  File.swift
//  
//
//  Created by Brandt Daniels on 4/26/20.
//

import Foundation

public struct ExtendedUserData: UserDataProtocol {
  
  public var data1: UInt8
  public var data2: UInt8
  public var data3: UInt8
  public var data4: UInt8
  public var data5: UInt8
  public var data6: UInt8
  public var data7: UInt8
  public var data8: UInt8
  public var data9: UInt8
  public var data10: UInt8
  public var data11: UInt8
  public var data12: UInt8
  public var data13: UInt8
  public var data14: UInt8

  public var rawValue: String {

    return String(
      format: "%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X",
      data1,
      data2,
      data3,
      data4,
      data5,
      data6,
      data7,
      data8,
      data9,
      data10,
      data11,
      data12,
      data13,
      data14
    )

  }
  
  public init(data1: UInt8 = 0x00, data2: UInt8 = 0x00, data3: UInt8 = 0x00, data4: UInt8 = 0x00, data5: UInt8 = 0x00, data6: UInt8 = 0x00, data7: UInt8 = 0x00, data8: UInt8 = 0x00, data9: UInt8 = 0x00, data10: UInt8 = 0x00, data11: UInt8 = 0x00, data12: UInt8 = 0x00, data13: UInt8 = 0x00, data14: UInt8 = 0x00) {
    
    self.data1 = data1
    self.data2 = data2
    self.data3 = data3
    self.data4 = data4
    self.data5 = data5
    self.data6 = data6
    self.data7 = data7
    self.data8 = data8
    self.data9 = data9
    self.data10 = data10
    self.data11 = data11
    self.data12 = data12
    self.data13 = data13
    self.data14 = data14

  }
  
}
