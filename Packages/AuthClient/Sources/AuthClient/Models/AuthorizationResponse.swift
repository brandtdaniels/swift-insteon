//
//  AuthorizationResponse.swift
//  
//
//  Created by Brandt Daniels on 6/27/20.
//

import Foundation

public struct AuthorizationResponse {
  
  typealias AuthorizationCode = String
  
  typealias State = String
  
  var state: State? {
    
    guard let stateQueryItem = queryItems.filter({ $0.name == "state" }).first else {
      
      return nil
      
    }
    
    return stateQueryItem.value
    
  }
  
  var code: AuthorizationCode? {
    
    guard let codeQueryItem = queryItems.filter({ $0.name == "code" }).first else {
      
      return nil
      
    }
    
    return codeQueryItem.value
    
  }
  
  private var queryItems: [URLQueryItem] {
    
    let urlString = url.absoluteString
    
    let components = URLComponents(string: urlString)
    
    return components?.queryItems ?? []
    
  }
  
  private let url: URL
  
  init(_ url: URL) {
    
    self.url = url
    
  }
  
}

public enum GrantType {
  
  case code
  
  case token
  
}

