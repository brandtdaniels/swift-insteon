//
//  ExtendedCommandWaitRequest.swift
//
//
//  Created by Brandt Daniels on 6/19/20.
//

import Foundation
import InsteonMessage

public struct ExtendedCommandWaitRequest {

  private let insteonId: DeviceAddressProtocol

  private let command: ExtendedLengthDirectCommand

  public init(insteonId: DeviceAddressProtocol, command: ExtendedLengthDirectCommand) {

    self.insteonId = insteonId
    self.command = command

  }

}

// MARK: - HubRequestProtocol

extension ExtendedCommandWaitRequest: HubRequestProtocol {

  public func urlRequest(baseUrlComponents: URLComponents) -> URLRequest {

    let flagByte = InsteonMessage.MessageFlags.extendedMessageFlags
    let flagByteStr = String(format: "%02X", flagByte.rawValue)

    let byteLength = "28"

    var urlComponents = baseUrlComponents
    urlComponents.path = "/exw.xml"
    urlComponents.percentEncodedQueryItems = [
      URLQueryItem(
        name: "\(insteonId.rawValue)",
        value: "\(flagByteStr)=\(command.command.rawValue)=\(byteLength)"
      )
    ]

    return URLRequest(url: urlComponents.url!)

  }

}
