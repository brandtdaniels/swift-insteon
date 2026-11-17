import InsteonCore
import InsteonHubClient
import InsteonModem

/// Why the service can't reach its modem, independent of any transport or display wording.
///
/// A cause never carries a host, address or credential.
public enum ModemUnavailability: Equatable, Sendable {
  /// The service hasn't finished its first connection since it started.
  case connecting
  /// The Hub didn't answer: its network is down, it lost power or it is restarting.
  case hubUnreachable
  /// The Hub rejected its user name and password (HTTP 401 or 403).
  case credentialsRejected
  /// The Hub answered with an HTTP error status, such as 503, until the connection gave up.
  case hubErrorStatus(Int)
  /// The modem didn't answer, or its serial port couldn't be opened or read.
  case modemUnreachable
  /// The connection ended or failed in a way that names no cause.
  case connectionLost
}

/// Whether the service can send to its modem.
public enum ModemConnectionState: Equatable, Sendable {
  /// The modem answered, and its ALL-Link database was read.
  case connected
  /// Commands are refused until a connection succeeds. The service keeps trying.
  case unavailable(ModemUnavailability)
}

/// What the service does with an error a connection attempt ended with.
enum ConnectionFailure: Equatable {
  /// Try again after a delay, and say why in the meantime.
  case retry(ModemUnavailability)
  /// Retrying can't help: the configuration is wrong.
  case fatal

  init(_ error: any Error) {
    switch error {
    case is HubAddressRefused, HubError.invalidEndpoint:
      self = .fatal
    case let HubError.unexpectedStatus(status) where status == 401 || status == 403:
      self = .retry(.credentialsRejected)
    case let HubError.unexpectedStatus(status):
      self = .retry(.hubErrorStatus(status))
    case is HubStoppedAnswering:
      self = .retry(.hubUnreachable)
    case ModemError.connectionClosed:
      self = .retry(.connectionLost)
    case is ModemError:
      self = .retry(.modemUnreachable)
    default:
      if HubStoppedAnswering.isUnanswered(error) {
        self = .retry(.hubUnreachable)
      } else if Self.isSerialPortFailure(error) {
        self = .retry(.modemUnreachable)
      } else {
        self = .retry(.connectionLost)
      }
    }
  }

  private static func isSerialPortFailure(_ error: any Error) -> Bool {
    #if os(macOS) || os(Linux)
    error is SerialPortError
    #else
    false
    #endif
  }
}
