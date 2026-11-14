import Foundation

/// The listener, hardware and files selected before a server opens a connection.
public struct ServerOptions: Sendable {
  /// The interface's literal IPv4 address. Defaults to loopback.
  public let listen: String
  /// The server's TCP port, separate from the Hub's port.
  public let port: Int
  /// The Hub's private IPv4 address and optional port, as for the CLI.
  public let hub: String?
  /// The serial or USB modem's device path, as an alternative to a Hub.
  public let serialPath: String?
  /// An explicit environment file, or nil for the CLI's per-user default.
  public let envFilePath: String?
  /// The gateway's own snapshot file, separate from the CLI's cache.
  public let statePath: String

  /// Parses pairs of options, rejecting duplicates, public listeners and wildcard binds.
  /// Hub resolution and file permissions are checked by the CLI's existing helpers.
  public init(arguments: [String], environment: [String: String]) throws {
    var options: [String: String] = [:]
    let names: Set<String> = ["--listen", "--port", "--hub", "--serial", "--env-file", "--state"]
    var index = 0
    while index < arguments.count {
      let name = arguments[index]
      guard names.contains(name), options[name] == nil, index + 1 < arguments.count else { throw ServerOptionError.invalidArguments }
      let value = arguments[index + 1]
      guard !value.isEmpty, !value.hasPrefix("--") else { throw ServerOptionError.invalidArguments }
      options[name] = value
      index += 2
    }
    let listen = options["--listen"] ?? "127.0.0.1"
    guard Self.allowedListener(listen) else { throw ServerOptionError.invalidListener }
    guard let port = Int(options["--port"] ?? "8080"), (1...65535).contains(port) else { throw ServerOptionError.invalidPort }
    guard options["--hub"] == nil || options["--serial"] == nil else { throw ServerOptionError.invalidArguments }
    self.listen = listen
    self.port = port
    self.hub = options["--hub"]
    self.serialPath = options["--serial"]
    self.envFilePath = options["--env-file"]
    let stateHome = environment["XDG_STATE_HOME"].flatMap { $0.hasPrefix("/") ? $0 : nil }
    let home = environment["HOME"].flatMap { $0.hasPrefix("/") ? $0 : nil }
    self.statePath = options["--state"] ?? ((stateHome ?? home.map { $0 + "/.local/state" } ?? FileManager.default.homeDirectoryForCurrentUser.path + "/.local/state") + "/insteon/gateway.json")
    guard statePath.hasPrefix("/") else { throw ServerOptionError.invalidStatePath }
  }

  private static func allowedListener(_ address: String) -> Bool {
    let parts = address.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 4 else { return false }
    let bytes = parts.compactMap { UInt8($0) }
    guard bytes.count == 4, zip(parts, bytes).allSatisfy({ String($0.1) == $0.0 }) else { return false }
    return bytes[0] == 127 || bytes[0] == 10 || (bytes[0] == 172 && (16...31).contains(bytes[1])) || (bytes[0] == 192 && bytes[1] == 168) || (bytes[0] == 100 && (64...127).contains(bytes[1]))
  }
}

/// A configuration error whose message contains no supplied arguments or credentials.
public enum ServerOptionError: Error, CustomStringConvertible {
  /// An unknown, repeated, conflicting or incomplete option.
  case invalidArguments
  /// The listener is not a literal loopback, private or shared-address IPv4 address.
  case invalidListener
  /// The TCP port is outside 1 through 65535.
  case invalidPort
  /// The state file's path isn't absolute.
  case invalidStatePath

  /// A safe explanation suitable for standard error.
  public var description: String {
    switch self {
    case .invalidArguments: "Invalid options. Run insteon-server --help."
    case .invalidListener: "Bind to a specific loopback or private VPN IPv4 address; wildcard and public listeners are refused."
    case .invalidPort: "The server port must be from 1 through 65535."
    case .invalidStatePath: "The state file needs an absolute path."
    }
  }
}
