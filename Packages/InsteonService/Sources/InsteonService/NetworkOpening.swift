import InsteonCore

/// Opens one connection to the modem at a time, for as long as the service needs it.
///
/// An opener makes a connection, builds the network that reaches devices through it from a
/// snapshot, runs a body with that network, and closes the connection when the body returns or
/// throws. If the connection fails while the body runs, the opener throws the connection's
/// error, as a Hub's modem session does.
public protocol NetworkOpening: Sendable {
  /// Opens a connection, runs `body` with a network built from `snapshot`, and closes it.
  func withNetwork(snapshot: NetworkSnapshot, _ body: @escaping @Sendable (DeviceNetwork) async throws -> Void) async throws
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
