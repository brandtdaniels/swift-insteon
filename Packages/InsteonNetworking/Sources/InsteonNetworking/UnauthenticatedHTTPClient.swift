import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// An ``HTTPClient`` that never sends credentials, for requests to addresses that mustn't
/// receive a Hub's user name and password, such as every address Hub discovery asks, or
/// Insteon's servers.
///
/// It's made only from a ``URLSessionHTTPClient``, so a client that adds credentials, such as
/// ``BasicAuthenticationHTTPClient`` or a decorator around one, can't stand in for it where
/// this type is required. It checks every request as well, and refuses one that carries
/// credentials with ``HTTPClientError/credentialsRefused`` before it's sent: a request with an
/// `Authorization` header or a user name or password in its URL, and any request when the
/// session's configuration adds an `Authorization` header to every request or has a credential
/// storage, whose saved credentials the session could answer a server's challenge with.
/// ``URLSessionHTTPClient/localNetwork(maximumResponseSize:resourceTimeout:)`` and
/// ``URLSessionHTTPClient/ephemeral(redirectPolicy:maximumResponseSize:resourceTimeout:)``
/// make sessions without one.
///
/// ```swift
/// let discovery = HubDiscovery(httpClient: .localNetwork())
/// ```
public struct UnauthenticatedHTTPClient: HTTPClient {

  private let transport: any HTTPClient

  /// Whether the transport's session adds an `Authorization` header to every request, or
  /// could answer a challenge with saved credentials, so every request is refused.
  private let sessionAddsCredentials: Bool

  /// Creates a client that sends requests with a `URLSession` client.
  ///
  /// - Parameter client: The client to send the requests with. If its session's
  ///   configuration adds an `Authorization` header to every request, or has a credential
  ///   storage, as `URLSession.shared` and `URLSessionConfiguration.ephemeral` do, every
  ///   request is refused.
  public init(_ client: URLSessionHTTPClient) {

    transport = client
    sessionAddsCredentials = client.sessionAddsCredentials || client.sessionStoresCredentials

  }

  /// Creates a client that sends requests with any client, for tests in this package, whose
  /// stand-ins answer as a server would.
  ///
  /// - Parameter transport: The client to send the requests with.
  package init(transport: any HTTPClient) {

    self.transport = transport
    sessionAddsCredentials = false

  }

  /// Makes a client for devices on the local network, as
  /// ``URLSessionHTTPClient/localNetwork(maximumResponseSize:resourceTimeout:)`` does: it
  /// goes to each device directly, never through a proxy, keeps nothing between requests,
  /// follows no redirects and reads a limited answer.
  ///
  /// - Parameters:
  ///   - maximumResponseSize: The most bytes of an answer's body to read. Defaults to
  ///     ``URLSessionHTTPClient/localNetworkMaximumResponseSize``.
  ///   - resourceTimeout: How long a request may take in all. Defaults to
  ///     ``URLSessionHTTPClient/localNetworkResourceTimeout``.
  /// - Returns: The client.
  public static func localNetwork(
    maximumResponseSize: Int = URLSessionHTTPClient.localNetworkMaximumResponseSize,
    resourceTimeout: Duration = URLSessionHTTPClient.localNetworkResourceTimeout
  ) -> UnauthenticatedHTTPClient {

    UnauthenticatedHTTPClient(URLSessionHTTPClient.localNetwork(maximumResponseSize: maximumResponseSize, resourceTimeout: resourceTimeout))

  }

  /// Sends a request that carries no credentials.
  ///
  /// - Parameter request: The request to send.
  /// - Returns: The response.
  /// - Throws: ``HTTPClientError/credentialsRefused`` before anything is sent if the request
  ///   carries credentials or the session adds them, or the wrapped client's error.
  public func send(_ request: URLRequest) async throws -> HTTPResponse {

    guard !sessionAddsCredentials, !Self.carriesCredentials(request) else {

      throw HTTPClientError.credentialsRefused

    }

    return try await transport.send(request)

  }

  /// Whether a request carries credentials of its own: an `Authorization` header, or a user
  /// name or password in its URL.
  static func carriesCredentials(_ request: URLRequest) -> Bool {

    request.value(forHTTPHeaderField: "Authorization") != nil || request.url?.user != nil || request.url?.password != nil

  }

}
