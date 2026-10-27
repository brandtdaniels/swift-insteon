import Foundation
import InsteonNetworking
import InsteonSerialCommand

/// A connection to an INSTEON Hub (model 2245) through its local HTTP interface.
///
/// The Hub passes serial commands to its built-in modem and collects the modem's replies in a
/// buffer, which you poll with ``Hub/readBuffer()``.
///
/// ```swift
/// let hub = Hub(
///   endpoint: HubEndpoint(host: "192.168.1.20"),
///   user: username,
///   password: password
/// )
///
/// let lamp = InsteonAddress(0xAA, 0xBB, 0xCC)
/// let turnOn = StandardMessage(to: lamp, command: StandardDirectCommand.on(level: 0xFF))
///
/// try await hub.send(.sendStandardMessage(turnOn))
/// ```
///
/// The Hub requires HTTP basic authentication with the user name and password printed on it.
/// ``Hub/init(endpoint:user:password:httpClient:)`` adds it for you; to authenticate another
/// way, pass an already-authenticated client to ``Hub/init(endpoint:httpClient:)``.
public struct Hub: SerialCommandSender {

  private let endpoint: HubEndpoint

  private let httpClient: any HTTPClient

  /// Creates a connection that sends requests through a client as-is.
  ///
  /// - Parameters:
  ///   - endpoint: Where the Hub can be reached.
  ///   - httpClient: The client to send requests with. It must authenticate them.
  public init(endpoint: HubEndpoint, httpClient: any HTTPClient) {

    self.endpoint = endpoint
    self.httpClient = httpClient

  }

  /// Creates a connection that authenticates with the Hub's user name and password.
  ///
  /// - Parameters:
  ///   - endpoint: Where the Hub can be reached.
  ///   - user: The Hub's user name.
  ///   - password: The Hub's password.
  ///   - httpClient: The client to send requests with. Defaults to ``URLSessionHTTPClient``.
  public init(
    endpoint: HubEndpoint,
    user: String,
    password: String,
    httpClient: any HTTPClient = URLSessionHTTPClient()
  ) {

    self.init(
      endpoint: endpoint,
      httpClient: BasicAuthenticationHTTPClient(httpClient, user: user, password: password)
    )

  }

  /// Passes a serial command to the Hub's modem.
  ///
  /// The modem's reply, such as an ACK or the requested data, arrives in the buffer.
  ///
  /// - Parameter command: The command to send.
  /// - Throws: ``HubError`` if the Hub rejected the request, or the HTTP client's error.
  public func send(_ command: SerialCommand) async throws {

    _ = try await perform(.send(command))

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

  private func perform(_ request: HubRequest) async throws -> HTTPResponse {

    let response = try await httpClient.send(request.urlRequest(for: endpoint))

    guard response.isSuccess else {

      throw HubError.unexpectedStatus(response.statusCode)

    }

    return response

  }

}
