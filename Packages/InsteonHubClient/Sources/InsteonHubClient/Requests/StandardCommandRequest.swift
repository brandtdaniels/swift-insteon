//
//  StandardCommandRequest.swift
//  
//
//  Created by Brandt Daniels on 6/19/20.
//

import Foundation
import InsteonMessage

public struct StandardCommandRequest {

  private let insteonId: DeviceAddressProtocol

  private let command: StandardLengthDirectCommand

  public init(insteonId: DeviceAddressProtocol, command: StandardLengthDirectCommand) {

    self.insteonId = insteonId
    self.command = command

  }

}

// MARK: - HubRequestProtocol

extension StandardCommandRequest: HubRequestProtocol {

  public func urlRequest(baseUrlComponents: URLComponents) -> URLRequest {

    var urlComponents = baseUrlComponents
    urlComponents.path = "/sx.xml"
    urlComponents.queryItems = [
      URLQueryItem(
        name: "\(insteonId.rawValue)",
        value: "\(command.command.rawValue)"
      )
    ]

    return URLRequest(url: urlComponents.url!)

  }

}
