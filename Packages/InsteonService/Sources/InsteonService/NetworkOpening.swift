import Foundation
import InsteonCore
import InsteonHubPro
import InsteonNetworking

/// Opens one connection to the network at a time, for as long as the service needs it.
///
/// An opener builds the network a connection reaches, runs a body with it, and closes the
/// connection when the body returns or throws.
public protocol ServedNetworkOpening: Sendable {
  /// Opens a connection like ``NetworkOpening/withNetwork(snapshot:onPollSucceeded:_:)``, and
  /// runs `body` with the network it reaches, served.
  func withServedNetwork(snapshot: NetworkSnapshot, onPollSucceeded: @escaping @Sendable () async -> Void, _ body: @escaping @Sendable (any ServedNetwork) async throws -> Void) async throws
}

/// Opens one connection to the modem at a time, for as long as the service needs it.
///
/// An opener makes a connection, builds the network that reaches devices through it from a
/// snapshot, runs a body with that network, and closes the connection when the body returns or
/// throws. If the connection fails while the body runs, the opener throws the connection's
/// error, as a Hub's modem session does.
public protocol NetworkOpening: ServedNetworkOpening {
  /// Opens a connection, runs `body` with a network built from `snapshot`, and closes it.
  func withNetwork(snapshot: NetworkSnapshot, _ body: @escaping @Sendable (DeviceNetwork) async throws -> Void) async throws

  /// Opens a connection like ``withNetwork(snapshot:_:)``, and calls `onPollSucceeded` each time
  /// the connection's modem answers a poll, whether or not the poll brought anything. A
  /// connection that doesn't poll never calls it. The default opens without reporting.
  func withNetwork(snapshot: NetworkSnapshot, onPollSucceeded: @escaping @Sendable () async -> Void, _ body: @escaping @Sendable (DeviceNetwork) async throws -> Void) async throws
}

extension NetworkOpening {
  public func withServedNetwork(snapshot: NetworkSnapshot, onPollSucceeded: @escaping @Sendable () async -> Void, _ body: @escaping @Sendable (any ServedNetwork) async throws -> Void) async throws {
    try await withNetwork(snapshot: snapshot, onPollSucceeded: onPollSucceeded) { network in try await body(ModemServedNetwork(network: network)) }
  }

  public func withNetwork(snapshot: NetworkSnapshot, onPollSucceeded: @escaping @Sendable () async -> Void, _ body: @escaping @Sendable (DeviceNetwork) async throws -> Void) async throws {
    try await withNetwork(snapshot: snapshot, body)
  }
}

/// An error an opener throws to end the service's run, because trying again can't help, such as
/// a configuration that names a device that doesn't exist. The run throws `underlying`.
public struct ConnectionRefusal: Error {
  /// The error the run throws.
  public let underlying: any Error

  /// Creates a refusal that ends the run with `underlying`.
  public init(_ underlying: any Error) {
    self.underlying = underlying
  }
}

/// Hands out a network whose connection the host keeps open.
struct FixedNetworkOpener: NetworkOpening {
  let network: DeviceNetwork

  func withNetwork(snapshot: NetworkSnapshot, _ body: @escaping @Sendable (DeviceNetwork) async throws -> Void) async throws {
    try await body(network)
  }
}

/// Opens a Hub Pro, polling its devices' levels.
///
/// Each connection reads the Hub Pro's settings and device list, describes its devices, and polls
/// every level at an interval. A poll that fails ends the connection, so the service reconnects
/// with its own backoff. Requests go to the Hub Pro one at a time.
public struct HubProOpener: ServedNetworkOpening {
  private let host: String
  private let port: Int
  private let catalog: ProductCatalog?
  private let httpClient: any HTTPClient
  private let pollInterval: Duration
  private let clock: any Clock<Duration>

  /// Creates an opener.
  ///
  /// - Parameters:
  ///   - host: The Hub Pro's host name or IP address.
  ///   - port: The port of its HTTP interface. Defaults to `HubProClient.defaultPort`.
  ///   - catalog: The catalog to describe devices with.
  ///   - httpClient: The client to send requests with. Defaults to `URLSessionHTTPClient.localNetwork()`.
  ///   - pollInterval: How long to wait between polls, at least `HubProNetwork.minimumPollInterval`.
  ///   - clock: The clock that times the polls.
  public init(
    host: String,
    port: Int = HubProClient.defaultPort,
    catalog: ProductCatalog?,
    httpClient: any HTTPClient = URLSessionHTTPClient.localNetwork(),
    pollInterval: Duration = HubProNetwork.defaultPollInterval,
    clock: any Clock<Duration> = ContinuousClock()
  ) {
    self.host = host
    self.port = port
    self.catalog = catalog
    self.httpClient = httpClient
    self.pollInterval = pollInterval
    self.clock = clock
  }

  public func withServedNetwork(snapshot: NetworkSnapshot, onPollSucceeded: @escaping @Sendable () async -> Void, _ body: @escaping @Sendable (any ServedNetwork) async throws -> Void) async throws {
    let transport = HubProTransport(host: host, port: port, httpClient: httpClient)
    let network = HubProNetwork(transport: transport, catalog: catalog, snapshot: snapshot, pollInterval: pollInterval, clock: clock, onPollSucceeded: onPollSucceeded)
    try await network.open()
    await onPollSucceeded()
    try await body(HubProServedNetwork(network: network))
  }
}
