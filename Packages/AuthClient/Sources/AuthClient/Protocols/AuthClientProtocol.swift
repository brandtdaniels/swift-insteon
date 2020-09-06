//
//  AuthClientProtocol.swift
//  
//
//  Created by Brandt Daniels on 6/27/20.
//

import Foundation

public protocol AuthClientProtocol {
  
  typealias AuthorizationCode = String
  
  typealias State = String
  
  typealias AccessToken = String
  
  typealias RefreshToken = String
  
  var clientId: String { get }
  
  func authorize(completion: @escaping (Result<TokenResponse, AuthError>) -> Void)
  
  func renewAccessToken(withRefreshToken: String, completion: @escaping (Result<TokenResponse, AuthError>) -> Void)
  
  static func handle(url: URL)
  
}
