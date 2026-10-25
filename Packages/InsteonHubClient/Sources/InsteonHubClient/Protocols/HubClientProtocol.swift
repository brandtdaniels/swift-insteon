//
//  HubClientProtocol.swift
//  
//
//  Created by Brandt Daniels on 4/30/20.
//

import Foundation

public protocol HubClientProtocol {

  func send(
    _ hubRequest: HubRequestProtocol,
    completion: @escaping (Result<Data?,Error>) -> Void
  )

}
