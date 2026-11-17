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
  --help           Show this help without connecting.

  Settings are read from the same protected per-user environment file as insteon.
  A Hub uses INSTEON_HUB_HOST, INSTEON_HUB_PORT, INSTEON_HUB_USERNAME and
  INSTEON_HUB_PASSWORD. The website and API use the user name insteon and a
  separate INSTEON_GATEWAY_PASSWORD of 32 through 1024 bytes.

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
  public typealias ModemOpener = @Sendable (
    _ endpoint: ModemEndpoint,
    _ catalog: ProductCatalog,
    _ snapshot: NetworkSnapshot,
    _ body: @escaping @Sendable (DeviceNetwork) async throws -> Void
  ) async throws -> Void

  /// Opens the Hub or serial port the endpoint names.
  public static let openModem: ModemOpener = { endpoint, catalog, snapshot, body in
    switch endpoint {
    case let .hub(location, credentials):
      try await ModemSession.withHub(host: location.host, port: location.port, user: credentials.user, password: credentials.password, catalog: catalog) { session in
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

  /// Loads protected settings, opens one modem and serves until interrupted or disconnected.
  /// Supplied arguments, settings and lower-level errors are never written to a remote client.
  ///
  /// - Parameters:
  ///   - arguments: The command-line options after the program name.
  ///   - environment: The process environment, which an environment file adds to.
  ///   - logger: Receives progress notes, warnings and one record per HTTP request.
  ///   - openModem: Opens the modem. Defaults to ``openModem``.
  /// - Throws: A ``ServerFailure`` source error: describe it with ``ServerFailure/init(_:)``.
  public static func run(arguments: [String], environment: [String: String], logger: Logger = Logger(label: "insteon-server"), openModem: ModemOpener = ServerRunner.openModem) async throws {
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
    let snapshot: NetworkSnapshot
    do { snapshot = try store.loadNetwork() }
    catch let error as DeviceRegistryStoreError { throw ServerRunError.stateFileUnusable(path: options.statePath, reason: error) }
    let endpoint: ModemEndpoint
    switch target {
    case let .hub(host, port):
      let location = try ModemTarget.hubLocation(host: host, port: port)
      endpoint = .hub(location, try HubCredentials(environment: environment))
      logger.info("Starting: opening the Hub at \(location.host):\(location.port)")
    case let .serial(path):
      endpoint = .serial(path: path)
      logger.info("Starting: opening the serial port")
    }
    let state = RunState()
    do {
      try await openModem(endpoint, catalog, snapshot) { network in
        do {
          try await serve(network: network, snapshot: snapshot, store: store, options: options, authentication: authentication, logger: logger, state: state)
        } catch {
          await state.recordBodyFailure(error)
          throw error
        }
      }
    } catch let error as ServerRunError {
      throw error
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw await classify(error, state: state, endpoint: endpoint)
    }
  }

  /// Chooses what to report when the modem's scope ends with `thrown`. The reader's own error
  /// replaces the one the body threw, so the body's error is kept separately and weighed first.
  private static func classify(_ thrown: any Error, state: RunState, endpoint: ModemEndpoint) async -> any Error {
    let body = await state.bodyFailure
    if await state.ended || thrown is HubStoppedAnswering {
      return ServerRunError.disconnected(cause: ServerFailure.cause(of: thrown))
    }
    if let body = body as? ServerRunError { return body }
    // The body only saw the modem close when the reader failed first; the reader's error says why.
    let primary = (body as? ModemError == .connectionClosed ? nil : body) ?? thrown
    // A Hub that rejects the credentials can drop the connection too, so a rejection in either error wins.
    if ServerFailure.isRejectedHubCredentials(primary) { return primary }
    if ServerFailure.isRejectedHubCredentials(thrown) { return thrown }
    if case let .hub(location, _) = endpoint, !(await state.serving) {
      let unanswered = HubStoppedAnswering.isUnanswered(primary) || HubStoppedAnswering.isUnanswered(thrown)
      if unanswered || (primary as? ModemError).map({ if case .timedOut = $0 { true } else { false } }) == true {
        return ServerRunError.hubUnreachable(host: location.host, port: location.port)
      }
    }
    return primary
  }

  private static func serve(network: DeviceNetwork, snapshot: NetworkSnapshot, store: JSONFileDeviceRegistryStore, options: ServerOptions, authentication: HTTPAuthentication, logger: Logger, state: RunState) async throws {
    let service = InsteonService(network: network, persistence: NetworkSnapshotPersistence(store: store))
    let router = makeInsteonRouter(service: service, authentication: authentication, logger: logger)
    let app = Application(
      responder: router.buildResponder(),
      configuration: .init(address: .hostname(options.listen, port: options.port), availableConnectionsDelegate: MaximumAvailableConnections(32)),
      onServerRunning: { _ in
        // The modem answered and the listener accepts connections.
        await state.markServing()
        logger.info("Serving Insteon at http://\(options.listen):\(options.port). Remote access requires an encrypted VPN.")
      },
      logger: logger
    )
    do {
      let persistence = try await service.run { try await app.runService() }
      if persistence == .failed {
        logger.warning("The final network snapshot could not be saved.")
      }
    } catch ServiceLifecycleError.connectionEnded {
      await state.markEnded()
      throw ServerRunError.disconnected(cause: nil)
    } catch let error as IOError where error.errnoCode == EADDRINUSE {
      throw ServerRunError.portInUse(host: options.listen, port: options.port)
    }
  }
}

/// What the run has seen, which the reader's own error can hide from the error the modem's scope throws.
private actor RunState {
  private(set) var ended = false
  private(set) var serving = false
  private(set) var bodyFailure: (any Error)?
  func markEnded() { ended = true }
  func markServing() { serving = true }
  func recordBodyFailure(_ error: any Error) {
    if bodyFailure == nil, !(error is CancellationError) { bodyFailure = error }
  }
}

/// Startup or connection failure with a credential-free description.
public enum ServerRunError: Error, CustomStringConvertible, Equatable {
  /// No gateway password was configured.
  case missingPassword
  /// The HTTP authentication policy refused the configured password.
  case invalidPassword
  /// The Hub did not answer when the server started.
  case hubUnreachable(host: String, port: Int)
  /// Another program already listens on the server's address and port.
  case portInUse(host: String, port: Int)
  /// The state file exists but can't be used.
  case stateFileUnusable(path: String, reason: DeviceRegistryStoreError)
  /// The modem's event stream ended while the service was running, with the connection's own
  /// explanation when it gave one.
  case disconnected(cause: String?)

  /// A safe explanation for the person running the server.
  public var description: String { ServerFailure(self).message }
}
