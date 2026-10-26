import Foundation
import InsteonNetworking

/// Decorates an `HTTPClient` with the headers the Insteon API requires,
/// and retries once with a new token when the API rejects the current one.
public struct AuthenticatingHTTPClient {

  private let httpClient: HTTPClient

  private let apiKey: String

  private let tokenProvider: AccessTokenProvider

  public init(
    _ httpClient: HTTPClient,
    apiKey: String,
    tokenProvider: AccessTokenProvider
  ) {

    self.httpClient = httpClient
    self.apiKey = apiKey
    self.tokenProvider = tokenProvider

  }

  private func send(
    _ request: URLRequest,
    retryingRejectedToken: Bool,
    completion: @escaping (Result<HTTPResponse, Error>) -> Void
  ) {

    tokenProvider.accessToken { tokenResult in

      switch tokenResult {

      case let .failure(error):

        completion(.failure(error))

      case let .success(token):

        var authenticatedRequest = request
        authenticatedRequest.setValue("APIKey \(self.apiKey)", forHTTPHeaderField: "Authentication")
        authenticatedRequest.setValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")

        self.httpClient.send(authenticatedRequest) { result in

          if retryingRejectedToken,
            case let .success(response) = result,
            AuthenticatingHTTPClient.isRejectedToken(response) {

            self.tokenProvider.invalidateAccessToken()

            self.send(request, retryingRejectedToken: false, completion: completion)

            return

          }

          completion(result)

        }

      }

    }

  }

  static func isRejectedToken(_ response: HTTPResponse) -> Bool {

    if response.statusCode == 401 {

      return true

    }

    guard let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: response.data) else {

      return false

    }

    return errorResponse.code == ErrorResponse.invalidAccessKeyCode

  }

}

// MARK: - HTTPClient

extension AuthenticatingHTTPClient: HTTPClient {

  public func send(
    _ request: URLRequest,
    completion: @escaping (Result<HTTPResponse, Error>) -> Void
  ) {

    send(request, retryingRejectedToken: true, completion: completion)

  }

}
