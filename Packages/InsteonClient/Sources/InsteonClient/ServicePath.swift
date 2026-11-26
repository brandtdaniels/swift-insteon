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
public struct ServicePath: HomePath, CustomStringConvertible, CustomDebugStringConvertible {

  public let name: String
  private let baseURL: URL
  private let token: String
  private let http: any HTTPClient

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

  public func open() async throws -> any HomeCalls {
    let response: HTTPResponse
    do {
      response = try await http.send(request("GET", "/api/v1/health"))
    } catch {
      throw HomePathError.notReached("the service didn't answer")
    }
    switch response.statusCode {
    case 200..<300: return ServiceCalls(path: self)
    case 401, 403: throw HomePathError.unauthorized
    default: throw HomePathError.notReached("the service answered with status \(response.statusCode)")
    }
  }

  fileprivate func request(_ method: String, _ path: String, body: Data? = nil) -> URLRequest {
    var request = URLRequest(url: URL(string: path, relativeTo: baseURL)?.absoluteURL ?? baseURL)
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
      throw HomePathError.interrupted
    }
  }

}

/// The calls of an open ``ServicePath``.
private struct ServiceCalls: HomeCalls {

  let path: ServicePath

  func devices() async throws -> [ServiceDevice] {
    let response = try await path.send(path.request("GET", "/api/v1/devices"))
    guard (200..<300).contains(response.statusCode) else { throw try failure(response) }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    do {
      return try decoder.decode(DeviceList.self, from: response.body).devices.map { try $0.device() }
    } catch {
      throw HomePathError.interrupted
    }
  }

  func execute(_ command: ServiceCommand) async throws -> CommandReceipt {
    let body = try JSONSerialization.data(withJSONObject: Self.wire(command), options: [.sortedKeys])
    let response = try await path.send(path.request("POST", "/api/v1/devices/\(command.address)/commands", body: body))
    guard (200..<300).contains(response.statusCode) else { throw try failure(response) }
    do {
      return try JSONDecoder().decode(Receipt.self, from: response.body).receipt()
    } catch {
      // The command was accepted and its answer can't be read: it may have reached the device.
      throw HomePathError.interrupted
    }
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
    if response.statusCode == 401 { return HomePathError.unauthorized }
    guard let refusal else {
      return HomeError.rejected(code: "status\(response.statusCode)", sent: false)
    }
    switch refusal.code {
    case "unknownDevice": return ServiceControlError.unknownDevice
    case "invalidLevel": return ServiceControlError.invalidLevel
    case "unsupportedControl": return ServiceControlError.unsupportedControl
    case "notIdentified": return ServiceControlError.notIdentified
    case "notLinked": return ServiceControlError.notLinked
    case "busy": return ServiceControlError.busy
    case "modemUnavailable": return ServiceControlError.modemUnavailable(Self.cause(refusal.cause))
    default: return HomeError.rejected(code: refusal.code, sent: refusal.sent ?? true)
    }
  }

  private static func cause(_ name: String?) -> ModemUnavailability {
    switch name {
    case "connecting": .connecting
    case "hubUnreachable": .hubUnreachable
    case "credentialsRejected": .credentialsRejected
    case "hubErrorStatus": .hubErrorStatus(0)
    case "modemUnreachable": .modemUnreachable
    default: .connectionLost
    }
  }

  private struct Refusal: Decodable {
    let code: String
    let sent: Bool?
    let cause: String?
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
        guard let address = InsteonAddress(address) else { throw HomePathError.interrupted }
        return ServiceDevice(address: address, productName: productName, canTurnOnAndOff: canTurnOnAndOff, canDim: canDim, value: value, lastAnsweredAt: lastAnsweredAt)
      }
    }
  }

  private struct Receipt: Decodable {
    let address: String
    let outcome: String
    let status: Status?
    let persistence: String

    struct Status: Decodable {
      let group: Int?
      let kind: String
      let value: UInt8
      let isOn: Bool
      let percent: Int?
      let label: String?
    }

    func receipt() throws -> CommandReceipt {
      guard let address = InsteonAddress(address) else { throw HomePathError.interrupted }
      let outcome: CommandReceipt.Outcome = self.outcome == "read" ? .read : .acknowledged
      let persistence: PersistenceOutcome = switch self.persistence {
      case "notAttempted": .notAttempted
      case "saved": .saved
      case "failed": .failed
      default: .notConfigured
      }
      return CommandReceipt(address: address, outcome: outcome, status: status.map(Self.deviceStatus), persistence: persistence)
    }

    private static func deviceStatus(_ status: Status) -> DeviceStatus {
      let reading: DeviceStatus.Reading = switch status.kind {
      case "percent": status.percent.map { .percent($0) } ?? .raw
      case "onOff": .onOff(status.isOn)
      case "named": status.label.map { .named($0) } ?? .raw
      default: .raw
      }
      return DeviceStatus(group: status.group, value: status.value, allLinkDatabaseDelta: 0, reading: reading, isOn: status.isOn)
    }
  }

}
