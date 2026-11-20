import Foundation

/// Why a plugin's request to the service, or its stream, failed.
///
/// A description never carries a token, a ticket or a path.
public enum PluginError: Error, Equatable, Sendable, CustomStringConvertible {
  /// The service answered with a status outside 200 through 299. `code` is the error `code` of the body, when it has one.
  case rejected(status: Int, code: String?)
  /// The service refused the credential or its scope (401 or 403), so retrying the same request can't succeed.
  case unauthorized(status: Int, code: String?)
  /// Nothing answered, or the connection ended before an answer.
  case unreachable
  /// The service answered something that isn't the contract's JSON.
  case malformedResponse

  public var description: String {
    switch self {
    case let .rejected(status, code): "The service answered \(status)" + (code.map { " (\($0))" } ?? "") + "."
    case let .unauthorized(status, code): "The service refused the credential with \(status)" + (code.map { " (\($0))" } ?? "") + "."
    case .unreachable: "The service didn't answer."
    case .malformedResponse: "The service's answer wasn't the contract's JSON."
    }
  }
}
