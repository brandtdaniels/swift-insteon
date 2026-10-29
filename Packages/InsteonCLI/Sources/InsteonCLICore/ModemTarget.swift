/// The environment variables the `insteon` command reads.
public enum EnvironmentKey {

  /// The Hub's user name, printed on the Hub: `INSTEON_HUB_USERNAME`.
  public static let hubUsername = "INSTEON_HUB_USERNAME"

  /// The Hub's password, printed on the Hub: `INSTEON_HUB_PASSWORD`.
  public static let hubPassword = "INSTEON_HUB_PASSWORD"

  /// The Hub's host name or IP address, used when `--hub` isn't given: `INSTEON_HUB_HOST`.
  public static let hubHost = "INSTEON_HUB_HOST"

  /// The port of the Hub's HTTP interface, used when the host doesn't give one:
  /// `INSTEON_HUB_PORT`.
  public static let hubPort = "INSTEON_HUB_PORT"

}

/// The modem the `insteon` command talks to: an Insteon Hub's built-in modem, or a modem on a
/// serial or USB port.
public enum ModemTarget: Hashable, Sendable {

  /// A Hub at a host, and the port of its HTTP interface, or `nil` for the Hub's default port.
  case hub(host: String, port: Int?)

  /// A modem on the serial port at a path, such as `/dev/ttyUSB0`.
  case serial(path: String)

  /// Works out the modem from `--hub` or `--serial`, or else from the environment.
  ///
  /// `--hub` and `--serial` can't both be given. Without either, the Hub's host comes from
  /// `INSTEON_HUB_HOST`. A host without a port takes its port from `INSTEON_HUB_PORT`, if it's
  /// set.
  ///
  /// - Parameters:
  ///   - hub: The value of `--hub`, `HOST` or `HOST:PORT`, if given.
  ///   - serialPath: The value of `--serial`, if given.
  ///   - environment: The environment, with any environment file merged in.
  /// - Returns: The modem to talk to.
  /// - Throws: ``ConfigurationError`` if no modem was given, both kinds were, or the host or
  ///   port isn't valid.
  public static func resolve(hub: String?, serialPath: String?, environment: [String: String]) throws(ConfigurationError) -> ModemTarget {

    if hub != nil, serialPath != nil {

      throw ConfigurationError.conflictingModems

    }

    if let serialPath {

      guard !serialPath.isEmpty else {

        throw ConfigurationError.noModem

      }

      return .serial(path: serialPath)

    }

    guard let text = hub ?? nonEmpty(environment[EnvironmentKey.hubHost]) else {

      throw ConfigurationError.noModem

    }

    let (host, port) = try hostAndPort(text)

    if let port {

      return .hub(host: host, port: port)

    }

    guard let portText = nonEmpty(environment[EnvironmentKey.hubPort]) else {

      return .hub(host: host, port: nil)

    }

    return try .hub(host: host, port: self.port(portText))

  }

  /// Splits `HOST:PORT` into its host and port. A host with more than one colon is an IPv6
  /// address without a port.
  private static func hostAndPort(_ text: String) throws(ConfigurationError) -> (host: String, port: Int?) {

    let parts = text.split(separator: ":", omittingEmptySubsequences: false)

    guard parts.count == 2 else {

      guard !text.isEmpty else {

        throw ConfigurationError.invalidHost(text)

      }

      return (text, nil)

    }

    let host = String(parts[0])

    guard !host.isEmpty else {

      throw ConfigurationError.invalidHost(text)

    }

    return try (host, port(String(parts[1])))

  }

  private static func port(_ text: String) throws(ConfigurationError) -> Int {

    guard let port = Int(text), (1...65_535).contains(port) else {

      throw ConfigurationError.invalidPort(text)

    }

    return port

  }

  private static func nonEmpty(_ value: String?) -> String? {

    guard let value, !value.isEmpty else {

      return nil

    }

    return value

  }

}

/// The Hub's user name and password, read from the environment.
///
/// Printing or dumping credentials shows neither value, so they don't end up in a terminal or
/// a log by accident.
public struct HubCredentials: Hashable, Sendable {

  /// The Hub's user name.
  public var user: String

  /// The Hub's password.
  public var password: String

  /// Creates credentials.
  ///
  /// - Parameters:
  ///   - user: The Hub's user name.
  ///   - password: The Hub's password.
  public init(user: String, password: String) {

    self.user = user
    self.password = password

  }

  /// Reads the credentials from `INSTEON_HUB_USERNAME` and `INSTEON_HUB_PASSWORD`.
  ///
  /// - Parameter environment: The environment, with any environment file merged in.
  /// - Throws: ``ConfigurationError/missingCredentials`` if either is missing or empty.
  public init(environment: [String: String]) throws(ConfigurationError) {

    guard
      let user = environment[EnvironmentKey.hubUsername], !user.isEmpty,
      let password = environment[EnvironmentKey.hubPassword], !password.isEmpty
    else {

      throw ConfigurationError.missingCredentials

    }

    self.init(user: user, password: password)

  }

}

extension HubCredentials: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {

  /// A placeholder that shows neither the user name nor the password.
  public var description: String {

    "HubCredentials(redacted)"

  }

  /// A placeholder that shows neither the user name nor the password.
  public var debugDescription: String {

    description

  }

  /// A mirror with no children, so `dump(_:)` shows neither value.
  public var customMirror: Mirror {

    Mirror(self, children: [Mirror.Child]())

  }

}

/// A modem or Hub the `insteon` command can't use as configured, with a message that says why.
public enum ConfigurationError: Error, Hashable, Sendable {

  /// Neither `--hub`, `--serial` nor `INSTEON_HUB_HOST` says which modem to use.
  case noModem

  /// Both `--hub` and `--serial` were given.
  case conflictingModems

  /// The Hub's host is empty or malformed.
  case invalidHost(String)

  /// The Hub's port isn't a number from 1 to 65,535.
  case invalidPort(String)

  /// `INSTEON_HUB_USERNAME` or `INSTEON_HUB_PASSWORD` is missing.
  case missingCredentials

  /// A serial port was asked for on a platform without serial ports.
  case serialUnavailable

}

extension ConfigurationError: CustomStringConvertible {

  /// The error as a one-line message for the person who typed the command.
  public var description: String {

    switch self {
    case .noModem:
      "No modem given: use --hub HOST[:PORT], set INSTEON_HUB_HOST, or use --serial PATH."
    case .conflictingModems:
      "Use either --hub or --serial, not both."
    case let .invalidHost(text):
      "'\(text)' isn't a valid Hub: expected HOST or HOST:PORT, such as 192.168.1.20."
    case let .invalidPort(text):
      "'\(text)' isn't a valid port: expected a number from 1 to 65535."
    case .missingCredentials:
      "The Hub's user name and password are missing: set INSTEON_HUB_USERNAME and INSTEON_HUB_PASSWORD in the environment or in ~/.config/insteon/env."
    case .serialUnavailable:
      "Serial ports are available only on macOS and Linux."
    }

  }

}
