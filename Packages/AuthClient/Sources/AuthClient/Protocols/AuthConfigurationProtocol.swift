//
//  AuthConfigurationProtocol.swift
//  
//
//  Created by Brandt Daniels on 6/27/20.
//

public protocol AuthConfigurationProtocol {
  
  var clientId: String { get }
  
  var clientSecret: String { get }
  
  var redirectUri: String { get }
  
  var state: String? { get }
  
  var authorizationEndpoint: String { get }
  
  var tokenEndpoint: String { get }
  
  var responseType: String { get }
  
}
