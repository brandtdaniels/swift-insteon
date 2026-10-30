import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Decorates an ``HTTPClient`` by adding an HTTP basic `Authorization` header to every request.
///
/// Basic authentication encodes the user name and password reversibly. Insteon Hubs serve their
/// local interface over plain HTTP, so anyone who can see the network traffic can read them;
/// keep the Hub on a trusted network.
///
/// The header is part of every request, so it goes wherever the wrapped client sends the
/// request. A ``URLSessionHTTPClient`` never follows a redirect for a request with an
/// `Authorization` header: it throws ``HTTPClientError/redirectRefused`` instead, so the
/// credentials reach only the host the request named. A Hub never redirects its own requests.
/// Another ``HTTPClient`` wrapped here must refuse redirects the same way. Use this client only
/// with hosts you trust, such as a Hub on your own network. The client keeps the encoded
/// credentials in memory for as long as it exists.
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
  ///   - httpClient: The client that sends the authenticated requests. It must not follow
  ///     redirects for them, as a ``URLSessionHTTPClient`` doesn't.
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
  /// - Throws: The wrapped client's error, such as ``HTTPClientError/redirectRefused`` from a
  ///   ``URLSessionHTTPClient`` when the server answers with a redirect.
  public func send(_ request: URLRequest) async throws -> HTTPResponse {

    var request = request
    request.setValue(authorization, forHTTPHeaderField: "Authorization")

    return try await httpClient.send(request)

  }

}

// MARK: - Redaction

extension BasicAuthenticationHTTPClient: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {

  /// A description that leaves out the credentials, so logging the client doesn't reveal them.
  public var description: String {

    "BasicAuthenticationHTTPClient(httpClient: \(httpClient), authorization: <redacted>)"

  }

  /// The same description as ``BasicAuthenticationHTTPClient/description``.
  public var debugDescription: String {

    description

  }

  /// A mirror that shows the wrapped client but not the credentials, for `dump` and debuggers.
  public var customMirror: Mirror {

    Mirror(self, children: ["httpClient": httpClient], displayStyle: .struct)

  }

}
