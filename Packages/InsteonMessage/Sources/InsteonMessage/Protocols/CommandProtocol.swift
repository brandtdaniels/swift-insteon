//
//  CommandProtocol.swift
//  
//
//  Created by Brandt Daniels on 4/26/20.
//

public protocol CommandProtocol {
  
  var command1: UInt8 { get }
  
  var command2: UInt8 { get }
  
  var rawValue: String { get }
  
}
