import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends HTTP requests.
///
/// This is the only networking dependency of the Insteon clients. Use
/// ``URLSessionHTTPClient`` by default, conform another HTTP stack to it, or supply a stub in
/// tests. Add cross-cutting behavior, such as authentication, by wrapping a client in a
/// decorator like ``BasicAuthenticationHTTPClient``.
public protocol HTTPClient: Sendable {

  /// Sends a request and returns the response.
  ///
  /// Responses with any status code are returned rather than thrown, so callers can decide
  /// which statuses are errors.
  ///
  /// - Parameter request: The request to send.
  /// - Returns: The response's status, headers and body.
  /// - Throws: An error if no HTTP response was received.
  func send(_ request: URLRequest) async throws -> HTTPResponse

}
