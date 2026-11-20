import NIOCore
import NIOPosix

/// Accepts TCP connections on a loopback port of its own and passes each one, byte for byte, to the
/// service's loopback port.
///
/// It reads no HTTP, so everything the service's contract does reaches a remote client unchanged:
/// authentication and scopes, `Idempotency-Key` replay, and event streams that stay open and resume
/// with `Last-Event-ID`. A connection ends when either side closes it or the forwarder stops.
public struct LoopbackForwarder: Sendable {
  private let upstreamPort: Int
  private let listenPort: Int

  /// Creates a forwarder.
  /// - Parameters:
  ///   - upstreamPort: The service's loopback port.
  ///   - listenPort: The loopback port to accept on. 0 lets the system choose.
  public init(upstreamPort: Int, listenPort: Int = 0) {
    self.upstreamPort = upstreamPort
    self.listenPort = listenPort
  }

  /// Accepts and forwards connections until the task is canceled, which closes them all.
  ///
  /// - Parameter onListening: Called once with the port the forwarder accepts on.
  /// - Throws: An error when the port can't be bound.
  public func run(onListening: @Sendable (Int) -> Void) async throws {
    let listener = try await ServerBootstrap(group: NIOSingletons.posixEventLoopGroup)
      .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
      .bind(host: "127.0.0.1", port: listenPort) { channel in
        channel.eventLoop.makeCompletedFuture { try NIOAsyncChannel<ByteBuffer, ByteBuffer>(wrappingChannelSynchronously: channel) }
      }
    onListening(listener.channel.localAddress?.port ?? listenPort)
    let upstreamPort = upstreamPort
    try await listener.executeThenClose { connections in
      await withDiscardingTaskGroup { group in
        do {
          for try await connection in connections {
            group.addTask { await Self.forward(connection, toUpstreamPort: upstreamPort) }
          }
        } catch {
          // The listener closed; the connections in flight end with the group.
        }
      }
    }
  }

  /// Joins one accepted connection to a new connection to the service and copies both ways.
  private static func forward(_ client: NIOAsyncChannel<ByteBuffer, ByteBuffer>, toUpstreamPort port: Int) async {
    do {
      // The accepted connection is closed on every path out, including a service that doesn't answer.
      try await client.executeThenClose { clientInbound, clientOutbound in
        let upstream = try await ClientBootstrap(group: NIOSingletons.posixEventLoopGroup)
          .connect(host: "127.0.0.1", port: port) { channel in
            channel.eventLoop.makeCompletedFuture { try NIOAsyncChannel<ByteBuffer, ByteBuffer>(wrappingChannelSynchronously: channel) }
          }
        try await upstream.executeThenClose { upstreamInbound, upstreamOutbound in
          try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { for try await bytes in clientInbound { try await upstreamOutbound.write(bytes) } }
            group.addTask { for try await bytes in upstreamInbound { try await clientOutbound.write(bytes) } }
            // The first side to end ends the connection.
            _ = try await group.next()
            group.cancelAll()
          }
        }
      }
    } catch {
      // The connection ended or the service refused it; there is nobody to tell.
    }
  }
}
