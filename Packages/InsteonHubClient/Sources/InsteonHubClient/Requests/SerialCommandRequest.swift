//
//  SerialCommandRequest.swift
//  
//
//  Created by Brandt Daniels on 6/18/20.
//

import Foundation
import InsteonSerialCommand

public struct SerialCommandRequest {

  public enum SerialCommandForm: Int {

      case short = 0

      case full = 3

  }

  private let serialCommand: SerialCommandProtocol

  public init(_ serialCommand: SerialCommandProtocol) {

    self.serialCommand = serialCommand
    
  }

}

// MARK: - HubRequestProtocol

extension SerialCommandRequest: HubRequestProtocol {

  public func urlRequest(baseUrlComponents: URLComponents) -> URLRequest {

    let commandForm: SerialCommandForm =
      serialCommand.number == .sendInsteonMessage ?
        .full : .short

    var urlComponents = baseUrlComponents
    urlComponents.path = "/\(commandForm.rawValue)"
    urlComponents.percentEncodedQueryItems = [
      URLQueryItem(
        name: serialCommand.stringValue,
        value: "I=\(commandForm.rawValue)"
      )
    ]

    return URLRequest(url: urlComponents.url!)

  }

}
