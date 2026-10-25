//
//  HubClient.swift
//
//
//  Created by Brandt Daniels on 4/30/20.
//

import Foundation
import RequestClient

public struct HubClient {

  public var baseUrlComponents: URLComponents {

    var urlComponents = URLComponents()
    urlComponents.scheme = "http"
    urlComponents.host = address.host
    urlComponents.port = address.port

    return urlComponents

  }

  private var credentialData: Data? {

    return String(
      format: "%@:%@", credentials.user, credentials.password
    ).data(using: .utf8)

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

// MARK: - HubClientProtocol

extension HubClient: HubClientProtocol {

  public func send(
    _ hubRequest: HubRequestProtocol,
    completion: @escaping (Result<Data?, Error>)
    -> Void) {

    guard let credentialData = credentialData else {

      completion(.failure(HubClientError.credentials))

      return

    }

    var urlRequest = hubRequest.urlRequest(baseUrlComponents: baseUrlComponents)
    urlRequest.setValue(
      "Basic \(credentialData.base64EncodedString())",
      forHTTPHeaderField: "Authorization"
    )

    requestClient.send(urlRequest) { data, response, error in

      guard error == nil else {

        print("Error: \(error!.localizedDescription)")
        completion(.failure(error!))

        return

      }

      guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {

          completion(.failure(HubClientError.response))

          return

      }

      print("Data: \(String(describing: data))")
      print("Response: \(response.description)")

      completion(.success(data))

    }

  }

}

public enum HubClientError: Error {

  case credentials
  case response

}
