//
//  InsteonIdentifier.swift
//  
//
//  Created by Brandt Daniels on 4/26/20.
//

public struct InsteonIdentifier: DeviceAddressProtocol {
  
  public var highByte: UInt8
  
  public var middleByte: UInt8
  
  public var lowByte: UInt8

  public var rawValue: String {

    return String(
      format: "%02X%02X%02X",
      highByte,
      middleByte,
      lowByte
    )

  }
  
  public init(
    _ highByte: UInt8,
    _ middleByte: UInt8,
    _ lowByte: UInt8
  ) {
    
    self.highByte = highByte
    self.middleByte = middleByte
    self.lowByte = lowByte
    
  }
  
}
