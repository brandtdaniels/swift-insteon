import XCTest
@testable import InsteonApiClient
import InsteonNetworking

final class ApiClientTests: XCTestCase {

  func testDecodesSuccessfulResponse() {

    let result = send(GetTestRoomId(), returning: .success(httpResponse(statusCode: 200, body: #"{"RoomID": 7}"#)))

    XCTAssertEqual(try result?.get(), RoomId(7))

  }

  func testDecodesResponseContainingNewlines() {

    let result = send(GetTestRoomId(), returning: .success(httpResponse(statusCode: 201, body: "{\n\"RoomID\": 7\n}")))

    XCTAssertEqual(try result?.get(), RoomId(7))

  }

  func testResponselessRequestSucceedsOnNoContent() {

    let apiClient = ApiClient(httpClient: MockHTTPClient(results: [.success(httpResponse(statusCode: 204))]))

    var succeeded = false

    apiClient.request(DeleteRoom(roomId: 7)) { result in

      if case .success = result {

        succeeded = true

      }

    }

    XCTAssertTrue(succeeded)

  }

  func testMapsServerError() {

    let result = send(GetTestRoomId(), returning: .success(httpResponse(statusCode: 400, body: #"{"code": 4001, "message": "Bad request"}"#)))

    guard case let .failure(.server(code, message))? = result else {

      return XCTFail("Expected server error, got \(String(describing: result))")

    }

    XCTAssertEqual(code, 4001)
    XCTAssertEqual(message, "Bad request")

  }

  func testMapsUndecodableErrorToUnknown() {

    let result = send(GetTestRoomId(), returning: .success(httpResponse(statusCode: 500, body: "Internal Server Error")))

    guard case .failure(.unknown)? = result else {

      return XCTFail("Expected unknown error, got \(String(describing: result))")

    }

  }

  func testMapsDecodingError() {

    let result = send(GetTestRoomId(), returning: .success(httpResponse(statusCode: 200, body: "not json")))

    guard case .failure(.decoding)? = result else {

      return XCTFail("Expected decoding error, got \(String(describing: result))")

    }

  }

  func testMapsTransportError() {

    let result = send(GetTestRoomId(), returning: .failure(TestError.failed))

    guard case .failure(.request)? = result else {

      return XCTFail("Expected request error, got \(String(describing: result))")

    }

  }

  func testConvenienceInitializerAuthenticatesRequests() {

    let mockHTTPClient = MockHTTPClient(results: [.success(httpResponse(statusCode: 200, body: #"{"RoomID": 7}"#))])

    let apiClient = ApiClient(
      apiKey: "key",
      tokenProvider: MockAccessTokenProvider(tokens: [AccessToken(value: "token", expiresAt: .distantFuture)]),
      httpClient: mockHTTPClient
    )

    apiClient.request(GetTestRoomId()) { _ in }

    XCTAssertEqual(mockHTTPClient.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer token")

  }

  private func send(
    _ request: GetTestRoomId,
    returning result: Result<HTTPResponse, Error>
  ) -> Result<RoomId, ApiClientError>? {

    let apiClient = ApiClient(httpClient: MockHTTPClient(results: [result]))

    var receivedResult: Result<RoomId, ApiClientError>?

    apiClient.request(request) { result in

      receivedResult = result

    }

    return receivedResult

  }

  static var allTests = [
    ("testDecodesSuccessfulResponse", testDecodesSuccessfulResponse),
    ("testDecodesResponseContainingNewlines", testDecodesResponseContainingNewlines),
    ("testResponselessRequestSucceedsOnNoContent", testResponselessRequestSucceedsOnNoContent),
    ("testMapsServerError", testMapsServerError),
    ("testMapsUndecodableErrorToUnknown", testMapsUndecodableErrorToUnknown),
    ("testMapsDecodingError", testMapsDecodingError),
    ("testMapsTransportError", testMapsTransportError),
    ("testConvenienceInitializerAuthenticatesRequests", testConvenienceInitializerAuthenticatesRequests)
  ]

}

struct GetTestRoomId: RequestProtocol {

  typealias Response = RoomId

  var urlRequest: URLRequest {

    return URLRequest(url: URL(string: "https://example.com/rooms")!)

  }

}
