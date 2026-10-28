import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonNetworking
import InsteonProtocol

/// Adds and removes Insteon devices on a Hub Pro 2243, reads its settings, and starts
/// its software update, through its local HTTP interface.
///
/// The interface is plain HTTP on port 80, without authentication, and every request is a
/// `POST`. Adding and removing a device, and reading the settings, answer with JSON.
///
/// ```swift
/// let hubPro = HubProClient(host: "192.168.1.20")
///
/// try await hubPro.addDevice(InsteonAddress(0x1A, 0x2B, 0x3C))
/// ```
///
/// The Hub Pro restarts its bridge after adding or removing a device, so it may not answer for
/// a while after. Send one request at a time.
public struct HubProClient: Sendable {

  /// The port of the Hub Pro's local HTTP interface: `80`.
  public static let defaultPort = 80

  /// How long to wait for an answer by default: 90 seconds, since adding a device waits for
  /// the device to answer the Hub Pro.
  public static let defaultTimeout: Duration = .seconds(90)

  /// The Hub Pro's host name or IP address.
  public let host: String

  /// The port of the Hub Pro's HTTP interface.
  public let port: Int

  /// The client requests are sent with.
  public let httpClient: any HTTPClient

  /// How long to wait for an answer.
  public let timeout: Duration

  /// Creates a client for a Hub Pro.
  ///
  /// - Parameters:
  ///   - host: The Hub Pro's host name or IP address.
  ///   - port: The port of its HTTP interface. Defaults to ``HubProClient/defaultPort``.
  ///   - httpClient: The client to send requests with. Defaults to a `URLSessionHTTPClient`.
  ///   - timeout: How long to wait for an answer. Defaults to
  ///     ``HubProClient/defaultTimeout``.
  public init(
    host: String,
    port: Int = HubProClient.defaultPort,
    httpClient: any HTTPClient = URLSessionHTTPClient(),
    timeout: Duration = HubProClient.defaultTimeout
  ) {

    self.host = host
    self.port = port
    self.httpClient = httpClient
    self.timeout = timeout

  }

  /// Adds a device to the Hub Pro.
  ///
  /// - Parameter device: The device's Insteon address, printed on it.
  /// - Throws: ``HubProError/deviceNotResponding`` if the device didn't answer the Hub Pro,
  ///   another ``HubProError`` if the Hub Pro refused or the host or port isn't usable, or the
  ///   client's error.
  public func addDevice(_ device: InsteonAddress) async throws {

    try Self.check(try await post("/insteon/add", device: device))

  }

  /// Removes a device from the Hub Pro.
  ///
  /// - Parameter device: The device's Insteon address.
  /// - Throws: ``HubProError/deviceNotResponding`` if the device didn't answer the Hub Pro,
  ///   another ``HubProError`` if the Hub Pro refused, or the client's error.
  public func removeDevice(_ device: InsteonAddress) async throws {

    try Self.check(try await post("/insteon/remove", device: device))

  }

  /// Reads the Hub Pro's network settings and software versions.
  ///
  /// - Returns: The settings.
  /// - Throws: ``HubProError/malformedResponse`` if the answer can't be read, another
  ///   ``HubProError`` if the Hub Pro refused, or the client's error.
  public func settings() async throws -> HubProSettings {

    let body = try await post("/settings")

    guard let settings = try? JSONDecoder().decode(HubProSettings.self, from: body) else {

      try Self.check(body)

      throw HubProError.malformedResponse

    }

    return settings

  }

  /// Starts installing the Hub Pro's waiting software update.
  ///
  /// The Hub Pro restarts to install it, so ``HubProClient/settings()`` fails for a while
  /// after. The update is done once ``HubProClient/settings()`` answers again and
  /// ``HubProSettings/isUpdateAvailable`` is `false`.
  ///
  /// - Throws: ``HubProError/unexpectedStatus(_:)`` if the Hub Pro refused, or the client's
  ///   error.
  public func startUpdate() async throws {

    // The Hub Pro may restart before its answer has a body, so only the status counts.
    _ = try await post("/update")

  }

  /// Sends a `POST` to a path, with the device as its `device` query item, and returns the
  /// body of a `200 OK` answer.
  private func post(_ path: String, device: InsteonAddress? = nil) async throws -> Data {

    var components = URLComponents()
    components.scheme = "http"
    components.host = host
    components.path = path

    if let device {

      // The Hub Pro waits for the device before answering when `sync` is `true`.
      components.queryItems = [
        URLQueryItem(name: "sync", value: "true"),
        URLQueryItem(name: "device", value: device.hexString),
      ]

    }

    guard !host.isEmpty, (0...65_535).contains(port) else {

      throw HubProError.invalidEndpoint

    }

    components.port = port

    guard let url = components.url, url.host != nil else {

      throw HubProError.invalidEndpoint

    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = TimeInterval(timeout.components.seconds) + TimeInterval(timeout.components.attoseconds) / 1e18

    let response = try await httpClient.send(request)

    guard response.statusCode == 200 else {

      throw HubProError.unexpectedStatus(response.statusCode)

    }

    return response.body

  }

  /// Checks an answer for the Hub Pro's `error` key.
  ///
  /// - Throws: ``HubProError/malformedResponse`` if the answer isn't a JSON object,
  ///   ``HubProError/deviceNotResponding`` or ``HubProError/rejected(_:)`` if it reports an
  ///   error.
  static func check(_ body: Data) throws(HubProError) {

    guard let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {

      throw .malformedResponse

    }

    // An empty or null error is no error.
    guard let error = object["error"], !(error is NSNull), (error as? String)?.isEmpty != true else {

      return

    }

    let message = error as? String ?? String(describing: error)

    // The Hub Pro reports a device that didn't answer by the fields it couldn't read from it.
    if message.contains("Key 'FromAddress' not found.") || message.contains("Key 'Device.InsteonEngineVersion' not found.") {

      throw .deviceNotResponding

    }

    throw .rejected(message)

  }

}
