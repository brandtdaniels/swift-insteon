import Foundation
import Hummingbird
import HummingbirdCore
import InsteonCLISupport
import InsteonCore
import InsteonGateway

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

  /// Loads protected settings, opens one modem and serves until interrupted or disconnected.
  /// Supplied arguments, settings and lower-level errors are never written to a remote client.
  public static func run(arguments: [String], environment: [String: String]) async throws {
    let options = try ServerOptions(arguments: arguments, environment: environment)
    let environment = try EnvironmentFile.load(explicitPath: options.envFilePath, environment: environment, warn: note)
    let target = try ModemTarget.resolve(hub: options.hub, serialPath: options.serialPath, environment: environment)
    guard let password = environment["INSTEON_GATEWAY_PASSWORD"] else { throw ServerRunError.missingPassword }
    // Validate server authentication before opening any hardware connection.
    _ = try Gateway(controller: UnavailableController(), password: password)
    let catalog = try ProductCatalog.load(contentsOf: ProductCatalog.bundledCatalogURL())
    let store = JSONFileDeviceRegistryStore(fileURL: URL(fileURLWithPath: options.statePath))
    let snapshot = try store.loadNetwork()
    switch target {
    case let .hub(host, port):
      let location = try ModemTarget.hubLocation(host: host, port: port)
      let credentials = try HubCredentials(environment: environment)
      note("Opening the Hub at \(location.host):\(location.port)")
      try await ModemSession.withHub(host: location.host, port: location.port, user: credentials.user, password: credentials.password, catalog: catalog) { session in
        try await serve(session: session, catalog: catalog, snapshot: snapshot, store: store, options: options, password: password)
      }
    case let .serial(path):
      #if os(macOS) || os(Linux)
      try await ModemSession.withSerialPort(path: path, catalog: catalog) { session in
        try await serve(session: session, catalog: catalog, snapshot: snapshot, store: store, options: options, password: password)
      }
      #else
      throw ConfigurationError.serialUnavailable
      #endif
    }
  }

  private static func serve(session: ModemSession, catalog: ProductCatalog, snapshot: NetworkSnapshot, store: JSONFileDeviceRegistryStore, options: ServerOptions, password: String) async throws {
    let network = session.network(catalog: catalog, snapshot: snapshot, hub: session.hub)
    _ = try await network.modemInfo()
    _ = try await network.modemDatabase()
    let controller = NetworkGatewayController(network: network, store: store)
    try await controller.save()
    let gateway = try Gateway(controller: controller, password: password)
    let app = Application(
      responder: GatewayHTTPResponder(gateway: gateway, controller: controller),
      configuration: .init(address: .hostname(options.listen, port: options.port), availableConnectionsDelegate: MaximumAvailableConnections(32))
    )
    note("Serving Insteon at http://\(options.listen):\(options.port). Remote access requires an encrypted VPN.")
    do {
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { try await app.runService() }
        group.addTask {
          // Consume events throughout the service's life, so identities are learned even
          // without a remote subscriber. Passive events don't invent device status readings.
          for await _ in await controller.events() {
            try Task.checkCancellation()
          }
          try Task.checkCancellation()
          throw ServerRunError.disconnected
        }
        defer { group.cancelAll() }
        _ = try await group.next()
      }
    } catch {
      try? await controller.save()
      throw error
    }
    try await controller.save()
  }

  private static func note(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
  }
}

/// Startup or connection failure with a credential-free description.
public enum ServerRunError: Error, CustomStringConvertible {
  /// No gateway password was configured.
  case missingPassword
  /// The modem's event stream ended while the service was running.
  case disconnected

  /// A safe explanation for the person running the server.
  public var description: String {
    switch self {
    case .missingPassword: "Set INSTEON_GATEWAY_PASSWORD in the protected environment file."
    case .disconnected: "The modem connection ended. Restart the service after checking the Hub or modem."
    }
  }
}

/// Validates gateway configuration before any device can be reached.
private struct UnavailableController: GatewayControlling {
  func devices() async throws -> [GatewayDevice] { throw ServerRunError.disconnected }
  func perform(_ command: GatewayCommand) async throws -> GatewayCommandResult { throw ServerRunError.disconnected }
}
