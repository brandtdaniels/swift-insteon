import Foundation
import Hummingbird
import HummingbirdCore
import InsteonCLISupport
import InsteonCore
import InsteonHTTP
import InsteonHubClient
import InsteonModem
import InsteonService
import Logging
import NIOCore

/// Starts the optional Swift server using the CLI's environment and modem selection rules.
public enum ServerRunner {
  /// Command-line help, without reading credentials or opening a connection.
  public static let help = """
  Usage: insteon-server [--hub HOST[:PORT] | --serial PATH] [OPTIONS]

  --listen IPV4     Bind to this interface (default: 127.0.0.1).
                   Choose the host's VPN address for remote access.
  --port PORT       Server port (default: 8080), separate from the Hub's port.
  --env-file PATH   Read settings from this file instead of ~/.config/insteon/env.
  --state PATH      Absolute path to the gateway's own network snapshot.
  --advertise-url URL  Where clients reach this server, such as http://insteon.local:8080,
                   for the pairing document (default: http://LISTEN:PORT).
  --home-name NAME  The home's name in a pairing document (default: Home).
  --help           Show this help without connecting.

  Settings are read from the same protected per-user environment file as insteon.
  A Hub uses INSTEON_HUB_HOST, INSTEON_HUB_PORT, INSTEON_HUB_USERNAME and
  INSTEON_HUB_PASSWORD. The website and API use the user name insteon and a
  separate INSTEON_GATEWAY_PASSWORD of 32 through 1024 bytes.

  Clients: the gateway password acts as an admin. A client has its own token and a scope
  (read, control or admin), is created with `insteon-server pair --name NAME` or the API,
  and is revoked with the API. Tokens are kept only as salted hashes.

  Use an encrypted VPN for remote HTTP access. The server supplies no VPN and
  uses no Insteon cloud service. Do not forward this server's or the Hub's port.
  """

  /// The modem a server opens, with what it needs to reach it.
  public enum ModemEndpoint: Sendable {
    /// A Hub at a location the credentials may be sent to.
    case hub(HubLocation, HubCredentials)
    /// A serial or USB modem's device path.
    case serial(path: String)
  }

  /// Opens the modem, runs `body` with the network it carries, and closes the modem when `body`
  /// returns or throws. The default opens the Hub or serial port; a test supplies a scripted connection.
  /// `onPollSucceeded` is called each time a Hub answers a poll; a serial modem has none.
  public typealias ModemOpener = @Sendable (
    _ endpoint: ModemEndpoint,
    _ catalog: ProductCatalog,
    _ snapshot: NetworkSnapshot,
    _ onPollSucceeded: @escaping @Sendable () async -> Void,
    _ body: @escaping @Sendable (DeviceNetwork) async throws -> Void
  ) async throws -> Void

  /// Opens the Hub or serial port the endpoint names.
  public static let openModem: ModemOpener = { endpoint, catalog, snapshot, onPollSucceeded, body in
    switch endpoint {
    case let .hub(location, credentials):
      try await ModemSession.withHub(host: location.host, port: location.port, user: credentials.user, password: credentials.password, catalog: catalog, onPollSucceeded: onPollSucceeded) { session in
        try await body(session.network(catalog: catalog, snapshot: snapshot, hub: session.hub))
      }
    case let .serial(path):
      #if os(macOS) || os(Linux)
      try await ModemSession.withSerialPort(path: path, catalog: catalog) { session in
        try await body(session.network(catalog: catalog, snapshot: snapshot, hub: session.hub))
      }
      #else
      throw ConfigurationError.serialUnavailable
      #endif
    }
  }

  /// Loads protected settings, serves the saved devices at once, and keeps reconnecting to the
  /// modem until interrupted. Supplied arguments, settings and lower-level errors are never
  /// written to a remote client.
  ///
  /// A setting, option, file or port that can't work ends the run with a failure to report. A
  /// Hub or modem that doesn't answer never does: the server stays up, serves what it saved, and
  /// logs why at each change.
  ///
  /// - Parameters:
  ///   - arguments: The command-line options after the program name.
  ///   - environment: The process environment, which an environment file adds to.
  ///   - logger: Receives progress notes, warnings and one record per HTTP request.
  ///   - openModem: Opens the modem. Defaults to ``openModem``.
  /// - Throws: A ``ServerFailure`` source error: describe it with ``ServerFailure/init(_:)``.
  public static func run(arguments: [String], environment: [String: String], logger: Logger = Logger(label: "insteon-server"), openModem: @escaping ModemOpener = ServerRunner.openModem) async throws {
    try await run(arguments: arguments, environment: environment, logger: logger, openModem: openModem, timing: Timing())
  }

  /// How long the server waits between attempts to reach its modem, and between reminders.
  struct Timing: Sendable {
    let reconnect: ReconnectPolicy
    let clock: any Clock<Duration>
    let jitter: @Sendable () -> Double
    let reminderClock: any Clock<Duration>
    let reminderInterval: Duration
    let now: @Sendable () -> Date
    let onListening: @Sendable (Int) -> Void

    init(
      reconnect: ReconnectPolicy = .standard,
      clock: any Clock<Duration> = ContinuousClock(),
      jitter: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) },
      reminderClock: any Clock<Duration> = ContinuousClock(),
      reminderInterval: Duration = .seconds(900),
      now: @escaping @Sendable () -> Date = { Date() },
      onListening: @escaping @Sendable (Int) -> Void = { _ in }
    ) {
      self.reconnect = reconnect
      self.clock = clock
      self.jitter = jitter
      self.reminderClock = reminderClock
      self.reminderInterval = reminderInterval
      self.now = now
      self.onListening = onListening
    }
  }

  static func run(arguments: [String], environment: [String: String], logger: Logger, openModem: @escaping ModemOpener, timing: Timing) async throws {
    let options = try ServerOptions(arguments: arguments, environment: environment)
    let environment = try EnvironmentFile.load(explicitPath: options.envFilePath, environment: environment, warn: { logger.warning("\($0)") })
    let target = try ModemTarget.resolve(hub: options.hub, serialPath: options.serialPath, environment: environment)
    guard let password = environment["INSTEON_GATEWAY_PASSWORD"] else { throw ServerRunError.missingPassword }
    // Validate server authentication before opening any hardware connection.
    let authentication: HTTPAuthentication
    do { authentication = try HTTPAuthentication(password: password) }
    catch { throw ServerRunError.invalidPassword }
    let catalog = try ProductCatalog.load(contentsOf: ProductCatalog.bundledCatalogURL())
    let store = JSONFileDeviceRegistryStore(fileURL: URL(fileURLWithPath: options.statePath))
    let clientFile = FileClientPersistence.url(besideState: options.statePath)
    let clients = ClientStore(persistence: FileClientPersistence(url: clientFile))
    // Reading the registry before listening keeps an unusable file from surfacing as a failed request.
    do { _ = try await clients.serviceID() }
    catch { throw ServerRunError.clientFileUnusable(path: clientFile.path) }
    let rulesFile = FileNotificationRulePersistence.url(besideState: options.statePath)
    let notificationRules = FileNotificationRulePersistence(url: rulesFile)
    do { _ = try await notificationRules.load() }
    catch { throw ServerRunError.notificationRulesFileUnusable(path: rulesFile.path) }
    let snapshot: NetworkSnapshot
    do { snapshot = try store.loadNetwork() }
    catch let error as DeviceRegistryStoreError { throw ServerRunError.stateFileUnusable(path: options.statePath, reason: error) }
    let savedAt = (try? FileManager.default.attributesOfItem(atPath: options.statePath))?[.modificationDate] as? Date
    let endpoint: ModemEndpoint
    let hub: HubLocation?
    switch target {
    case let .hub(host, port):
      let location = try ModemTarget.hubLocation(host: host, port: port)
      endpoint = .hub(location, try HubCredentials(environment: environment))
      hub = location
      logger.info("Starting: opening the Hub at \(location.host):\(location.port)")
    case let .serial(path):
      endpoint = .serial(path: path)
      hub = nil
      logger.info("Starting: opening the serial port")
    }
    try await serve(
      network: DeviceNetwork.offline(catalog: catalog, snapshot: snapshot, hub: hub),
      opener: EndpointOpener(endpoint: endpoint, catalog: catalog, openModem: openModem),
      hub: hub,
      snapshotSavedAt: savedAt,
      persistence: NetworkSnapshotPersistence(store: store),
      options: options,
      authentication: authentication,
      clients: clients,
      pairing: pairingConfiguration(for: options),
      notificationRules: notificationRules,
      logger: logger,
      timing: timing
    )
  }

  /// The pairing document's home name and its local network route: the advertised address, or the one the server listens on.
  static func pairingConfiguration(for options: ServerOptions) -> PairingConfiguration {
    PairingConfiguration(homeName: options.homeName, routes: [PairingRoute(kind: "lan", url: options.advertiseURL ?? "http://" + options.listen + ":" + String(options.port))])
  }

  /// Serves HTTP while the service keeps its modem connected. The listener opens first and serves
  /// the saved device list, so a Hub that is away never keeps the server down.
  static func serve(
    network: DeviceNetwork,
    opener: any NetworkOpening,
    hub: HubLocation?,
    snapshotSavedAt: Date?,
    persistence: any SnapshotPersisting,
    options: ServerOptions,
    authentication: any HTTPAuthenticating,
    clients: any ClientStoring,
    pairing: PairingConfiguration,
    notificationRules: any NotificationRulePersisting,
    logger: Logger,
    timing: Timing
  ) async throws {
    let service = InsteonService(network: network, opener: opener, persistence: persistence, snapshotSavedAt: snapshotSavedAt, reconnect: timing.reconnect, clock: timing.clock, now: timing.now, jitter: timing.jitter, throughHub: hub != nil, notificationRules: notificationRules)
    let router = makeInsteonRouter(service: service, authentication: authentication, clients: clients, pairing: pairing, logger: logger, now: timing.now)
    let app = Application(
      responder: router.buildResponder(),
      server: ConnectionLimits.server,
      configuration: .init(address: .hostname(options.listen, port: options.port), availableConnectionsDelegate: MaximumAvailableConnections(ConnectionLimits.maximumConnections)),
      onServerRunning: { channel in
        // The listener accepts connections, whether or not the modem has answered.
        logger.info("Serving Insteon at http://\(options.listen):\(options.port). Remote access requires an encrypted VPN.")
        timing.onListening(channel.localAddress?.port ?? options.port)
      },
      logger: logger
    )
    let events = await service.events()
    let outage = OutageLog(hub: hub, logger: logger)
    do {
      let persisted = try await service.run {
        try await withThrowingTaskGroup(of: Bool.self) { group in
          group.addTask {
            do { for try await event in events { await outage.handle(event) } } catch {}
            return false
          }
          group.addTask {
            // A failure that persists is repeated at an interval, not at every retry.
            do { while true { try await timing.reminderClock.sleep(for: timing.reminderInterval); await outage.remind() } } catch {}
            return false
          }
          group.addTask { try await app.runService(); return true }
          defer { group.cancelAll() }
          while let hostEnded = try await group.next(), !hostEnded {}
        }
      }
      if persisted == .failed {
        logger.warning("The final network snapshot could not be saved.")
      }
    } catch let error as IOError where error.errnoCode == EADDRINUSE {
      throw ServerRunError.portInUse(host: options.listen, port: options.port)
    }
  }
}

/// Opens the configured Hub or serial port for each connection attempt.
private struct EndpointOpener: NetworkOpening {
  let endpoint: ServerRunner.ModemEndpoint
  let catalog: ProductCatalog
  let openModem: ServerRunner.ModemOpener
  private let history = ConnectionHistory()

  init(endpoint: ServerRunner.ModemEndpoint, catalog: ProductCatalog, openModem: @escaping ServerRunner.ModemOpener) {
    self.endpoint = endpoint
    self.catalog = catalog
    self.openModem = openModem
  }

  func withNetwork(snapshot: NetworkSnapshot, _ body: @escaping @Sendable (DeviceNetwork) async throws -> Void) async throws {
    try await withNetwork(snapshot: snapshot, onPollSucceeded: {}, body)
  }

  func withNetwork(snapshot: NetworkSnapshot, onPollSucceeded: @escaping @Sendable () async -> Void, _ body: @escaping @Sendable (DeviceNetwork) async throws -> Void) async throws {
    let history = history
    do {
      try await openModem(endpoint, catalog, snapshot, onPollSucceeded) { network in
        await history.markConnected()
        try await body(network)
      }
    } catch let error as SerialPortError {
      // A path that doesn't exist before the modem has ever connected is a setting to fix. Later,
      // an unplugged modem is just away, and the same error means "retry".
      if await !history.hasConnected, case let .cannotOpen(_, code) = error, code == ENOENT { throw ConnectionRefusal(error) }
      throw error
    }
  }
}

private actor ConnectionHistory {
  private(set) var hasConnected = false
  func markConnected() { hasConnected = true }
}

/// Logs each change in whether the modem is reachable, and repeats an outage that lasts.
///
/// One outage is one record. While the modem stays away, a change between causes that all mean
/// "nothing answered" (the Hub, the modem or the connection) isn't a new record: the first cause
/// stands, and the reminder repeats it. A change to a cause that asks for a different action,
/// such as rejected credentials, is logged.
private actor OutageLog {
  private let hub: HubLocation?
  private let logger: Logger
  private var logged: ModemUnavailability?

  init(hub: HubLocation?, logger: Logger) {
    self.hub = hub
    self.logger = logger
  }

  func handle(_ event: ServiceEvent) {
    switch event {
    case let .modemUnavailable(cause):
      if let logged, logged.continuesOutage(of: cause) { return }
      logged = cause
      record(cause, reminder: false)
    case .modemReconnected:
      logged = nil
      logger.info("The Hub or modem is connected.", metadata: ["code": "modem_connected"])
    default:
      break
    }
  }

  func remind() {
    if let logged { record(logged, reminder: true) }
  }

  private func record(_ reason: ModemUnavailability, reminder: Bool) {
    guard let failure = ServerFailure.degraded(reason, hub: hub) else { return }
    failure.record(in: logger, level: reason == .credentialsRejected ? .error : .warning, reminder: reminder)
  }
}

private extension ModemUnavailability {
  /// Whether `other` is the same outage seen from a different side: nothing answered, and the
  /// person has the same thing to check.
  func continuesOutage(of other: ModemUnavailability) -> Bool {
    func nothingAnswered(_ cause: ModemUnavailability) -> Bool {
      switch cause {
      case .hubUnreachable, .modemUnreachable, .connectionLost: true
      case .connecting, .credentialsRejected, .hubErrorStatus: false
      }
    }
    return self == other || (nothingAnswered(self) && nothingAnswered(other))
  }
}

/// Startup failure with a credential-free description.
public enum ServerRunError: Error, CustomStringConvertible, Equatable {
  /// No gateway password was configured.
  case missingPassword
  /// The HTTP authentication policy refused the configured password.
  case invalidPassword
  /// The Hub did not answer. The server reports this while it keeps retrying.
  case hubUnreachable(host: String, port: Int)
  /// Another program already listens on the server's address and port.
  case portInUse(host: String, port: Int)
  /// The state file exists but can't be used.
  case stateFileUnusable(path: String, reason: DeviceRegistryStoreError)
  /// The client file exists but can't be used.
  case clientFileUnusable(path: String)
  /// The notification rules file exists but can't be used.
  case notificationRulesFileUnusable(path: String)
  /// The service already keeps the most clients it allows.
  case clientLimitReached

  /// A safe explanation for the person running the server.
  public var description: String { ServerFailure(self).message }
}
