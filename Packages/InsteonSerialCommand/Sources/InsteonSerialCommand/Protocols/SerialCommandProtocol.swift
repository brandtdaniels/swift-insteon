//
//  SerialCommandProtocol.swift
//  
//
//  Created by Brandt Daniels on 5/17/20.
//

public protocol SerialCommandProtocol {

  var type: SerialCommandType { get }

  var stringValue: String { get }
  
}
