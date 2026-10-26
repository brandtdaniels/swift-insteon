import XCTest
@testable import InsteonNetworking

final class URLSessionHTTPClientTests: XCTestCase {

  var httpClient: URLSessionHTTPClient!

  override func setUp() {

    super.setUp()

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]

    httpClient = URLSessionHTTPClient(session: URLSession(configuration: configuration))

  }

  override func tearDown() {

    StubURLProtocol.stub = nil

    super.tearDown()

  }

  func testDeliversDataAndResponse() {

    let url = URL(string: "http://example.com")!
    let expectedData = Data("body".utf8)

    StubURLProtocol.stub = .success((
      HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
      expectedData
    ))

    let expectation = XCTestExpectation(description: "Send request")

    httpClient.send(URLRequest(url: url)) { result in

      switch result {
      case let .success(response):
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.data, expectedData)
      case .failure:
        XCTFail("Expected success")
      }

      expectation.fulfill()

    }

    wait(for: [expectation], timeout: 1.0)

  }

  func testDeliversError() {

    StubURLProtocol.stub = .failure(URLError(.notConnectedToInternet))

    let expectation = XCTestExpectation(description: "Send request")

    httpClient.send(URLRequest(url: URL(string: "http://example.com")!)) { result in

      switch result {
      case .success:
        XCTFail("Expected failure")
      case let .failure(error):
        XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
      }

      expectation.fulfill()

    }

    wait(for: [expectation], timeout: 1.0)

  }

  static var allTests = [
    ("testDeliversDataAndResponse", testDeliversDataAndResponse),
    ("testDeliversError", testDeliversError)
  ]

}

// MARK: - URLProtocol

final class StubURLProtocol: URLProtocol {

  static var stub: Result<(HTTPURLResponse, Data), Error>?

  override class func canInit(with request: URLRequest) -> Bool {

    return true

  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {

    return request

  }

  override func startLoading() {

    switch StubURLProtocol.stub {
    case let .success((response, data))?:
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    case let .failure(error)?:
      client?.urlProtocol(self, didFailWithError: error)
    case nil:
      client?.urlProtocol(self, didFailWithError: URLError(.unknown))
    }

  }

  override func stopLoading() {}

}
