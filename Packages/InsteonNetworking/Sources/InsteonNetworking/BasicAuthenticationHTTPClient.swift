import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Decorates an ``HTTPClient`` by adding an HTTP basic `Authorization` header to every request.
///
/// ```swift
/// let client = BasicAuthenticationHTTPClient(
///   URLSessionHTTPClient(),
///   user: username,
///   password: password
/// )
/// ```
public struct BasicAuthenticationHTTPClient: HTTPClient {

  private let httpClient: any HTTPClient

  private let authorization: String

  /// Creates a client that authenticates requests before passing them on.
  ///
  /// - Parameters:
  ///   - httpClient: The client that sends the authenticated requests.
  ///   - user: The user name.
  ///   - password: The password.
  public init(_ httpClient: any HTTPClient, user: String, password: String) {

    self.httpClient = httpClient
    authorization = "Basic " + Data("\(user):\(password)".utf8).base64EncodedString()

  }

  /// Adds the `Authorization` header and sends the request with the wrapped client.
  ///
  /// - Parameter request: The request to authenticate and send.
  /// - Returns: The wrapped client's response.
  /// - Throws: The wrapped client's error.
  public func send(_ request: URLRequest) async throws -> HTTPResponse {

    var request = request
    request.setValue(authorization, forHTTPHeaderField: "Authorization")

    return try await httpClient.send(request)

  }

}
