//
//  UpdateCredentialsRequest.swift
//  
//
//  Created by Brandt Daniels on 6/19/20.
//

import Foundation

public struct UpdateCredentialsRequest {

  private let username: String

  private let password: String

  public init(username: String, password: String) {

    self.username = username
    self.password = password

  }

}

// MARK: - HubRequestProtocol

extension UpdateCredentialsRequest: HubRequestProtocol {

  public func urlRequest(baseUrlComponents: URLComponents) -> URLRequest {

    var urlComponents = baseUrlComponents
    urlComponents.path = "/1"
    urlComponents.percentEncodedQueryItems = [
      URLQueryItem(
        name: "L",
        value: "\(username)=1=\(password)"
      )
    ]

    return URLRequest(url: urlComponents.url!)

  }

}
