//
//  HubClient.swift
//
//
//  Created by Brandt Daniels on 4/30/20.
//

import Foundation
import InsteonNetworking

public struct HubClient {

  public var baseUrlComponents: URLComponents {

    var urlComponents = URLComponents()
    urlComponents.scheme = "http"
    urlComponents.host = address.host
    urlComponents.port = address.port

    return urlComponents

  }

  private let address: SocketAddressProtocol

  private let httpClient: HTTPClient

  /// Sends requests through `httpClient` unchanged, so it is responsible for any authentication the hub needs.
  public init(
    address: SocketAddressProtocol,
    httpClient: HTTPClient
  ) {

    self.address = address
    self.httpClient = httpClient

  }

  /// Authenticates every request to the hub with HTTP basic authentication using `credentials`.
  public init(
    credentials: LoginCredentialsProtocol,
    address: SocketAddressProtocol,
    httpClient: HTTPClient
  ) {

    self.init(
      address: address,
      httpClient: BasicAuthenticationHTTPClient(
        httpClient,
        user: credentials.user,
        password: credentials.password
      )
    )

  }

}

// MARK: - HubClientProtocol

extension HubClient: HubClientProtocol {

  public func send(
    _ hubRequest: HubRequestProtocol,
    completion: @escaping (Result<Data, Error>)
    -> Void) {

    let urlRequest = hubRequest.urlRequest(baseUrlComponents: baseUrlComponents)

    httpClient.send(urlRequest) { result in

      switch result {

      case let .failure(error):

        completion(.failure(error))

      case let .success(response):

        guard response.isSuccess else {

          completion(.failure(HubClientError.response(statusCode: response.statusCode)))

          return

        }

        completion(.success(response.data))

      }

    }

  }

}

public enum HubClientError: Error, Equatable {

  case response(statusCode: Int)

}
