import InsteonService

/// What a client reads from ``ClientConnection/events()``.
public enum ClientEvent: Equatable, Sendable {

  /// Something happened.
  case event(ServiceEvent)

  /// The client missed events the service can't replay, for the reason given. Refresh everything
  /// displayed; the events that follow are the service's present ones.
  case refresh(EventGapReason)

}

/// The service's numbered events over a ``ClientConnection``, from ``ClientConnection/sequencedEvents(after:)``.
///
/// Iterate from one task. Each step reads the open subscription; when the path is lost, it waits on
/// the connection's clock, reaches a path again and resumes after the last cursor it returned.
public struct ConnectionEvents: AsyncSequence, Sendable {

  /// An event with its cursor, a position, or a gap.
  public typealias Element = SequencedItem

  let connection: ClientConnection
  let start: EventCursor?

  /// Creates the single reader.
  public func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(connection: connection, cursor: start)
  }

  /// The reader. It stops, returning `nil`, when its task is canceled.
  public struct AsyncIterator: AsyncIteratorProtocol {

    let connection: ClientConnection
    var cursor: EventCursor?
    private var live: (events: SequencedEvents.AsyncIterator, generation: Int, path: String)?
    private var failures = 0
    /// Whether the reader has subscribed before, so a subscription with no cursor is a resubscription.
    private var hasSubscribed = false
    /// Whether events may have been missed before the next position is known.
    private var missedBeforePosition = false
    private var queued: SequencedItem?

    init(connection: ClientConnection, cursor: EventCursor?) {
      self.connection = connection
      self.cursor = cursor
    }

    /// Returns the next item, reconnecting as needed.
    ///
    /// A subscription lost before any item arrived resumes with no cursor, so what happened in
    /// between can't be replayed: the reader returns a gap saying so first.
    ///
    /// - Throws: ``ConnectionError`` when the credential is refused or its scope is too low, on
    ///   every path or on the one in use, or when no path carries events.
    public mutating func next() async throws -> SequencedItem? {
      if let item = queued {
        queued = nil
        return item
      }
      while !Task.isCancelled {
        if live == nil {
          do {
            let subscription = try await connection.subscribe(after: cursor)
            live = (subscription.events.makeAsyncIterator(), subscription.generation, subscription.path)
            if hasSubscribed, cursor == nil { missedBeforePosition = true }
            hasSubscribed = true
          } catch is CancellationError {
            return nil
          } catch let error as ConnectionError {
            switch error {
            case .unauthorized, .forbidden, .unsupported: throw error
            default: guard await backOff(growing: true) else { return nil }
            }
            continue
          }
        }
        guard var reading = live else { continue }
        var growing = true
        do {
          let item = try await reading.events.next()
          live = (reading.events, reading.generation, reading.path)
          if let item {
            failures = 0
            return try remember(item)
          }
          // The service closed the subscription cleanly: not a failure, and the path is kept.
          growing = false
        } catch is CancellationError {
          return nil
        } catch ServiceEventError.slowConsumer {
          // The service ended this subscription, not the path: resubscribe on the same one.
        } catch ConnectionPathError.unauthorized {
          // A path that only carries a refused credential isn't lost: the credential is the problem.
          throw ConnectionError.unauthorized(paths: [reading.path])
        } catch ConnectionPathError.forbidden {
          throw ConnectionError.forbidden(path: reading.path)
        } catch {
          await connection.lost(reading.generation)
        }
        live = nil
        guard await backOff(growing: growing) else { return nil }
      }
      return nil
    }

    /// Notes the cursor an item moves to, and returns the item, or a gap in front of it when events
    /// may have been missed before the service said where it stands.
    private mutating func remember(_ item: SequencedItem) throws -> SequencedItem {
      let place: EventCursor
      switch item {
      case let .event(_, position), let .position(position), let .gap(_, current: position): place = position
      }
      cursor = place
      guard missedBeforePosition else { return item }
      missedBeforePosition = false
      if case .gap = item { return item }
      if case .position = item { return .gap(.tooOld, current: place) }
      queued = item
      return .gap(.tooOld, current: place)
    }

    /// Waits before the next attempt. Returns `false` when canceled. A wait that follows a failure
    /// is longer each time in a row; one that follows a clean end is always the first.
    private mutating func backOff(growing: Bool) async -> Bool {
      let delays = connection.retryDelays
      let delay = delays[Swift.min(failures, delays.count - 1)]
      failures = growing ? failures + 1 : 0
      do {
        try await connection.clock.sleep(for: delay)
        return true
      } catch {
        return false
      }
    }

  }

}

/// The service's events over a ``ClientConnection``, from ``ClientConnection/events()``, without
/// the numbering. It reconnects as ``ConnectionEvents`` does.
public struct ClientEvents: AsyncSequence, Sendable {

  /// An event, or a notice to refresh.
  public typealias Element = ClientEvent

  let base: ConnectionEvents

  /// Creates the single reader.
  public func makeAsyncIterator() -> AsyncIterator { AsyncIterator(base: base.makeAsyncIterator()) }

  /// The reader. It stops, returning `nil`, when its task is canceled.
  public struct AsyncIterator: AsyncIteratorProtocol {

    var base: ConnectionEvents.AsyncIterator

    /// Returns the next event or refresh notice, leaving out positions.
    public mutating func next() async throws -> ClientEvent? {
      while let item = try await base.next() {
        switch item {
        case let .event(event, _): return .event(event)
        case .position: continue
        case let .gap(reason, _): return .refresh(reason)
        }
      }
      return nil
    }

  }

}
