//
//  RequestClientProtocol.swift
//  
//
//  Created by Brandt Daniels on 4/30/20.
//

import Foundation

public protocol RequestClientProtocol {

  func send(
    _ request: URLRequest,
    completion: @escaping (
    _ data: Data?,
    _ response: URLResponse?,
    _ error: Error?
    ) -> Void
  )

}
