import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonNetworking

/// The local HTTP interface of a Hub 2245 or Hub 2242.
///
/// The Hub passes bytes to its built-in modem and collects the modem's replies in a buffer.
/// These are the Hub's requests, with no pacing or retries; to send commands, wrap the Hub in a
/// ``HubConnection`` and drive it with a `Modem`, as you would a USB modem. A Hub 2242 also
/// runs timers, which ``Hub/setTimer(_:for:)`` and the methods beside it write.
///
/// The Hub requires HTTP basic authentication with the user name and password printed on it.
/// ``Hub/init(endpoint:user:password:httpClient:requestTimeout:clock:)`` adds it for you; to
/// authenticate another way, pass an already-authenticated client to
/// ``Hub/init(endpoint:httpClient:requestTimeout:clock:)``. The Hub's interface is plain HTTP, so the
/// credentials are readable on the network: keep the Hub on a network you trust.
///
/// A Hub never redirects its own requests. With the default `URLSessionHTTPClient`, a request
/// carrying the credentials that's answered with a redirect isn't followed and throws
/// `HTTPClientError.redirectRefused`, so the credentials reach only the Hub's address. A client
/// of your own must refuse redirects for these requests too.
///
/// The default client is `URLSessionHTTPClient.localNetwork()`, whose session goes to the Hub
/// directly rather than through a proxy, which would read the credentials, and keeps no
/// cookies, credentials or cache. On Linux, where the environment's proxy can't be turned off,
/// it refuses a request a proxy would carry with `HTTPClientError.proxyConfigured`.
///
/// Each request gives up after ``Hub/requestTimeout`` in all, so a Hub that doesn't answer, or
/// answers a byte at a time, fails in seconds rather than after `URLRequest`'s default of a
/// minute between bytes. A page larger than ``Hub/maximumResponseSize`` fails with
/// `HTTPClientError.responseTooLarge(limit:)`.
///
/// `Hub` sends the credentials to whatever address its endpoint names. A front end that takes
/// the address from a person should check it first, as `ModemSession.withHub` in InsteonCore
/// does, sending them only to a private IPv4 address.
public struct Hub: Sendable {

  /// How long each request waits for the Hub by default: 5 seconds.
  ///
  /// A Hub on the local network answers in well under a second, since every request is a short
  /// GET that returns a small page, such as the buffer, and no request waits for an Insteon
  /// device: the modem's replies arrive in the buffer later.
  public static let defaultRequestTimeout: Duration = .seconds(5)

  /// The largest page the Hub's answer may be: 64 KiB.
  ///
  /// The buffer page is under 1 KiB, and a Hub 2242's slot page a few KiB.
  public static let maximumResponseSize: Int = 64 * 1024

  /// How long each request may take in all before it fails.
  public let requestTimeout: Duration

  private let endpoint: HubEndpoint

  private let httpClient: any HTTPClient

  private let clock: any Clock<Duration>

  /// Creates a Hub interface that sends requests through a client as-is.
  ///
  /// - Parameters:
  ///   - endpoint: Where the Hub can be reached.
  ///   - httpClient: The client to send requests with. It must authenticate them, and must
  ///     not follow redirects for them, as `URLSessionHTTPClient` doesn't for a request with
  ///     an `Authorization` header.
  ///   - requestTimeout: How long each request may take in all before it fails. Defaults to
  ///     ``Hub/defaultRequestTimeout``.
  ///   - clock: The clock that times each request. Defaults to a `ContinuousClock`; tests can
  ///     pass a clock they control.
  public init(
    endpoint: HubEndpoint,
    httpClient: any HTTPClient,
    requestTimeout: Duration = Hub.defaultRequestTimeout,
    clock: any Clock<Duration> = ContinuousClock()
  ) {

    self.endpoint = endpoint
    self.httpClient = httpClient
    self.requestTimeout = requestTimeout
    self.clock = clock

  }

  /// Creates a Hub interface that authenticates with the Hub's user name and password.
  ///
  /// - Parameters:
  ///   - endpoint: Where the Hub can be reached.
  ///   - user: The Hub's user name.
  ///   - password: The Hub's password.
  ///   - httpClient: The client to send requests with, before the credentials are added.
  ///     Defaults to `URLSessionHTTPClient.localNetwork()`, which uses no proxy, keeps
  ///     nothing between requests, and refuses redirects for these requests, throwing
  ///     `HTTPClientError.redirectRefused`. Another client must refuse them too.
  ///   - requestTimeout: How long each request may take in all before it fails. Defaults to
  ///     ``Hub/defaultRequestTimeout``.
  ///   - clock: The clock that times each request. Defaults to a `ContinuousClock`.
  public init(
    endpoint: HubEndpoint,
    user: String,
    password: String,
    httpClient: any HTTPClient = URLSessionHTTPClient.localNetwork(),
    requestTimeout: Duration = Hub.defaultRequestTimeout,
    clock: any Clock<Duration> = ContinuousClock()
  ) {

    self.init(
      endpoint: endpoint,
      httpClient: BasicAuthenticationHTTPClient(httpClient, user: user, password: password),
      requestTimeout: requestTimeout,
      clock: clock
    )

  }

  /// Passes bytes, such as a serial command, to the Hub's modem.
  ///
  /// The Hub starts its buffer over, and the modem's reply, such as the command's echo or the
  /// requested data, arrives in it.
  ///
  /// - Parameter bytes: The bytes to send.
  /// - Throws: ``HubError`` if the Hub rejected the request, or the HTTP client's error.
  public func write(_ bytes: [UInt8]) async throws {

    _ = try await perform(.write(bytes))

  }

  /// Sends a command a Hub 2242 runs itself, in its short form.
  ///
  /// The Hub's modem echoes the serial command it sends for it into the buffer, such as
  /// `02 61 01 11 01 06` for On to group 1, and devices' cleanup acknowledgments follow.
  ///
  /// - Parameter command: The command.
  /// - Throws: ``HubError`` if the Hub rejected the request, or the HTTP client's error.
  public func send(_ command: HubShortCommand) async throws {

    _ = try await perform(.shortCommand(command))

  }

  /// Reads the buffer of bytes the modem has sent back.
  ///
  /// - Returns: The Hub's buffer.
  /// - Throws: ``HubError`` if the Hub rejected the request or the buffer couldn't be parsed,
  ///   or the HTTP client's error.
  public func readBuffer() async throws -> HubBuffer {

    let response = try await perform(.readBuffer)

    return try HubBuffer(response: String(decoding: response.body, as: UTF8.self))

  }

  /// Clears the buffer of bytes the modem has sent back.
  ///
  /// Reset any ``HubBufferCursor`` afterwards.
  ///
  /// - Throws: ``HubError`` if the Hub rejected the request, or the HTTP client's error.
  public func clearBuffer() async throws {

    _ = try await perform(.clearBuffer)

  }

  /// Sends a request and checks the answer.
  ///
  /// - Throws: `URLError(.timedOut)` if the request takes longer than
  ///   ``Hub/requestTimeout`` in all, `HTTPClientError.responseTooLarge(limit:)` for a page
  ///   larger than ``Hub/maximumResponseSize``, ``HubError/unexpectedStatus(_:)`` for a
  ///   status that isn't 2xx, or the HTTP client's error.
  func perform(_ request: HubRequest) async throws -> HTTPResponse {

    let urlRequest: URLRequest = try request.urlRequest(for: endpoint, timeout: requestTimeout)
    let httpClient: any HTTPClient = httpClient

    // The request's own timeout limits only the wait between bytes, so the whole request is
    // limited too.
    let response: HTTPResponse = try await withDeadline(requestTimeout, clock: clock) {

      try await httpClient.send(urlRequest)

    }

    // Whatever the client, a page larger than a Hub's isn't read.
    guard response.body.count <= Self.maximumResponseSize else {

      throw HTTPClientError.responseTooLarge(limit: Self.maximumResponseSize)

    }

    guard response.isSuccess else {

      throw HubError.unexpectedStatus(response.statusCode)

    }

    return response

  }

}
