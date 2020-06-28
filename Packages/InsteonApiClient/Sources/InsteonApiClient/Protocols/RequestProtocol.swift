//
//  RequestProtocol.swift
//  
//
//  Created by Brandt Daniels on 6/28/20.
//

import Foundation

public protocol RequestProtocol {

  associatedtype Response: Decodable

  var urlRequest: URLRequest { get }

}

