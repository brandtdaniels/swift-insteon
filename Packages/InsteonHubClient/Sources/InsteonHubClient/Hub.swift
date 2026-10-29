import Foundation
import InsteonNetworking

/// The local HTTP interface of a Hub 2245 or Hub 2242.
///
/// The Hub passes bytes to its built-in modem and collects the modem's replies in a buffer.
/// These are the Hub's requests, with no pacing or retries; to send commands, wrap the Hub in a
/// ``HubConnection`` and drive it with a `Modem`, as you would a USB modem. A Hub 2242 also
/// runs timers, which ``Hub/setTimer(_:for:)`` and the methods beside it write.
///
/// The Hub requires HTTP basic authentication with the user name and password printed on it.
/// ``Hub/init(endpoint:user:password:httpClient:requestTimeout:)`` adds it for you; to
/// authenticate another way, pass an already-authenticated client to
/// ``Hub/init(endpoint:httpClient:requestTimeout:)``. The Hub's interface is plain HTTP, so the
/// credentials are readable on the network: keep the Hub on a network you trust.
///
/// Each request gives up after ``Hub/requestTimeout``, so a Hub that doesn't answer fails in
/// seconds rather than after `URLRequest`'s default of a minute.
public struct Hub: Sendable {

  /// How long each request waits for the Hub by default: 5 seconds.
  ///
  /// A Hub on the local network answers in well under a second, since every request is a short
  /// GET that returns a small page, such as the buffer, and no request waits for an Insteon
  /// device: the modem's replies arrive in the buffer later.
  public static let defaultRequestTimeout: Duration = .seconds(5)

  /// How long each request waits for the Hub before it fails.
  public let requestTimeout: Duration

  private let endpoint: HubEndpoint

  private let httpClient: any HTTPClient

  /// Creates a Hub interface that sends requests through a client as-is.
  ///
  /// - Parameters:
  ///   - endpoint: Where the Hub can be reached.
  ///   - httpClient: The client to send requests with. It must authenticate them.
  ///   - requestTimeout: How long each request waits for the Hub before it fails. Defaults to
  ///     ``Hub/defaultRequestTimeout``.
  public init(endpoint: HubEndpoint, httpClient: any HTTPClient, requestTimeout: Duration = Hub.defaultRequestTimeout) {

    self.endpoint = endpoint
    self.httpClient = httpClient
    self.requestTimeout = requestTimeout

  }

  /// Creates a Hub interface that authenticates with the Hub's user name and password.
  ///
  /// - Parameters:
  ///   - endpoint: Where the Hub can be reached.
  ///   - user: The Hub's user name.
  ///   - password: The Hub's password.
  ///   - httpClient: The client to send requests with. Defaults to `URLSessionHTTPClient`.
  ///   - requestTimeout: How long each request waits for the Hub before it fails. Defaults to
  ///     ``Hub/defaultRequestTimeout``.
  public init(
    endpoint: HubEndpoint,
    user: String,
    password: String,
    httpClient: any HTTPClient = URLSessionHTTPClient(),
    requestTimeout: Duration = Hub.defaultRequestTimeout
  ) {

    self.init(
      endpoint: endpoint,
      httpClient: BasicAuthenticationHTTPClient(httpClient, user: user, password: password),
      requestTimeout: requestTimeout
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

  func perform(_ request: HubRequest) async throws -> HTTPResponse {

    let response = try await httpClient.send(request.urlRequest(for: endpoint, timeout: requestTimeout))

    guard response.isSuccess else {

      throw HubError.unexpectedStatus(response.statusCode)

    }

    return response

  }

}
