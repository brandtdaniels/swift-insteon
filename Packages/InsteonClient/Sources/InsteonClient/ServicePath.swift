import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonCore
import InsteonNetworking
import InsteonProtocol
import InsteonService

/// The service's HTTP contract, spoken to one address with one client token.
///
/// The address is the service on a local network, or the local end of a transport's route. The
/// `HTTPClient` supplies the timeouts: give a client that gives up quickly, so a path that
/// doesn't answer passes the call on to the next.
public struct ServicePath: ConnectionPath, CustomStringConvertible, CustomDebugStringConvertible {

  public let name: String
  private let baseURL: URL
  private let token: String
  fileprivate let http: any HTTPClient

  /// Creates a path.
  ///
  /// - Parameters:
  ///   - name: What to call the path.
  ///   - baseURL: The service's address, such as `http://192.0.2.20:8080`.
  ///   - token: The client token from the pairing document.
  ///   - http: Sends the requests.
  public init(name: String, baseURL: URL, token: String, http: any HTTPClient) {
    self.name = name
    self.baseURL = baseURL
    self.token = token
    self.http = http
  }

  /// Names the path and its address, never the token.
  public var description: String { "ServicePath(\(name), \(baseURL.absoluteString))" }

  public var debugDescription: String { description }

  public func open() async throws -> any ConnectionCalls {
    let request = try request("GET", "/api/v1/health")
    let response: HTTPResponse
    do {
      response = try await http.send(request)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw ConnectionPathError.notReached("the service didn't answer")
    }
    switch response.statusCode {
    case 200..<300: return ServiceCalls(path: self)
    case 401: throw ConnectionPathError.unauthorized
    case 403: throw ConnectionPathError.forbidden
    default: throw ConnectionPathError.notReached("the service answered with status \(response.statusCode)")
    }
  }

  /// The address of an API path, under the base address's own path.
  private func address(_ path: String) throws -> URL {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
      let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
      let host = components.host, !host.isEmpty
    else { throw ConnectionPathError.notReached("the service address isn't an HTTP address") }
    if scheme == "http", !LocalAddress.isLocal(host: host) {
      throw ConnectionPathError.notReached("the token is never sent over HTTP to a host outside the local network")
    }
    components.query = nil
    components.fragment = nil
    let base = components.path.split(separator: "/", omittingEmptySubsequences: true).joined(separator: "/")
    components.path = (base.isEmpty ? "" : "/" + base) + path
    guard let url = components.url else { throw ConnectionPathError.notReached("the service address isn't an HTTP address") }
    return url
  }

  fileprivate func request(_ method: String, _ path: String, body: Data? = nil) throws -> URLRequest {
    var request = URLRequest(url: try address(path))
    request.httpMethod = method
    request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
    if method != "GET" { request.setValue("1", forHTTPHeaderField: "X-Insteon-Request") }
    if let body {
      request.httpBody = body
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    return request
  }

  fileprivate func send(_ request: URLRequest) async throws -> HTTPResponse {
    do {
      return try await http.send(request)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw ConnectionPathError.interrupted
    }
  }

}

/// The calls of an open ``ServicePath``.
private struct ServiceCalls: ConnectionCalls {

  let path: ServicePath

  func devices() async throws -> [ServiceDevice] {
    let response = try await path.send(try path.request("GET", "/api/v1/devices"))
    guard (200..<300).contains(response.statusCode) else { throw try failure(response) }
    let decoder = JSONDecoder()
    // Both forms, with and without fractional seconds, on every platform.
    decoder.dateDecodingStrategy = .custom { decoder in
      let text = try decoder.singleValueContainer().decode(String.self)
      let plain = ISO8601DateFormatter()
      let fractional = ISO8601DateFormatter()
      fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      guard let date = plain.date(from: text) ?? fractional.date(from: text) else {
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not an ISO 8601 date"))
      }
      return date
    }
    // One entry that can't be read fails the whole list: a partial list would look complete.
    do {
      return try decoder.decode(DeviceList.self, from: response.body).devices.map { try $0.device() }
    } catch {
      throw ConnectionPathError.badResponse
    }
  }

  func execute(_ command: ServiceCommand) async throws -> CommandReceipt {
    let body = try JSONSerialization.data(withJSONObject: Self.wire(command), options: [.sortedKeys])
    let response = try await path.send(try path.request("POST", "/api/v1/devices/\(Self.dotted(command.address))/commands", body: body))
    guard (200..<300).contains(response.statusCode) else { throw try failure(response) }
    do {
      return try JSONDecoder().decode(WireReceipt.self, from: response.body).receipt()
    } catch {
      // The command was accepted and its answer can't be read: it may have taken effect.
      throw ConnectionPathError.badResponse
    }
  }

  func sequencedEvents(after cursor: EventCursor?) async throws -> SequencedEvents {
    var request = try path.request("GET", "/api/v1/events")
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    if let cursor, !cursor.runID.isEmpty { request.setValue(cursor.token, forHTTPHeaderField: "Last-Event-ID") }
    let response: HTTPStreamResponse
    do {
      response = try await path.http.stream(request)
    } catch is CancellationError {
      throw CancellationError()
    } catch HTTPClientError.streamingUnsupported {
      throw ConnectionPathError.unsupported
    } catch {
      throw ConnectionPathError.interrupted
    }
    switch response.statusCode {
    case 200..<300: break
    case 401: throw ConnectionPathError.unauthorized
    case 403: throw ConnectionPathError.forbidden
    // A server error, such as a proxy's, or a service with all its streams in use, may pass.
    case 429, 500...: throw ConnectionPathError.interrupted
    default: throw ConnectionPathError.badResponse
    }
    // Something that answers 2xx but isn't an event stream, such as a proxy's page, isn't the service.
    guard response.headers["content-type"]?.lowercased().hasPrefix("text/event-stream") == true else { throw ConnectionPathError.badResponse }
    // The reader pulls from the bytes in the task that reads the items, so nothing runs unobserved.
    let reader = EventStreamReader(chunks: response.body)
    return SequencedEvents(AsyncThrowingStream { try await reader.next() })
  }

  /// The address as the service's path names it: two uppercase hexadecimal digits a byte, dotted.
  private static func dotted(_ address: InsteonAddress) -> String {
    [address.high, address.middle, address.low].map { String(format: "%02X", $0) }.joined(separator: ".")
  }

  private static func wire(_ command: ServiceCommand) -> [String: Any] {
    let action: String = switch command.action {
    case .identify: "identify"
    case .status: "status"
    case .on: "on"
    case .off: "off"
    }
    var object: [String: Any] = ["action": action]
    if let level = command.levelPercent { object["levelPercent"] = level }
    return object
  }

  /// The error a refusal stands for.
  private func failure(_ response: HTTPResponse) throws -> any Error {
    let refusal = try? JSONDecoder().decode(Refusal.self, from: response.body)
    if response.statusCode == 401 { return ConnectionPathError.unauthorized }
    if response.statusCode == 403 { return ConnectionPathError.forbidden }
    // An answer that isn't the service's own refusal comes from something else. A server error,
    // such as a proxy's, says nothing about whether the request reached the service. A 3xx or 4xx,
    // such as a wrong prefix, means the service did not accept the request: a bad response.
    guard let refusal else { return response.statusCode >= 500 ? ConnectionPathError.interrupted : ConnectionPathError.badResponse }
    switch refusal.code {
    case "unknownDevice": return ServiceControlError.unknownDevice
    case "invalidLevel": return ServiceControlError.invalidLevel
    case "unsupportedControl": return ServiceControlError.unsupportedControl
    case "notIdentified": return ServiceControlError.notIdentified
    case "notLinked": return ServiceControlError.notLinked
    case "busy": return ServiceControlError.busy
    case "modemUnavailable":
      if let cause = Self.cause(refusal.cause) { return ServiceControlError.modemUnavailable(cause) }
      return ConnectionError.modemUnavailable(cause: refusal.cause)
    default: return ConnectionError.rejected(code: refusal.code, sent: refusal.sent ?? true)
    }
  }

  /// The cause, when it has a case here that needs nothing the wire doesn't carry.
  private static func cause(_ name: String?) -> ModemUnavailability? {
    switch name {
    case "connecting": .connecting
    case "hubUnreachable": .hubUnreachable
    case "credentialsRejected": .credentialsRejected
    case "modemUnreachable": .modemUnreachable
    case "connectionLost": .connectionLost
    default: nil
    }
  }

  /// The service's own error body. Anything short of its whole shape is not the service's.
  private struct Refusal: Decodable {
    let version: Int
    let code: String
    let message: String
    let sent: Bool?
    let requestId: String
    let cause: String?

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: Keys.self)
      version = try container.decode(Int.self, forKey: .version)
      guard version == 1 else { throw ConnectionPathError.badResponse }
      code = try container.decode(String.self, forKey: .code)
      message = try container.decode(String.self, forKey: .message)
      sent = try container.decode(Bool.self, forKey: .sent)
      requestId = try container.decode(String.self, forKey: .requestId)
      cause = try container.decodeIfPresent(String.self, forKey: .cause)
    }

    private enum Keys: String, CodingKey { case version, code, message, sent, requestId, cause }
  }

  private struct DeviceList: Decodable {
    let devices: [Entry]

    struct Entry: Decodable {
      let address: String
      let productName: String?
      let canTurnOnAndOff: Bool
      let canDim: Bool
      let value: UInt8?
      let lastAnsweredAt: Date?

      func device() throws -> ServiceDevice {
        guard let address = InsteonAddress(address) else { throw ConnectionPathError.badResponse }
        return ServiceDevice(address: address, productName: productName, canTurnOnAndOff: canTurnOnAndOff, canDim: canDim, value: value, lastAnsweredAt: lastAnsweredAt)
      }
    }
  }

}
