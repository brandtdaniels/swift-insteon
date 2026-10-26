import Foundation
@testable import InsteonApiClient
import InsteonNetworking

final class MockHTTPClient: HTTPClient {

  private(set) var requests: [URLRequest] = []

  private var results: [Result<HTTPResponse, Error>]

  /// Returns `results` in order, repeating the last one once the others are used up.
  init(results: [Result<HTTPResponse, Error>]) {

    self.results = results

  }

  func send(
    _ request: URLRequest,
    completion: @escaping (Result<HTTPResponse, Error>) -> Void
  ) {

    requests.append(request)

    completion(results.count > 1 ? results.removeFirst() : results[0])

  }

}

final class MockAccessTokenProvider: AccessTokenProvider {

  private(set) var invalidateCallCount = 0

  private var tokens: [AccessToken]

  private let error: Error?

  init(tokens: [AccessToken] = [], error: Error? = nil) {

    self.tokens = tokens
    self.error = error

  }

  func accessToken(completion: @escaping (Result<AccessToken, Error>) -> Void) {

    if let error = error {

      completion(.failure(error))

    } else {

      completion(.success(tokens.count > 1 ? tokens.removeFirst() : tokens[0]))

    }

  }

  func invalidateAccessToken() {

    invalidateCallCount += 1

  }

}

final class MockTokenAuthorizer: TokenAuthorizer {

  private(set) var authorizeCallCount = 0

  private(set) var refreshedTokens: [AccessToken] = []

  var authorizeResult: Result<AccessToken, Error> = .failure(TestError.unexpectedCall)

  var refreshResult: Result<AccessToken, Error> = .failure(TestError.unexpectedCall)

  func authorize(completion: @escaping (Result<AccessToken, Error>) -> Void) {

    authorizeCallCount += 1

    completion(authorizeResult)

  }

  func refresh(
    _ token: AccessToken,
    completion: @escaping (Result<AccessToken, Error>) -> Void
  ) {

    refreshedTokens.append(token)

    completion(refreshResult)

  }

}

enum TestError: Error, Equatable {

  case unexpectedCall

  case failed

}

func httpResponse(statusCode: Int, body: String = "") -> HTTPResponse {

  return HTTPResponse(
    data: Data(body.utf8),
    response: HTTPURLResponse(
      url: URL(string: "https://example.com")!,
      statusCode: statusCode,
      httpVersion: nil,
      headerFields: nil
    )!
  )

}
