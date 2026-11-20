import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends requests to the service's HTTP contract with one client token.
///
/// A plugin is an ordinary client: it holds a token the service issued, with the least scope its
/// work needs, and sends it as `Authorization: Bearer`. The token never appears in a description,
/// an error or a log line this library writes.
public struct ServiceClient: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  /// The service's loopback or LAN address, such as `http://127.0.0.1:8080`.
  public let baseURL: URL
  private let token: String
  private let session: URLSession

  /// What the service answered.
  public struct Response: Sendable, Equatable {
    /// The HTTP status.
    public let status: Int
    /// The body, which may be empty.
    public let body: Data

    /// The `code` of an error body, when the body has one.
    public var errorCode: String? {
      (try? JSONSerialization.jsonObject(with: body)).flatMap { $0 as? [String: Any] }?["code"] as? String
    }

    /// The failure a non-2xx answer stands for, or `nil` for a 2xx answer.
    public var failure: PluginError? {
      switch status {
      case 200..<300: nil
      case 401, 403: .unauthorized(status: status, code: errorCode)
      default: .rejected(status: status, code: errorCode)
      }
    }
  }

  /// Creates a client.
  /// - Parameters:
  ///   - baseURL: The service's address.
  ///   - token: A client token, from `insteon-server pair` or `POST /api/v1/clients`.
  public init(baseURL: URL, token: String) {
    self.baseURL = baseURL
    self.token = token
    let configuration = URLSessionConfiguration.ephemeral
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    session = URLSession(configuration: configuration)
  }

  public var description: String { "ServiceClient(\(baseURL.absoluteString))" }
  public var debugDescription: String { description }

  /// Sends one request and returns the answer, whatever its status.
  ///
  /// The request carries the `X-Insteon-Request` marker the contract asks of a change, and a JSON
  /// content type when it has a body. It isn't tied to the calling task's cancellation, so a plugin
  /// that is shutting down can still send its last request.
  ///
  /// - Throws: ``PluginError/unreachable`` when nothing answers.
  public func send(_ method: String, _ path: String, body: Data? = nil) async throws -> Response {
    let request = authorizedRequest(method, path, body: body)
    return try await withCheckedThrowingContinuation { continuation in
      session.dataTask(with: request) { data, response, error in
        if let http = response as? HTTPURLResponse {
          continuation.resume(returning: Response(status: http.statusCode, body: data ?? Data()))
        } else {
          continuation.resume(throwing: PluginError.unreachable)
        }
      }.resume()
    }
  }

  /// A request that carries this client's credential, for a caller that reads the answer itself.
  func authorizedRequest(_ method: String, _ path: String, body: Data? = nil) -> URLRequest {
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
}
