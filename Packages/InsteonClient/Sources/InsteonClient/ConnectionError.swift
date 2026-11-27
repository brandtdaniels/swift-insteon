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

/// What a ``ClientConnection`` reports when no path gave an answer.
public enum ConnectionError: Error, Equatable, Sendable {

  /// Every path was tried and none was reached. Nothing was sent.
  case noPathReached([PathFailure])

  /// Every path that was tried refused this device's credential. The paths are named. Pair again.
  case unauthorized(paths: [String])

  /// The named path was lost while a request was in flight. A command may have reached its
  /// device: read the device's status before sending it again.
  case interrupted(path: String)

  /// The credential is good, but its scope is too low for the call on the named path. The path is
  /// kept. Pairing again doesn't help: ask for a credential with a wider scope.
  case forbidden(path: String)

  /// The named path answered with something this library can't read, or that isn't the service. The
  /// path is dropped, so the next call checks it again. A 3xx or 4xx answer from something that isn't
  /// the service means the service did not accept the request. For an unreadable 2xx answer to a
  /// command, the command may have taken effect: read the device's status before sending it again.
  case badResponse(path: String)

  /// None of the connection's paths carries this call, such as events over a Hub on the local
  /// network. Nothing was sent, and trying again won't help.
  case unsupported(paths: [String])

  /// The service's modem is away for a cause this library has no case for, named as the service
  /// names it, or `nil` when it names none. The service's wire answer carries no status for a Hub
  /// that answered with an error, so that cause is reported by name too. Nothing was sent.
  case modemUnavailable(cause: String?)

  /// The service refused a scene number: it isn't a group from 1 through 254. Nothing was sent.
  case invalidScene

  /// The service sent a command and can't say whether it took effect: the modem accepted it and then
  /// stopped answering, or the service gave up waiting. `sent` says whether the command may have
  /// reached a device. Read the devices before sending it again.
  case outcomeUnknown(sent: Bool)

  /// The service refused a request with a code this library has no case for.
  case rejected(code: String, sent: Bool)

}
