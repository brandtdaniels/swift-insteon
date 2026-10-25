//
//  HubRequestProtocol.swift
//  
//
//  Created by Brandt Daniels on 6/18/20.
//

import Foundation

public protocol HubRequestProtocol {

  func urlRequest(baseUrlComponents: URLComponents) -> URLRequest

}
