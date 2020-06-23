import XCTest
@testable import InsteonHubClient
import RequestClient
import InsteonSerialCommand

final class InsteonHubClientTests: XCTestCase {

  var hubClient: HubClientProtocol!

  var mockRequestClient: MockRequestClient!

  override func setUp() {

    mockRequestClient = MockRequestClient()

    let credentials = LoginCredentials(
      user: "",
      password: ""
    )
    let address = SocketAddress(
      host: "example.com",
      port: 80
    )

    hubClient = HubClient(
      credentials: credentials,
      address: address,
      requestClient: mockRequestClient
    )

  }

  func testRequestClientInteraction() {

    let expectation = XCTestExpectation(
      description: "Send hub command"
    )

    let serialCommand = SerialCommand(.cancelAllLinking)

    let hubRequest = SerialCommandRequest(serialCommand)

    hubClient.send(hubRequest) { result in

      XCTAssertEqual(
        self.mockRequestClient.sendCallCount,
        1
      )

      expectation.fulfill()

    }

    wait(for: [expectation], timeout: 1.0)

  }

  func testRequestClientError() {

    let expectedError = HubClientError.response

    mockRequestClient = MockRequestClient(error: expectedError)

    let credentials = LoginCredentials(
      user: "",
      password: ""
    )
    let address = SocketAddress(
      host: "example.com",
      port: 80
    )

    hubClient = HubClient(
      credentials: credentials,
      address: address,
      requestClient: mockRequestClient
    )

    let expectation = XCTestExpectation(
      description: "Send hub command"
    )

    let serialCommand = SerialCommand(.cancelAllLinking)

    let hubRequest = SerialCommandRequest(serialCommand)

    hubClient.send(hubRequest) { result in

      switch result {
      case .success:
        XCTFail("No error thrown")
      case let .failure(error):
        XCTAssertEqual(
          error as? HubClientError,
          expectedError
        )
      }

      expectation.fulfill()

    }

    wait(for: [expectation], timeout: 1.0)

  }

  func testRequestClientResponseError() {

    let response = HTTPURLResponse(
      url: URL(string: "example.com")!,
      statusCode: 400,
      httpVersion: nil,
      headerFields: nil
    )

    mockRequestClient = MockRequestClient(response: response)

    let credentials = LoginCredentials(
      user: "",
      password: ""
    )
    let address = SocketAddress(
      host: "example.com",
      port: 80
    )

    hubClient = HubClient(
      credentials: credentials,
      address: address,
      requestClient: mockRequestClient
    )

    let expectation = XCTestExpectation(
      description: "Send hub command"
    )

    let serialCommand = SerialCommand(.cancelAllLinking)

    let hubRequest = SerialCommandRequest(serialCommand)

    hubClient.send(hubRequest) { result in

      switch result {
      case .success:
        XCTFail("No error thrown")
      case let .failure(error):
        XCTAssertEqual(
          error as? HubClientError,
          HubClientError.response
        )
      }

      expectation.fulfill()

    }

    wait(for: [expectation], timeout: 1.0)

  }

  func testRequestClientSuccess() {

    let expectedData = Data()
    let response = HTTPURLResponse(
      url: URL(string: "example.com")!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: nil
    )

    mockRequestClient = MockRequestClient(data: expectedData, response: response)

    let credentials = LoginCredentials(
      user: "",
      password: ""
    )
    let address = SocketAddress(
      host: "example.com",
      port: 80
    )

    hubClient = HubClient(
      credentials: credentials,
      address: address,
      requestClient: mockRequestClient
    )

    let expectation = XCTestExpectation(
      description: "Send hub command"
    )

    let serialCommand = SerialCommand(.cancelAllLinking)

    let hubRequest = SerialCommandRequest(serialCommand)

    hubClient.send(hubRequest) { result in

      switch result {
      case let .success(data):
        XCTAssertEqual(data, expectedData)
      case .failure(_):
        XCTFail("Error thrown")
      }

      expectation.fulfill()

    }

    wait(for: [expectation], timeout: 1.0)

  }

  static var allTests = [
    ("testRequestClientInteraction", testRequestClientInteraction),
    ("testRequestClientError", testRequestClientError),
    ("testRequestClientResponseError", testRequestClientResponseError),
    ("testRequestClientSuccess", testRequestClientSuccess)
  ]

}

// MARK: - RequestClientProtocol

class MockRequestClient: RequestClientProtocol {

  private(set) var sendCallCount = 0

  private let data: Data?

  private let response: URLResponse?

  private let error: Error?

  init(data: Data? = nil, response: URLResponse? = nil, error: Error? = nil) {

    self.data = data
    self.response = response
    self.error = error

  }

  func send(_ request: URLRequest, completion: @escaping (Data?, URLResponse?, Error?) -> Void) {

    sendCallCount += 1

    completion(data, response, error)

  }

}
