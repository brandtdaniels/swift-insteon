//
//  TokenResponse.swift
//  
//
//  Created by Brandt Daniels on 6/27/20.
//

import Foundation

public struct TokenResponse {
  
  public var accessToken: String
  
  public var refreshToken: String
  
  public var tokenType: TokenType
  
  public var expiresIn: Double
  
  public var expiration: Date? {
    
    return Date(timeIntervalSinceNow: expiresIn * 60)
    
  }
  
  public var expirationDateString: String? {
    
    guard let expiration = expiration else {
      
      return nil
      
    }
    
    let formatter = DateFormatter()
    return formatter.string(from: expiration)
    
  }
  
  public var isExpired: Bool {
    
    guard let expiration = expiration else {
      
      return true
      
    }
    
    return expiration.compare(Date()) == .orderedAscending
      || expiration.compare(Date()) == .orderedSame
    
  }
  
  public init(accessToken: String, refreshToken: String, tokenType: TokenType, expiresIn: Double) {
    
    self.accessToken = accessToken
    self.refreshToken = refreshToken
    self.tokenType = tokenType
    self.expiresIn = expiresIn
    
  }
  
}

// MARK: - Decodable

extension TokenResponse: Decodable {
  
  private enum CodingKeys: String, CodingKey {
    
    case accessToken = "access_token"
    
    case refreshToken = "refresh_token"
    
    case tokenType = "token_type"
    
    case expiresIn = "expires_in"
    
  }
  
}

public enum TokenType: String, Decodable {
  
  case bearer = "Bearer"
  
}
