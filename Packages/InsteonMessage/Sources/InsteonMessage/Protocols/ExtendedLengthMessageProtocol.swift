//
//  ExtendedLengthMessageProtocol.swift
//  
//
//  Created by Brandt Daniels on 4/26/20.
//

public protocol ExtendedLengthMessageProtocol: StandardLengthMessageProtocol {
  
  var userData: UserDataProtocol { get }
  
  var rawValue: String { get }
  
  
}
