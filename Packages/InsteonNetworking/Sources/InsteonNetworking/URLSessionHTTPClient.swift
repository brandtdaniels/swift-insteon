import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Adapts `URLSession` to ``HTTPClient``.
public final class URLSessionHTTPClient: HTTPClient, @unchecked Sendable {

  // `URLSession` is thread-safe; it isn't marked `Sendable` on every platform.
  private let session: URLSession

  /// Creates a client that sends requests with a session.
  ///
  /// - Parameter session: The session to send requests with. Defaults to the shared session.
  public init(session: URLSession = .shared) {

    self.session = session

  }

  /// Sends a request with the session.
  ///
  /// - Parameter request: The request to send.
  /// - Returns: The response's status, headers and body.
  /// - Throws: The session's error if the request failed, or
  ///   ``HTTPClientError/nonHTTPResponse`` if the response wasn't HTTP.
  public func send(_ request: URLRequest) async throws -> HTTPResponse {

    let (data, response) = try await data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {

      throw HTTPClientError.nonHTTPResponse

    }

    var headers: [String: String] = [:]

    for case let (name as String, value as String) in httpResponse.allHeaderFields {

      headers[name] = value

    }

    return HTTPResponse(statusCode: httpResponse.statusCode, headers: headers, body: data)

  }

  private func data(for request: URLRequest) async throws -> (Data, URLResponse) {

    #if canImport(FoundationNetworking)
    // swift-corelibs-foundation lacks a cancelable async API, so bridge the completion handler.
    return try await withCheckedThrowingContinuation { continuation in

      session.dataTask(with: request) { data, response, error in

        if let error {

          continuation.resume(throwing: error)

        } else if let response {

          continuation.resume(returning: (data ?? Data(), response))

        } else {

          continuation.resume(throwing: HTTPClientError.nonHTTPResponse)

        }

      }.resume()

    }
    #else
    return try await session.data(for: request)
    #endif

  }

}
