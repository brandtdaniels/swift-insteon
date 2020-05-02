//
//  StandardLengthMessageProtocol.swift
//
//
//  Created by Brandt Daniels on 4/26/20.
//

public protocol StandardLengthMessageProtocol {
  
  var toAddress: DeviceAddressProtocol { get }
  
  var flags: MessageFlags { get }
  
  var command: CommandProtocol { get }
  
  var rawValue: String { get }
  
}


