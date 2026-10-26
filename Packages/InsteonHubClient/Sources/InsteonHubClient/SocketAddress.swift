//
//  SocketAddress.swift
//  
//
//  Created by Brandt Daniels on 4/30/20.
//

public struct SocketAddress: SocketAddressProtocol {

  public var host: String

  public var port: Int

  public init(host: String, port: Int) {

    self.host = host
    self.port = port

  }

}
