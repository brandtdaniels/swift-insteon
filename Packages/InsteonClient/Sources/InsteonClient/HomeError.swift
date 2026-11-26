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

  /// Every path that was tried refused this device's credential. The paths are named. Pair again.
  case unauthorized(paths: [String])

  /// The named path was lost while a request was in flight. A command may have reached its
  /// device: read the device's status before sending it again.
  case interrupted(path: String)

  /// The named path answered with something this library can't read. The path is kept. A command
  /// the answer was for may have taken effect: read the device's status before sending it again.
  case badResponse(path: String)

  /// The service's modem is away for a cause this library has no case for, named as the service
  /// names it, or `nil` when it names none. The service's wire answer carries no status for a Hub
  /// that answered with an error, so that cause is reported by name too. Nothing was sent.
  case modemUnavailable(cause: String?)

  /// The service refused a request with a code this library has no case for.
  case rejected(code: String, sent: Bool)

}
