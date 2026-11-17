import InsteonCore

/// Opens one connection to the modem at a time, for as long as the service needs it.
///
/// An opener makes a connection, builds the network that reaches devices through it from a
/// snapshot, runs a body with that network, and closes the connection when the body returns or
/// throws. If the connection fails while the body runs, the opener throws the connection's
/// error, as `ModemSession/withHub(host:port:user:password:catalog:_:)` does.
public protocol NetworkOpening: Sendable {
  /// Opens a connection, runs `body` with a network built from `snapshot`, and closes it.
  func withNetwork(snapshot: NetworkSnapshot, _ body: @escaping @Sendable (DeviceNetwork) async throws -> Void) async throws
}

/// Opens a `ModemSession` for each attempt, such as a Hub's or a serial modem's.
public struct ModemSessionOpener: NetworkOpening {
  /// Opens a session, runs the body with it, and closes it.
  public typealias Open = @Sendable (_ body: @escaping @Sendable (ModemSession) async throws -> Void) async throws -> Void

  private let catalog: ProductCatalog?
  private let open: Open

  /// Creates an opener.
  ///
  /// - Parameters:
  ///   - catalog: The catalog that describes the devices behind the modem.
  ///   - open: Opens a session with a call such as `ModemSession/withHub(host:port:user:password:catalog:_:)`.
  public init(catalog: ProductCatalog?, open: @escaping Open) {
    self.catalog = catalog
    self.open = open
  }

  /// Opens a session and runs the body with the network it makes.
  public func withNetwork(snapshot: NetworkSnapshot, _ body: @escaping @Sendable (DeviceNetwork) async throws -> Void) async throws {
    let catalog = catalog
    try await open { session in
      try await body(session.network(catalog: catalog, snapshot: snapshot, hub: session.hub))
    }
  }
}

/// Hands out a network whose connection the host keeps open.
struct FixedNetworkOpener: NetworkOpening {
  let network: DeviceNetwork

  func withNetwork(snapshot: NetworkSnapshot, _ body: @escaping @Sendable (DeviceNetwork) async throws -> Void) async throws {
    try await body(network)
  }
}
