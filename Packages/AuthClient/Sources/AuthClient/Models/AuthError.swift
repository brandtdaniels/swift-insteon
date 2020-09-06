//
//  AuthError.swift
//  
//
//  Created by Brandt Daniels on 6/27/20.
//

public enum AuthError: Error {
  
  case authorization(message: String)
  case unknown
  
}
