//
//  AuthConfiguration.swift
//  
//
//  Created by Brandt Daniels on 6/27/20.
//

public struct AuthConfiguration: AuthConfigurationProtocol {
  
  public let clientId: String
  
  public let clientSecret: String
  
  public let redirectUri: String
  
  public let state: String?
  
  public var authorizationEndpoint: String
  
  public var tokenEndpoint: String
  
  public var responseType: String
  
  public init(
    clientId: String,
    clientSecret: String,
    redirectUri: String,
    state: String?,
    authorizationEndpoint: String,
    tokenEndpoint: String,
    responseType: String
  ) {
    
    self.clientId = clientId
    
    self.clientSecret = clientSecret
    
    self.redirectUri = redirectUri
    
    self.state = state
    
    self.authorizationEndpoint = authorizationEndpoint
    
    self.tokenEndpoint = tokenEndpoint
    
    self.responseType = responseType
    
  }
  
}
