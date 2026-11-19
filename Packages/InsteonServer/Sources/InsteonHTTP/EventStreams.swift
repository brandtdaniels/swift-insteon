/// How long and how many event streams the server keeps, so streams to vanished clients
/// release their connections and streams never take every connection the server accepts.
public struct EventStreamPolicy: Sendable, Equatable {
  /// Time between keepalive comments on an idle stream. Browsers and proxies see traffic, and a
  /// dead connection fails a write instead of staying quiet.
  public var heartbeatInterval: Duration
  /// Age at which the server ends a stream cleanly. A browser reconnects and refreshes its
  /// cards, and a stream whose client vanished without closing releases its connection.
  public var maximumLifetime: Duration
  /// Streams open at once. Opening one more ends the oldest, so a client that is still there
  /// takes the place of one that is not.
  public var maximumStreams: Int

  /// Creates a policy.
  public init(heartbeatInterval: Duration, maximumLifetime: Duration, maximumStreams: Int) {
    self.heartbeatInterval = heartbeatInterval
    self.maximumLifetime = maximumLifetime
    self.maximumStreams = maximumStreams
  }

  /// A keepalive every 15 seconds, a lifetime of 10 minutes and 16 streams, half of the
  /// connections ``ConnectionLimits/maximumConnections`` accepts.
  public static let standard = EventStreamPolicy(heartbeatInterval: .seconds(15), maximumLifetime: .seconds(600), maximumStreams: 16)
}

/// Counts open event streams and ends the oldest when a stream opens past the limit.
actor EventStreamRegistry {
  struct Lease: Sendable {
    fileprivate let id: Int
    fileprivate let clientID: String?
    /// Yields once if the registry ended this stream to make room.
    let evictions: AsyncStream<Void>
  }

  private let limit: Int
  private var nextID = 0
  private var open: [(id: Int, clientID: String?, evict: AsyncStream<Void>.Continuation)] = []

  init(limit: Int) { self.limit = max(limit, 1) }

  /// - Parameter clientID: The client that opened the stream, or `nil` for the gateway password.
  func admit(clientID: String? = nil) -> Lease {
    while open.count >= limit {
      let oldest = open.removeFirst()
      oldest.evict.yield()
      oldest.evict.finish()
    }
    let (evictions, evict) = AsyncStream<Void>.makeStream()
    defer { nextID += 1 }
    open.append((nextID, clientID, evict))
    return Lease(id: nextID, clientID: clientID, evictions: evictions)
  }

  /// How many streams the client has open.
  func openStreamCount(clientID: String) -> Int { open.filter { $0.clientID == clientID }.count }

  /// Ends every open stream the client opened.
  func end(clientID: String) {
    for stream in open where stream.clientID == clientID {
      stream.evict.yield()
      stream.evict.finish()
    }
    open.removeAll { $0.clientID == clientID }
  }

  func release(_ lease: Lease) {
    guard let index = open.firstIndex(where: { $0.id == lease.id }) else { return }
    open.remove(at: index).evict.finish()
  }
}
