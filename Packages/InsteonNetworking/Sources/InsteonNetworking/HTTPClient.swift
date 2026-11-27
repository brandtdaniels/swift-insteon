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

  /// Sends a request and returns the response's status once it arrives, with the body as it
  /// arrives, for a response that stays open, such as server-sent events.
  ///
  /// Responses with any status code are returned rather than thrown. The body ends when the
  /// server closes it, and throws if the connection fails after the status arrived. Cancel the
  /// reading of the body, or the task that reads it, to close the connection.
  ///
  /// The default throws ``HTTPClientError/streamingUnsupported``.
  ///
  /// - Parameter request: The request to send.
  /// - Returns: The response's status and headers, and its body as chunks.
  /// - Throws: An error if no HTTP response was received.
  func stream(_ request: URLRequest) async throws -> HTTPStreamResponse

}

extension HTTPClient {

  public func stream(_ request: URLRequest) async throws -> HTTPStreamResponse {

    throw HTTPClientError.streamingUnsupported

  }

}

/// A response whose body arrives in pieces, from ``HTTPClient/stream(_:)``.
public struct HTTPStreamResponse: Sendable {

  /// The HTTP status code.
  public var statusCode: Int

  /// The response headers, keyed by lowercased name.
  public private(set) var headers: [String: String]

  /// The body, as the chunks the connection delivers. Reading it ends when the server closes
  /// the body, and throws when the connection fails.
  public var body: AsyncThrowingStream<Data, any Error>

  /// Creates a response.
  ///
  /// - Parameters:
  ///   - statusCode: The HTTP status code.
  ///   - headers: The response headers. Defaults to none. Their names are lowercased.
  ///   - body: The body's chunks.
  public init(statusCode: Int, headers: [String: String] = [:], body: AsyncThrowingStream<Data, any Error>) {

    self.statusCode = statusCode
    let sorted = headers.sorted { $0.key < $1.key }
    self.headers = Dictionary(sorted.map { ($0.key.lowercased(), $0.value) }) { first, _ in first }
    self.body = body

  }

}
