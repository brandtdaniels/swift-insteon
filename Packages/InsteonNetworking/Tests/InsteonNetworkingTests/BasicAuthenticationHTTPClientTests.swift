import XCTest
@testable import InsteonNetworking

final class BasicAuthenticationHTTPClientTests: XCTestCase {

  func testAddsBasicAuthorizationHeader() {

    let mockHTTPClient = MockHTTPClient(result: .failure(HTTPClientError.nonHTTPResponse))

    let httpClient = BasicAuthenticationHTTPClient(
      mockHTTPClient,
      user: "user",
      password: "password"
    )

    httpClient.send(URLRequest(url: URL(string: "http://example.com")!)) { _ in }

    XCTAssertEqual(
      mockHTTPClient.requests.first?.value(forHTTPHeaderField: "Authorization"),
      "Basic dXNlcjpwYXNzd29yZA=="
    )

  }

  func testForwardsResult() {

    let expectedError = HTTPClientError.nonHTTPResponse

    let httpClient = BasicAuthenticationHTTPClient(
      MockHTTPClient(result: .failure(expectedError)),
      user: "user",
      password: "password"
    )

    var receivedError: Error?

    httpClient.send(URLRequest(url: URL(string: "http://example.com")!)) { result in

      if case let .failure(error) = result {

        receivedError = error

      }

    }

    XCTAssertEqual(receivedError as? HTTPClientError, expectedError)

  }

  static var allTests = [
    ("testAddsBasicAuthorizationHeader", testAddsBasicAuthorizationHeader),
    ("testForwardsResult", testForwardsResult)
  ]

}
