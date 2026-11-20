import InsteonPluginKit

/// A transport that forwards a loopback port to the service and registers itself as a route.
///
/// This is the smallest transport that works: it adds no reach beyond the machine, because the
/// listener is on loopback. A real transport, over a tunnel or a relay, does the same two things:
/// it carries bytes to the service's loopback port, and it registers a `kind` and a `ticket` that
/// tell its own clients how to reach it. This one's ticket is the address it listens on.
public struct LoopbackTransport: Sendable {
  /// The route kind this transport registers.
  public static let kind = "loopback"

  private let forwarder: LoopbackForwarder
  private let registrar: RouteRegistrar
  private let kind: String

  /// Creates a transport.
  /// - Parameters:
  ///   - service: The service, with an `admin` token, for registering the route.
  ///   - upstreamPort: The service's loopback port.
  ///   - listenPort: The loopback port to accept on. 0 lets the system choose.
  ///   - kind: The route kind to register.
  public init(service: ServiceClient, upstreamPort: Int, listenPort: Int = 0, kind: String = LoopbackTransport.kind) {
    forwarder = LoopbackForwarder(upstreamPort: upstreamPort, listenPort: listenPort)
    registrar = RouteRegistrar(service: service)
    self.kind = kind
  }

  /// Forwards connections and keeps the route registered until the task is canceled, then removes the route.
  ///
  /// The route is registered once the listener accepts connections, so a client that reads the route
  /// can reach it. The route is removed when the transport stops for any reason, including a failed
  /// registration.
  ///
  /// - Parameter onRegistered: Called once with the port the transport accepts on, after the route is registered.
  /// - Throws: A ``PluginError`` when the route can't be registered, for example a token without the `admin` scope.
  public func run(onRegistered: @Sendable (Int) -> Void = { _ in }) async throws {
    let (ports, announce) = AsyncStream<Int>.makeStream()
    let forwarder = forwarder, registrar = registrar, kind = kind
    var failure: (any Error)?
    var registered = false
    do {
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
          defer { announce.finish() }
          try await forwarder.run { announce.yield($0) }
        }
        for await port in ports {
          try await registrar.register(kind: kind, ticket: "127.0.0.1:" + String(port))
          registered = true
          onRegistered(port)
          break
        }
        try await group.next()
        group.cancelAll()
      }
    } catch is CancellationError {
      // Stopped on purpose.
    } catch {
      failure = error
    }
    // The route is removed even when the task was canceled: the request isn't tied to cancellation.
    if registered { try? await registrar.unregister(kind: kind) }
    if let failure { throw failure }
  }
}
