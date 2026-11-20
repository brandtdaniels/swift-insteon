import Foundation
import InsteonCLISupport
import InsteonCore
import InsteonHTTP
import InsteonHubClient
import InsteonModem
import InsteonService
import Logging

/// Why the server stopped, in words for the person who runs it.
///
/// A failure names its cause and the setting, file or device to check. Its message never carries a
/// password, an Authorization value or text a client sent. A cause the server can't name is
/// reported by its type alone.
public struct ServerFailure: Error, Equatable, Sendable {
  /// A stable name for the cause, for logs and scripts. The raw value never changes meaning.
  public enum Code: String, Sendable {
    case argumentsInvalid = "arguments_invalid"
    case listenAddressInvalid = "listen_address_invalid"
    case portInvalid = "port_invalid"
    case portInUse = "port_in_use"
    case gatewayPasswordMissing = "gateway_password_missing"
    case gatewayPasswordInvalid = "gateway_password_invalid"
    case environmentFileMissing = "environment_file_missing"
    case environmentFileUnreadable = "environment_file_unreadable"
    case environmentFileUnsafe = "environment_file_unsafe"
    case environmentFileMalformed = "environment_file_malformed"
    case modemNotChosen = "modem_not_chosen"
    case hubCredentialsMissing = "hub_credentials_missing"
    case hubAddressRefused = "hub_address_refused"
    case hubCredentialsRejected = "hub_credentials_rejected"
    case hubUnreachable = "hub_unreachable"
    case hubAnsweredWithError = "hub_answered_with_error"
    case hardwareError = "hardware_error"
    case serialPathMissing = "serial_path_missing"
    case serialPortUnavailable = "serial_port_unavailable"
    case stateFileUnusable = "state_file_unusable"
    case clientFileUnusable = "client_file_unusable"
    case notificationRulesFileUnusable = "notification_rules_file_unusable"
    case routesFileUnusable = "routes_file_unusable"
    case clientLimitReached = "client_limit_reached"
    case advertiseURLInvalid = "advertise_url_invalid"
    case homeNameInvalid = "home_name_invalid"
    case pairingOptionsInvalid = "pairing_options_invalid"
    case modemConnectionEnded = "modem_connection_ended"
    case modemUnreachable = "modem_unreachable"
    case unexpected = "unexpected_error"
  }

  /// The exit status for a setting, file or option the person has to change.
  public static let configurationStatus: Int32 = 78
  /// The exit status for a Hub, modem or port that isn't available.
  public static let unavailableStatus: Int32 = 69

  /// What went wrong.
  public let code: Code
  /// A guided, one-line explanation for standard error and the log.
  public let message: String
  /// The process's exit status: 78 to change a setting, 69 for hardware or a port that isn't
  /// available, and 1 for anything unrecognized.
  public let exitStatus: Int32

  /// Describes an error from starting or running the server.
  public init(_ error: any Error) {
    switch error {
    case let failure as ServerFailure: self = failure
    case let error as ServerOptionError: self = Self.describe(error)
    case let error as ServerRunError: self = Self.describe(error)
    case let error as EnvironmentFileError: self = Self.describe(error)
    case let error as DotEnvError: self.init(.environmentFileMalformed, error.description, Self.configurationStatus)
    case let error as ConfigurationError: self = Self.describe(error)
    case let error as HubAddressRefused: self.init(.hubAddressRefused, error.description + " Change --hub or INSTEON_HUB_HOST.", Self.configurationStatus)
    case let error as HubError:
      if case let .unexpectedStatus(status) = error, status == 401 || status == 403 {
        self.init(.hubCredentialsRejected, "The Hub rejected its user name and password (HTTP \(status)). Check INSTEON_HUB_USERNAME and INSTEON_HUB_PASSWORD in the environment file.", Self.configurationStatus)
      } else {
        let message = InsteonErrorDescription.message(for: error) ?? "The Hub answered with an error."
        self.init(.hubAnsweredWithError, message + " Check the Hub, then start the server again.", Self.unavailableStatus)
      }
    case let error as SerialPortError: self = Self.describe(error)
    default:
      // Reuse InsteonCore's wording for an error from the modem, Hub or network libraries.
      if let message = InsteonErrorDescription.message(for: error) {
        self.init(.hardwareError, message, Self.unavailableStatus)
      } else {
        self = Self.unexpected(error)
      }
    }
  }

  /// Writes the failure as one critical record, with its code and exit status as metadata.
  public func record(in logger: Logger) {
    logger.critical("\(message)", metadata: ["code": "\(code.rawValue)", "exit_status": "\(exitStatus)"])
  }

  /// Describes why the modem is away while the server keeps running and retries, or `nil` while it
  /// is still making its first connection. The wording reuses the startup failures' and ends with
  /// what the server does next.
  ///
  /// - Parameters:
  ///   - cause: Why the service can't reach its modem.
  ///   - hub: The Hub the server reaches, or `nil` for a serial modem.
  static func degraded(_ cause: ModemUnavailability, hub: HubLocation?) -> ServerFailure? {
    let retries = " The server keeps running and retries; commands get 503 until it answers."
    switch cause {
    case .connecting:
      return nil
    case .hubUnreachable:
      guard let hub else { return degraded(.modemUnreachable, hub: nil) }
      let base = ServerFailure(ServerRunError.hubUnreachable(host: hub.host, port: hub.port))
      return ServerFailure(.hubUnreachable, base.message + retries, unavailableStatus)
    case .credentialsRejected:
      let base = ServerFailure(HubError.unexpectedStatus(401)).message.replacingOccurrences(of: "(HTTP 401)", with: "(HTTP 401 or 403)")
      return ServerFailure(.hubCredentialsRejected, base + " The server keeps running and retries every 15 minutes; restart it after changing the settings.", configurationStatus)
    case let .hubErrorStatus(status):
      let base = ServerFailure(HubError.unexpectedStatus(status)).message.replacingOccurrences(of: " Check the Hub, then start the server again.", with: "")
      return ServerFailure(.hubAnsweredWithError, base + retries, unavailableStatus)
    case .modemUnreachable:
      return ServerFailure(.modemUnreachable, "The modem isn't answering. Check that it's connected and powered." + retries, unavailableStatus)
    case .connectionLost:
      return ServerFailure(.modemConnectionEnded, "The connection to the Hub or modem ended." + retries, unavailableStatus)
    }
  }

  /// Writes the failure as one record at `level`, with its code as metadata, for a failure the
  /// server survives.
  func record(in logger: Logger, level: Logger.Level, reminder: Bool = false) {
    logger.log(level: level, "\(message)", metadata: ["code": "\(code.rawValue)", "retrying": "true", "reminder": "\(reminder)"])
  }

  private init(_ code: Code, _ message: String, _ exitStatus: Int32) {
    self.code = code
    self.message = message
    self.exitStatus = exitStatus
  }

  private static func unexpected(_ error: any Error) -> ServerFailure {
    ServerFailure(.unexpected, "The server stopped on an unexpected error (\(type(of: error))). Check the Hub or modem, the listener and the state file.", 1)
  }

  private static func describe(_ error: ServerOptionError) -> ServerFailure {
    switch error {
    case .invalidArguments: ServerFailure(.argumentsInvalid, "Invalid options. Run insteon-server --help for the ones it takes.", configurationStatus)
    case .invalidListener: ServerFailure(.listenAddressInvalid, "--listen must be a literal IPv4 address on this computer's loopback or a private network, such as 127.0.0.1 or a VPN address. Wildcard and public addresses are refused.", configurationStatus)
    case .invalidPort: ServerFailure(.portInvalid, "--port must be a number from 1 through 65535.", configurationStatus)
    case .invalidStatePath: ServerFailure(.stateFileUnusable, "--state must be an absolute path.", configurationStatus)
    case .invalidAdvertiseURL: ServerFailure(.advertiseURLInvalid, "--advertise-url must be an http or https address with a host, such as http://insteon.local:8080, and no credentials, path or query.", configurationStatus)
    case .invalidClient: ServerFailure(.pairingOptionsInvalid, "pair needs --name with 1 through 64 characters and no control characters, and takes --scope read, control or admin. Run insteon-server pair --help.", configurationStatus)
    case .invalidHomeName: ServerFailure(.homeNameInvalid, "--home-name must be 1 through 64 characters without control characters.", configurationStatus)
    }
  }

  private static func describe(_ error: ServerRunError) -> ServerFailure {
    switch error {
    case .missingPassword:
      ServerFailure(.gatewayPasswordMissing, "INSTEON_GATEWAY_PASSWORD isn't set. Add it to the environment file; it needs 32 through 1024 bytes with no control characters.", configurationStatus)
    case .invalidPassword:
      ServerFailure(.gatewayPasswordInvalid, "INSTEON_GATEWAY_PASSWORD must contain 32 through 1024 bytes with no control characters. Change it in the environment file.", configurationStatus)
    case let .hubUnreachable(host, port):
      ServerFailure(.hubUnreachable, "The Hub at \(host):\(port) didn't answer. Check that it's powered on and on the same network, and that --hub or INSTEON_HUB_HOST is its address.", unavailableStatus)
    case let .portInUse(host, port):
      ServerFailure(.portInUse, "\(host):\(port) is already in use. Stop the other program or choose another port with --port.", unavailableStatus)
    case .clientLimitReached:
      ServerFailure(.clientLimitReached, "The service keeps at most \(ClientStore.maximumClients) clients. Revoke one with DELETE /api/v1/clients/{id}, then pair again.", configurationStatus)
    case let .clientFileUnusable(path):
      ServerFailure(.clientFileUnusable, "The client file \(path) couldn't be read or isn't in a format this server reads, so it was left as it is. Move it aside to start with no clients; every client must pair again.", configurationStatus)
    case let .notificationRulesFileUnusable(path):
      ServerFailure(.notificationRulesFileUnusable, "The notification rules file \(path) couldn't be read or isn't in a format this server reads, so it was left as it is. Move it aside to start with no rules.", configurationStatus)
    case let .routesFileUnusable(path):
      ServerFailure(.routesFileUnusable, "The routes file \(path) couldn't be read or isn't in a format this server reads, so it was left as it is. Move it aside to start with no registered routes; each transport registers again when it starts.", configurationStatus)
    case let .stateFileUnusable(path, reason):
      switch reason {
      case .unreadableFile:
        ServerFailure(.stateFileUnusable, "The state file \(path) couldn't be read, so it was left as it is. Check that this account may read it.", configurationStatus)
      default:
        ServerFailure(.stateFileUnusable, "The state file \(path) isn't in a format this server reads, so it was left as it is. Move it aside and the server starts a fresh one.", configurationStatus)
      }
    }
  }

  private static func describe(_ error: EnvironmentFileError) -> ServerFailure {
    switch error {
    case .notFound:
      ServerFailure(.environmentFileMissing, error.description + " Create it, or leave out --env-file to use the default.", configurationStatus)
    case .unreadable:
      ServerFailure(.environmentFileUnreadable, error.description, configurationStatus)
    case .refused:
      ServerFailure(.environmentFileUnsafe, error.description, configurationStatus)
    }
  }

  private static func describe(_ error: ConfigurationError) -> ServerFailure {
    switch error {
    case .missingCredentials: ServerFailure(.hubCredentialsMissing, error.description, configurationStatus)
    case .noModem, .conflictingModems: ServerFailure(.modemNotChosen, error.description, configurationStatus)
    case .invalidHost, .invalidPort: ServerFailure(.hubAddressRefused, error.description, configurationStatus)
    case .serialUnavailable: ServerFailure(.serialPortUnavailable, error.description, configurationStatus)
    }
  }

  private static func describe(_ error: SerialPortError) -> ServerFailure {
    if case let .cannotOpen(path, code) = error, code == ENOENT {
      return ServerFailure(.serialPathMissing, "No serial device at \(path). Plug in the modem and check the path given to --serial.", configurationStatus)
    }
    let message = InsteonErrorDescription.message(for: error) ?? "The serial port couldn't be used."
    return ServerFailure(.serialPortUnavailable, message + " Check that this account may use the device and that no other program has it open.", unavailableStatus)
  }
}
