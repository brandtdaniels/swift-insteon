import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonNetworking

/// Records requests and answers them with a fixed response.
actor StubHTTPClient: HTTPClient {

  private(set) var requests: [URLRequest] = []

  private let response: HTTPResponse

  init(response: HTTPResponse = HTTPResponse(statusCode: 200)) {

    self.response = response

  }

  func send(_ request: URLRequest) async throws -> HTTPResponse {

    requests.append(request)

    return response

  }

}
