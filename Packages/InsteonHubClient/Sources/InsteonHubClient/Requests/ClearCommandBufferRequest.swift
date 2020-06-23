//
//  ClearCommandBufferRequest.swift
//  
//
//  Created by Brandt Daniels on 6/19/20.
//

import Foundation

public struct ClearCommandBufferRequest {}

// MARK: - HubRequestProtocol

extension ClearCommandBufferRequest: HubRequestProtocol {

  public func urlRequest(baseUrlComponents: URLComponents) -> URLRequest {

    var urlComponents = baseUrlComponents
    urlComponents.path = "/1"
    urlComponents.percentEncodedQueryItems = [
      URLQueryItem(
        name: "XB",
        value: "M=1"
      )
    ]

    return URLRequest(url: urlComponents.url!)

  }

}
