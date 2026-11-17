import Foundation
import Hummingbird
import HummingbirdCore
import InsteonCLISupport
import InsteonCore
import InsteonHTTP
import InsteonService

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
  --help           Show this help without connecting.

  Settings are read from the same protected per-user environment file as insteon.
  A Hub uses INSTEON_HUB_HOST, INSTEON_HUB_PORT, INSTEON_HUB_USERNAME and
  INSTEON_HUB_PASSWORD. The website and API use the user name insteon and a
  separate INSTEON_GATEWAY_PASSWORD of 32 through 1024 bytes.

  Use an encrypted VPN for remote HTTP access. The server supplies no VPN and
  uses no Insteon cloud service. Do not forward this server's or the Hub's port.
  """

  /// Loads protected settings, serves the saved devices at once, and keeps reconnecting to the modem until interrupted.
  /// Supplied arguments, settings and lower-level errors are never written to a remote client.
  public static func run(arguments: [String], environment: [String: String]) async throws {
    let options = try ServerOptions(arguments: arguments, environment: environment)
    let environment = try EnvironmentFile.load(explicitPath: options.envFilePath, environment: environment, warn: note)
    let target = try ModemTarget.resolve(hub: options.hub, serialPath: options.serialPath, environment: environment)
    guard let password = environment["INSTEON_GATEWAY_PASSWORD"] else { throw ServerRunError.missingPassword }
    // Validate server authentication before opening any hardware connection.
    let authentication: HTTPAuthentication
    do { authentication = try HTTPAuthentication(password: password) }
    catch { throw ServerRunError.invalidPassword }
    let catalog = try ProductCatalog.load(contentsOf: ProductCatalog.bundledCatalogURL())
    let store = JSONFileDeviceRegistryStore(fileURL: URL(fileURLWithPath: options.statePath))
    let snapshot = try store.loadNetwork()
    let savedAt = (try? FileManager.default.attributesOfItem(atPath: options.statePath))?[.modificationDate] as? Date
    let opener: any NetworkOpening
    let location: HubLocation?
    switch target {
    case let .hub(host, port):
      let hub = try ModemTarget.hubLocation(host: host, port: port)
      location = hub
      let credentials = try HubCredentials(environment: environment)
      note("Opening the Hub at \(hub.host):\(hub.port)")
      let (user, password) = (credentials.user, credentials.password)
      opener = ModemSessionOpener(catalog: catalog) { body in
        try await ModemSession.withHub(host: hub.host, port: hub.port, user: user, password: password, catalog: catalog, body)
      }
    case let .serial(path):
      #if os(macOS) || os(Linux)
      location = nil
      opener = ModemSessionOpener(catalog: catalog) { body in
        try await ModemSession.withSerialPort(path: path, catalog: catalog, body)
      }
      #else
      throw ConfigurationError.serialUnavailable
      #endif
    }
    try await serve(
      network: DeviceNetwork.offline(catalog: catalog, snapshot: snapshot, hub: location),
      opener: opener,
      snapshotSavedAt: savedAt,
      persistence: NetworkSnapshotPersistence(store: store),
      listen: options.listen,
      port: options.port,
      authentication: authentication
    )
  }

  /// Serves HTTP while the service keeps its modem connected. The listener opens first and
  /// serves the saved device list, so a Hub that is away never keeps the server down.
  static func serve(
    network: DeviceNetwork,
    opener: any NetworkOpening,
    snapshotSavedAt: Date?,
    persistence: any SnapshotPersisting,
    listen: String,
    port: Int,
    authentication: any HTTPAuthenticating,
    reconnect: ReconnectPolicy = .standard,
    clock: any Clock<Duration> = ContinuousClock(),
    jitter: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) },
    onListening: @escaping @Sendable (Int) -> Void = { _ in },
    onEvent: @escaping @Sendable (ServiceEvent) -> Void = ServerRunner.logConnectionChange
  ) async throws {
    let service = InsteonService(network: network, opener: opener, persistence: persistence, snapshotSavedAt: snapshotSavedAt, reconnect: reconnect, clock: clock, jitter: jitter)
    let router = makeInsteonRouter(service: service, authentication: authentication)
    let app = Application(
      responder: router.buildResponder(),
      configuration: .init(address: .hostname(listen, port: port), availableConnectionsDelegate: MaximumAvailableConnections(32)),
      onServerRunning: { channel in onListening(channel.localAddress?.port ?? port) }
    )
    note("Serving Insteon at http://\(listen):\(port). Remote access requires an encrypted VPN.")
    let events = await service.events()
    let finalSave = try await service.run {
      try await withThrowingTaskGroup(of: Bool.self) { group in
        group.addTask {
          do { for try await event in events { onEvent(event) } } catch {}
          return false
        }
        group.addTask { try await app.runService(); return true }
        defer { group.cancelAll() }
        while let hostEnded = try await group.next(), !hostEnded {}
      }
    }
    if finalSave == .failed {
      note("The final network snapshot could not be saved.")
    }
  }

  @Sendable static func logConnectionChange(_ event: ServiceEvent) {
    switch event {
    case let .modemUnavailable(cause): note(cause.notice)
    case .modemReconnected: note("The Hub or modem is connected.")
    default: break
    }
  }

  private static func note(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
  }
}

/// Startup or connection failure with a credential-free description.
public enum ServerRunError: Error, CustomStringConvertible, Equatable {
  /// No gateway password was configured.
  case missingPassword
  /// The HTTP authentication policy refused the configured password.
  case invalidPassword

  /// A safe explanation for the person running the server.
  public var description: String {
    switch self {
    case .missingPassword: "Set INSTEON_GATEWAY_PASSWORD in the protected environment file."
    case .invalidPassword: "INSTEON_GATEWAY_PASSWORD must contain 32 through 1024 bytes with no control characters."
    }
  }
}
