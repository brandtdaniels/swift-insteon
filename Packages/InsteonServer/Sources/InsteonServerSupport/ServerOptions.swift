import Foundation
import InsteonScheduling
import InsteonService
import Logging

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
  /// The network's name in a pairing document.
  public let networkName: String
  /// How often a Hub Pro is asked for its devices' levels, in seconds: from 2, and 5 by default.
  public let pollIntervalSeconds: Int
  /// The network's latitude in degrees, positive north, or nil. Given with ``longitude``.
  public let latitude: Double?
  /// The network's longitude in degrees, positive east, or nil. Given with ``latitude``.
  public let longitude: Double?
  /// The network's IANA time zone, such as `America/Los_Angeles`, or nil for the one the server remembers
  /// or the computer's. The host's time zone database decides whether the server can use it.
  public let timeZone: String?
  /// How much the server logs: `--log-level`, else `INSTEON_LOG_LEVEL` in the process's environment,
  /// else `info`. The environment file is read later and doesn't set it.
  public let logLevel: Logger.Level
  /// The tuning the service runs with: each value from its flag, else its `INSTEON_` environment
  /// variable, else the standard value. Checked with ``ServiceTuning/validated()``.
  public let tuning: ServiceTuning
  /// Where each tuning value that isn't the standard one came from, by name such as `scenes.echoWaitMs`.
  public let tuningSources: [String: TuningSource]

  /// Parses pairs of options, rejecting duplicates, public listeners and wildcard binds.
  /// Hub resolution and file permissions are checked by the CLI's existing helpers.
  public init(arguments: [String], environment: [String: String]) throws {
    var options: [String: String] = [:]
    let names: Set<String> = ["--listen", "--port", "--hub", "--serial", "--env-file", "--state", "--advertise-url", "--network-name", "--poll-interval", "--latitude", "--longitude", "--time-zone", "--log-level", "--scene-echo-wait-ms", "--scene-cleanup-quiet-ms", "--scene-cleanup-cap-ms"]
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
    let networkName = options["--network-name"] ?? "Network"
    guard (1...64).contains(networkName.count), !networkName.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw ServerOptionError.invalidNetworkName }
    self.networkName = networkName
    guard let pollInterval = Int(options["--poll-interval"] ?? "5"), (2...3600).contains(pollInterval) else { throw ServerOptionError.invalidPollInterval }
    self.pollIntervalSeconds = pollInterval
    switch (options["--latitude"], options["--longitude"]) {
    case (nil, nil):
      latitude = nil
      longitude = nil
    case let (latitudeText?, longitudeText?):
      guard let latitude = Double(latitudeText), let longitude = Double(longitudeText), GeographicCoordinate(latitude: latitude, longitude: longitude) != nil else { throw ServerOptionError.invalidLocation }
      self.latitude = latitude
      self.longitude = longitude
    default:
      throw ServerOptionError.invalidLocation
    }
    let timeZone = options["--time-zone"]
    if let timeZone {
      guard (1...64).contains(timeZone.count), timeZone.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "/_+-".contains($0)) }) else { throw ServerOptionError.invalidTimeZone }
    }
    self.timeZone = timeZone
    // A bad variable is refused even when the option is good, so a typo never goes unnoticed.
    let fromEnvironment = try environment["INSTEON_LOG_LEVEL"].map { try Self.level($0) }
    let fromOption = try options["--log-level"].map { try Self.level($0) }
    self.logLevel = fromOption ?? fromEnvironment ?? .info
    var scenes = ServiceTuning.Scenes.standard
    var sources: [String: TuningSource] = [:]
    // A flag beats its environment variable, which beats the standard value.
    func milliseconds(_ flag: String, _ variable: String, _ name: String, _ error: ServerOptionError) throws -> Duration? {
      let flagValue = options[flag], variableValue = environment[variable]
      guard let text = flagValue ?? variableValue else { return nil }
      // Only the unit is parsed here; ServiceTuning.validated() is the one place that knows the ranges.
      guard let value = Int(text) else { throw error }
      sources[name] = flagValue != nil ? .flag : .environment
      return .milliseconds(value)
    }
    if let value = try milliseconds("--scene-echo-wait-ms", "INSTEON_SCENE_ECHO_WAIT_MS", ServiceTuningError.Field.scenesEchoWait.name, .invalidSceneEchoWait) { scenes.echoWait = value }
    if let value = try milliseconds("--scene-cleanup-quiet-ms", "INSTEON_SCENE_CLEANUP_QUIET_MS", ServiceTuningError.Field.scenesCleanupQuiet.name, .invalidSceneCleanupQuiet) { scenes.cleanupQuietPeriod = value }
    if let value = try milliseconds("--scene-cleanup-cap-ms", "INSTEON_SCENE_CLEANUP_CAP_MS", ServiceTuningError.Field.scenesCleanupCap.name, .invalidSceneCleanupCap) { scenes.cleanupCap = value }
    // A quiet period nobody set follows a cap shorter than its standard value, so setting only a short cap works.
    if sources[ServiceTuningError.Field.scenesCleanupQuiet.name] == nil { scenes.cleanupQuietPeriod = min(scenes.cleanupQuietPeriod, scenes.cleanupCap) }
    do {
      tuning = try ServiceTuning(scenes: scenes).validated()
    } catch ServiceTuningError.invalid(let field) {
      switch field {
      case .scenesEchoWait: throw ServerOptionError.invalidSceneEchoWait
      case .scenesCleanupQuiet: throw ServerOptionError.invalidSceneCleanupQuiet
      case .scenesCleanupCap: throw ServerOptionError.invalidSceneCleanupCap
      }
    }
    tuningSources = sources
  }

  private static func level(_ text: String) throws -> Logger.Level {
    guard let level = Logger.Level(rawValue: text.lowercased()) else { throw ServerOptionError.invalidLogLevel }
    return level
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
  /// The network's name is empty, over 64 characters or has control characters.
  case invalidNetworkName
  /// `--poll-interval` isn't a whole number of seconds from 2 through 3600.
  case invalidPollInterval
  /// `--latitude` and `--longitude` are given together, as numbers within the Earth's range.
  case invalidLocation
  /// `--time-zone` isn't an IANA time zone's name of 1 through 64 letters, digits and `/_+-`.
  case invalidTimeZone
  /// `--log-level` or `INSTEON_LOG_LEVEL` isn't trace, debug, info, notice, warning, error or critical.
  case invalidLogLevel
  /// `--scene-echo-wait-ms` or its variable isn't a whole number of milliseconds from 1 through 60000.
  case invalidSceneEchoWait
  /// `--scene-cleanup-quiet-ms` or its variable isn't a whole number of milliseconds from 2150
  /// through the cap, which is the Insteon Developer's Guide's time for the first cleanup.
  case invalidSceneCleanupQuiet
  /// `--scene-cleanup-cap-ms` or its variable isn't a whole number of milliseconds from 2150 through 300000.
  case invalidSceneCleanupCap
  /// A `pair` command needs a client name of 1 through 64 characters and a scope of read, control or admin.
  case invalidClient

  /// A safe explanation suitable for standard error.
  public var description: String { ServerFailure(self).message }
}
