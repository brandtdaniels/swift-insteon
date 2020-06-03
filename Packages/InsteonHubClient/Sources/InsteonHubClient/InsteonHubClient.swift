//
//  InsteonHubClient.swift
//
//
//  Created by Brandt Daniels on 4/30/20.
//

import Foundation
import RequestClient
import InsteonSerialCommand

public struct InsteonHubClient {

  private var baseUrlComponents: URLComponents {

    var urlComponents = URLComponents()
    urlComponents.scheme = "http"
    urlComponents.host = address.host
    urlComponents.port = address.port

    return urlComponents

  }

  private let credentials: LoginCredentialsProtocol

  private let address: SocketAddressProtocol

  private let requestClient: RequestClientProtocol

  public init(
    credentials: LoginCredentialsProtocol,
    address: SocketAddressProtocol,
    requestClient: RequestClientProtocol
  ) {

    self.credentials = credentials
    self.address = address
    self.requestClient = requestClient

  }

}

// MARK: - InsteonHubClientProtocol

extension InsteonHubClient: InsteonHubClientProtocol {

  public func send(
    _ serialCommand: SerialCommandProtocol,
    completion: @escaping (Result<Void, Error>)
    -> Void) {

    let commandForm: SerialCommandForm = .short

    var urlComponents = baseUrlComponents
    urlComponents.path = "/\(commandForm.rawValue)"
    urlComponents.queryItems = [
      URLQueryItem(
        name: serialCommand.stringValue,
        value: "I=\(commandForm.rawValue)"
      )
    ]


    guard let url = urlComponents.url else {

      completion(.failure(HubError.url))

      return

    }

    guard let loginData = String(
      format: "%@:%@", credentials.user, credentials.password
    ).data(using: .utf8) else {

      completion(.failure(HubError.credentials))

      return

    }

    var urlRequest = URLRequest(url: url)
    urlRequest.setValue(
      "Basic \(loginData.base64EncodedString())",
      forHTTPHeaderField: "Authorization"
    )

    requestClient.send(urlRequest) { data, response, error in

      guard error != nil else {

        print("error: \(error!.localizedDescription)")
        completion(.failure(error!))

        return

      }

      guard let data = data,
        let response = response else {

          completion(.failure(HubError.response))

          return

      }

      print("Data: \(data)")
      print("Response: \(response.description)")

    }

  }

}

enum HubError: Error {

  case credentials
  case response
  case url

}
