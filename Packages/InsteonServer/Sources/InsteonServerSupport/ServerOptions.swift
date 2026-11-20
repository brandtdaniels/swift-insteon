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
  /// Where a client reaches this server on the local network, such as `http://insteon.local:8080`,
  /// or nil to use the listen address and port.
  public let advertiseURL: String?
  /// The home's name in a pairing document.
  public let homeName: String
  /// How often a Hub Pro is asked for its devices' levels, in seconds: from 2, and 5 by default.
  public let pollIntervalSeconds: Int

  /// Parses pairs of options, rejecting duplicates, public listeners and wildcard binds.
  /// Hub resolution and file permissions are checked by the CLI's existing helpers.
  public init(arguments: [String], environment: [String: String]) throws {
    var options: [String: String] = [:]
    let names: Set<String> = ["--listen", "--port", "--hub", "--serial", "--env-file", "--state", "--advertise-url", "--home-name", "--poll-interval"]
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
    advertiseURL = try options["--advertise-url"].map { try Self.normalized(advertisedURL: $0) }
    let homeName = options["--home-name"] ?? "Home"
    guard (1...64).contains(homeName.count), !homeName.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw ServerOptionError.invalidHomeName }
    self.homeName = homeName
    guard let pollInterval = Int(options["--poll-interval"] ?? "5"), (2...3600).contains(pollInterval) else { throw ServerOptionError.invalidPollInterval }
    self.pollIntervalSeconds = pollInterval
  }

  /// The address without a trailing slash, or an error if it isn't a plain http or https address.
  private static func normalized(advertisedURL text: String) throws -> String {
    guard let url = URL(string: text), let scheme = url.scheme, ["http", "https"].contains(scheme), let host = url.host(percentEncoded: false), !host.isEmpty,
          url.user == nil, url.password == nil, url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/" else { throw ServerOptionError.invalidAdvertiseURL }
    return text.hasSuffix("/") ? String(text.dropLast()) : text
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
  /// The advertised address isn't an http or https address without credentials, path or query.
  case invalidAdvertiseURL
  /// The home's name is empty, over 64 characters or has control characters.
  case invalidHomeName
  /// `--poll-interval` isn't a whole number of seconds from 2 through 3600.
  case invalidPollInterval
  /// A `pair` command needs a client name of 1 through 64 characters and a scope of read, control or admin.
  case invalidClient

  /// A safe explanation suitable for standard error.
  public var description: String { ServerFailure(self).message }
}
