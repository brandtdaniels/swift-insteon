import Foundation

/// A response received by an ``HTTPClient``.
public struct HTTPResponse: Hashable, Sendable {

  /// The HTTP status code.
  public var statusCode: Int

  /// The response headers, keyed by lowercased name, since header names are case-insensitive.
  public var headers: [String: String]

  /// The response body. Empty when the server sent no body.
  public var body: Data

  /// Creates a response.
  ///
  /// - Parameters:
  ///   - statusCode: The HTTP status code.
  ///   - headers: The response headers. Defaults to none. Their names are lowercased; if two
  ///     differ only in case, the first in the dictionary's order wins.
  ///   - body: The response body. Defaults to empty.
  public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {

    self.statusCode = statusCode
    self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }) { first, _ in first }
    self.body = body

  }

  /// Whether ``HTTPResponse/statusCode`` is in the 2xx range.
  public var isSuccess: Bool {

    (200...299).contains(statusCode)

  }

  /// Returns the value of a header, matching its name case-insensitively.
  ///
  /// - Parameter name: The header's name.
  /// - Returns: The header's value, or `nil` if the response doesn't include it.
  public func value(forHeader name: String) -> String? {

    headers[name.lowercased()]

  }

}
