/// Why a path wasn't reached.
public struct PathFailure: Equatable, Sendable {

  /// The path's name.
  public let path: String

  /// What a person can read about why, without an address or credential.
  public let reason: String

  /// Creates a failure.
  public init(path: String, reason: String) {
    self.path = path
    self.reason = reason
  }

}

/// What a ``HomeConnection`` reports when no path gave an answer.
public enum HomeError: Error, Equatable, Sendable {

  /// Every path was tried and none was reached. Nothing was sent.
  case noPathReached([PathFailure])

  /// The home refused this device's credential on the named path. Pair again.
  case unauthorized(path: String)

  /// The named path was lost while a request was in flight. A command may have reached its
  /// device: read the device's status before sending it again.
  case interrupted(path: String)

  /// The service refused a request with a code this library has no case for.
  case rejected(code: String, sent: Bool)

}
