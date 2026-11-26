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
    private var live: (events: SequencedEvents.AsyncIterator, generation: Int)?
    private var failures = 0

    init(connection: ClientConnection, cursor: EventCursor?) {
      self.connection = connection
      self.cursor = cursor
    }

    /// Returns the next item, reconnecting as needed.
    ///
    /// - Throws: ``ConnectionError`` when the credential is refused on every path or its scope is
    ///   too low.
    public mutating func next() async throws -> SequencedItem? {
      while !Task.isCancelled {
        if live == nil {
          do {
            let subscription = try await connection.subscribe(after: cursor)
            live = (subscription.events.makeAsyncIterator(), subscription.generation)
          } catch is CancellationError {
            return nil
          } catch let error as ConnectionError {
            switch error {
            case .unauthorized, .forbidden: throw error
            default: guard await backOff() else { return nil }
            }
            continue
          }
        }
        guard var reading = live else { continue }
        do {
          let item = try await reading.events.next()
          live = (reading.events, reading.generation)
          if let item {
            failures = 0
            switch item {
            case let .event(_, position), let .position(position), let .gap(_, current: position): cursor = position
            }
            return item
          }
        } catch is CancellationError {
          return nil
        } catch ServiceEventError.slowConsumer {
          // The service ended this subscription, not the path: resubscribe on the same one.
        } catch {
          await connection.lost(reading.generation)
        }
        live = nil
        guard await backOff() else { return nil }
      }
      return nil
    }

    /// Waits before the next attempt. Returns `false` when canceled.
    private mutating func backOff() async -> Bool {
      let delays = connection.retryDelays
      let delay = delays[Swift.min(failures, delays.count - 1)]
      failures += 1
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
