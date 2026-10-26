import XCTest
@testable import InsteonHubClient
import InsteonNetworking
import InsteonSerialCommand

final class InsteonHubClientTests: XCTestCase {

  let address = SocketAddress(
    host: "example.com",
    port: 25105
  )

  let credentials = LoginCredentials(
    user: "user",
    password: "password"
  )

  let hubRequest = SerialCommandRequest(SerialCommand(.cancelAllLinking))

  func testHTTPClientInteraction() {

    let mockHTTPClient = MockHTTPClient(result: .success(response(statusCode: 200)))

    let hubClient = HubClient(address: address, httpClient: mockHTTPClient)

    hubClient.send(hubRequest) { _ in }

    XCTAssertEqual(mockHTTPClient.requests.count, 1)
    XCTAssertEqual(mockHTTPClient.requests.first?.url?.host, "example.com")
    XCTAssertEqual(mockHTTPClient.requests.first?.url?.port, 25105)

  }

  func testCredentialsAddBasicAuthorization() {

    let mockHTTPClient = MockHTTPClient(result: .success(response(statusCode: 200)))

    let hubClient = HubClient(
      credentials: credentials,
      address: address,
      httpClient: mockHTTPClient
    )

    hubClient.send(hubRequest) { _ in }

    XCTAssertEqual(
      mockHTTPClient.requests.first?.value(forHTTPHeaderField: "Authorization"),
      "Basic dXNlcjpwYXNzd29yZA=="
    )

  }

  func testHTTPClientError() {

    let expectedError = HTTPClientError.nonHTTPResponse

    let hubClient = HubClient(
      address: address,
      httpClient: MockHTTPClient(result: .failure(expectedError))
    )

    let result = send(hubRequest, with: hubClient)

    switch result {
    case .success?:
      XCTFail("No error thrown")
    case let .failure(error)?:
      XCTAssertEqual(error as? HTTPClientError, expectedError)
    case nil:
      XCTFail("No result")
    }

  }

  func testHTTPClientResponseError() {

    let hubClient = HubClient(
      address: address,
      httpClient: MockHTTPClient(result: .success(response(statusCode: 400)))
    )

    let result = send(hubRequest, with: hubClient)

    switch result {
    case .success?:
      XCTFail("No error thrown")
    case let .failure(error)?:
      XCTAssertEqual(error as? HubClientError, .response(statusCode: 400))
    case nil:
      XCTFail("No result")
    }

  }

  func testHTTPClientSuccess() {

    let expectedData = Data("response".utf8)

    let hubClient = HubClient(
      address: address,
      httpClient: MockHTTPClient(result: .success(response(statusCode: 200, data: expectedData)))
    )

    let result = send(hubRequest, with: hubClient)

    switch result {
    case let .success(data)?:
      XCTAssertEqual(data, expectedData)
    case .failure?:
      XCTFail("Error thrown")
    case nil:
      XCTFail("No result")
    }

  }

  private func send(_ hubRequest: HubRequestProtocol, with hubClient: HubClient) -> Result<Data, Error>? {

    var receivedResult: Result<Data, Error>?

    hubClient.send(hubRequest) { result in

      receivedResult = result

    }

    return receivedResult

  }

  private func response(statusCode: Int, data: Data = Data()) -> HTTPResponse {

    return HTTPResponse(
      data: data,
      response: HTTPURLResponse(
        url: URL(string: "http://example.com")!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
      )!
    )

  }

  static var allTests = [
    ("testHTTPClientInteraction", testHTTPClientInteraction),
    ("testCredentialsAddBasicAuthorization", testCredentialsAddBasicAuthorization),
    ("testHTTPClientError", testHTTPClientError),
    ("testHTTPClientResponseError", testHTTPClientResponseError),
    ("testHTTPClientSuccess", testHTTPClientSuccess)
  ]

}

// MARK: - HTTPClient

final class MockHTTPClient: HTTPClient {

  private(set) var requests: [URLRequest] = []

  private let result: Result<HTTPResponse, Error>

  init(result: Result<HTTPResponse, Error>) {

    self.result = result

  }

  func send(
    _ request: URLRequest,
    completion: @escaping (Result<HTTPResponse, Error>) -> Void
  ) {

    requests.append(request)

    completion(result)

  }

}
