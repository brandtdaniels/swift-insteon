//
//  CommandBufferRequest.swift
//  
//
//  Created by Brandt Daniels on 6/19/20.
//

import Foundation

public struct CommandBufferRequest {}

// MARK: - HubRequestProtocol

extension CommandBufferRequest: HubRequestProtocol {

  public func urlRequest(baseUrlComponents: URLComponents) -> URLRequest {

    var urlComponents = baseUrlComponents
    urlComponents.path = "/buffstatus.xml"

    return URLRequest(url: urlComponents.url!)

  }

}
