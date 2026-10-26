//
//  LoginCredentials.swift
//  
//
//  Created by Brandt Daniels on 4/30/20.
//

public struct LoginCredentials: LoginCredentialsProtocol {

  public var user: String

  public var password: String

  public init(user: String, password: String) {

    self.user = user
    self.password = password

  }

}
