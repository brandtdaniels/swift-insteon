import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonNetworking

/// An ``HTTPClient`` that records requests and answers each with a fixed response.
public actor StubHTTPClient: HTTPClient {

  /// The requests sent so far, oldest first.
  public private(set) var requests: [URLRequest] = []

  private let response: HTTPResponse

  /// Creates a client that answers every request with a response.
  ///
  /// - Parameter response: The response to answer with. Defaults to an empty `200 OK`.
  public init(response: HTTPResponse = HTTPResponse(statusCode: 200)) {

    self.response = response

  }

  /// Records a request and returns the fixed response.
  ///
  /// - Parameter request: The request.
  /// - Returns: The fixed response.
  public func send(_ request: URLRequest) async throws -> HTTPResponse {

    requests.append(request)

    return response

  }

}
