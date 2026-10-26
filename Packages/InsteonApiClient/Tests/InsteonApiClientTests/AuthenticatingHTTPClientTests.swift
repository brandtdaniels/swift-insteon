import XCTest
@testable import InsteonApiClient
import InsteonNetworking

final class AuthenticatingHTTPClientTests: XCTestCase {

  let request = URLRequest(url: URL(string: "https://example.com/houses")!)

  let token = AccessToken(value: "token", expiresAt: .distantFuture)

  func testAddsApiKeyAndBearerHeaders() {

    let mockHTTPClient = MockHTTPClient(results: [.success(httpResponse(statusCode: 200))])

    let httpClient = AuthenticatingHTTPClient(
      mockHTTPClient,
      apiKey: "key",
      tokenProvider: MockAccessTokenProvider(tokens: [token])
    )

    httpClient.send(request) { _ in }

    XCTAssertEqual(mockHTTPClient.requests.first?.value(forHTTPHeaderField: "Authentication"), "APIKey key")
    XCTAssertEqual(mockHTTPClient.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer token")

  }

  func testRetriesOnceWithNewTokenWhenTokenIsRejected() {

    let mockHTTPClient = MockHTTPClient(results: [
      .success(httpResponse(statusCode: 400, body: #"{"code": 4014, "message": "Invalid access key"}"#)),
      .success(httpResponse(statusCode: 200))
    ])

    let tokenProvider = MockAccessTokenProvider(tokens: [
      token,
      AccessToken(value: "new-token", expiresAt: .distantFuture)
    ])

    let httpClient = AuthenticatingHTTPClient(mockHTTPClient, apiKey: "key", tokenProvider: tokenProvider)

    var receivedStatusCode: Int?

    httpClient.send(request) { result in

      receivedStatusCode = try? result.get().statusCode

    }

    XCTAssertEqual(tokenProvider.invalidateCallCount, 1)
    XCTAssertEqual(mockHTTPClient.requests.count, 2)
    XCTAssertEqual(mockHTTPClient.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer new-token")
    XCTAssertEqual(receivedStatusCode, 200)

  }

  func testDoesNotRetryMoreThanOnce() {

    let mockHTTPClient = MockHTTPClient(results: [.success(httpResponse(statusCode: 401))])

    let tokenProvider = MockAccessTokenProvider(tokens: [token])

    let httpClient = AuthenticatingHTTPClient(mockHTTPClient, apiKey: "key", tokenProvider: tokenProvider)

    var receivedStatusCode: Int?

    httpClient.send(request) { result in

      receivedStatusCode = try? result.get().statusCode

    }

    XCTAssertEqual(mockHTTPClient.requests.count, 2)
    XCTAssertEqual(receivedStatusCode, 401)

  }

  func testPropagatesTokenProviderError() {

    let mockHTTPClient = MockHTTPClient(results: [.success(httpResponse(statusCode: 200))])

    let httpClient = AuthenticatingHTTPClient(
      mockHTTPClient,
      apiKey: "key",
      tokenProvider: MockAccessTokenProvider(error: TestError.failed)
    )

    var receivedError: Error?

    httpClient.send(request) { result in

      if case let .failure(error) = result {

        receivedError = error

      }

    }

    XCTAssertEqual(receivedError as? TestError, .failed)
    XCTAssertTrue(mockHTTPClient.requests.isEmpty)

  }

  static var allTests = [
    ("testAddsApiKeyAndBearerHeaders", testAddsApiKeyAndBearerHeaders),
    ("testRetriesOnceWithNewTokenWhenTokenIsRejected", testRetriesOnceWithNewTokenWhenTokenIsRejected),
    ("testDoesNotRetryMoreThanOnce", testDoesNotRetryMoreThanOnce),
    ("testPropagatesTokenProviderError", testPropagatesTokenProviderError)
  ]

}
