import Hummingbird
import HummingbirdCore
import NIOCore

/// Connection-level limits for the HTTP listener.
public enum ConnectionLimits {
  /// Connections the listener accepts at once. Further clients wait until one closes.
  public static let maximumConnections = 32
  /// Time a connection may sit without receiving a request, or without completing the headers
  /// of one. A client that connects and says nothing, or trickles a header, loses its slot.
  /// A response being written, such as an event stream, is not idle.
  public static let idleTimeout: TimeAmount = .seconds(30)
  /// Time one write may stay unfinished before the connection closes. A client that stops
  /// reading releases its connection.
  public static let writeTimeout: TimeAmount = .seconds(30)

  /// The listener's HTTP/1.1 channel with the idle and write timeouts applied.
  public static var server: HTTPServerBuilder {
    .http1(configuration: .init(additionalChannelHandlers: [WriteStallHandler(timeout: writeTimeout)], idleTimeout: idleTimeout))
  }
}

/// Closes a connection when a write has not completed within a timeout.
final class WriteStallHandler: ChannelOutboundHandler, RemovableChannelHandler {
  typealias OutboundIn = NIOAny
  typealias OutboundOut = NIOAny

  private let timeout: TimeAmount

  init(timeout: TimeAmount) { self.timeout = timeout }

  func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
    let completion = promise ?? context.eventLoop.makePromise(of: Void.self)
    let stalled = context.eventLoop.assumeIsolated().scheduleTask(in: timeout) { context.close(promise: nil) }
    completion.futureResult.assumeIsolated().whenComplete { _ in stalled.cancel() }
    context.write(data, promise: completion)
  }
}
