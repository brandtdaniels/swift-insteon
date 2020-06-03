//
//  InsteonHubClientProtocol.swift
//  
//
//  Created by Brandt Daniels on 4/30/20.
//

import InsteonSerialCommand

public protocol InsteonHubClientProtocol {

  func send(
    _ serialCommand: SerialCommandProtocol,
    completion: @escaping (Result<Void,Error>) -> Void
  )

}
