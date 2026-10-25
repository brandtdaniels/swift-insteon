//
//  AuthClient.swift
//
//
//  Created by Brandt Daniels on 6/27/20.
//

import Foundation
import OAuthSwift

public struct AuthClient {
  
  public var clientId: String
  
  private let configuration: AuthConfigurationProtocol
  
  private let oauthSwift: OAuth2Swift
  
  public init(_ configuration: AuthConfigurationProtocol) {
    
    self.configuration = configuration
    
    clientId = configuration.clientId
    
    oauthSwift = OAuth2Swift(
      consumerKey: configuration.clientId,
      consumerSecret: configuration.clientSecret,
      authorizeUrl: configuration.authorizationEndpoint,
      accessTokenUrl: configuration.tokenEndpoint,
      responseType: configuration.responseType
    )
    
  }
  
}

// MARK: - AuthClientProtocol

extension AuthClient: AuthClientProtocol {
  
  public func authorize(completion: @escaping (Result<TokenResponse, AuthError>) -> Void) {
    
    oauthSwift.authorize(
      withCallbackURL: configuration.redirectUri,
      scope: "",
      state: configuration.state ?? ""
    ) { result in
      
      switch result {
      
      case let .success((credential, _, parameters)):
        
        var tokenType = TokenType.bearer
        if let tokenTypeStr = parameters["token_type"] as? String,
           let paramTokenType = TokenType(rawValue: tokenTypeStr) {
          
          tokenType = paramTokenType
          
        }
        
        let tokenResponse = TokenResponse(
          accessToken: credential.oauthToken,
          refreshToken: credential.oauthRefreshToken,
          tokenType: tokenType,
          expiresIn: parameters["expires_in"] as? Double ?? 7200
        )
        
        completion(.success(tokenResponse))
        
      case .failure(let error):
        
        print(error.localizedDescription)
        
        completion(.failure(.authorization(message: error.localizedDescription)))
        
      }
      
    }
    
  }
  
  public func renewAccessToken(withRefreshToken refreshToken: String,
                               completion: @escaping (Result<TokenResponse, AuthError>) -> Void) {
    
    oauthSwift.renewAccessToken(withRefreshToken: refreshToken) { result in
      
      switch result {
      
      case let .success(tokenSuccess):
        
        print(tokenSuccess)
        
        let tokenResponse = TokenResponse(
          accessToken: tokenSuccess.credential.oauthToken,
          refreshToken: tokenSuccess.credential.oauthRefreshToken,
          tokenType: TokenType(rawValue: tokenSuccess.parameters["token_type"] as? String ?? "Bearer") ?? .bearer,
          expiresIn: tokenSuccess.parameters["expires_in"] as? Double ?? 7200
        )
        
        completion(.success(tokenResponse))
        
      case let .failure(error):
        
        print(error)
        
        completion(.failure(.authorization(message: error.localizedDescription)))
        
      }
      
    }
    
  }
  
  public static func handle(url: URL) {
    
    OAuthSwift.handle(url: url)
    
  }
  
}
