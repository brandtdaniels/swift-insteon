//
//  LinkStatusRequest.swift
//  
//
//  Created by Brandt Daniels on 6/29/20.
//

import Foundation

public struct LinkStatusRequest {}

// MARK: - HubRequestProtocol

extension LinkStatusRequest: HubRequestProtocol {

  public func urlRequest(baseUrlComponents: URLComponents) -> URLRequest {

    var urlComponents = baseUrlComponents
    urlComponents.path = "/Linkstatus.xml"

    return URLRequest(url: urlComponents.url!)

  }

}
