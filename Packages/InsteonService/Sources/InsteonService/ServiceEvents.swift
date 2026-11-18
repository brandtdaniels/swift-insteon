/// A subscription to the service's passive device notifications, command completions and
/// changes in whether the modem is reachable.
///
/// Subscribe before sending a command to observe its completion. Iterate from one task. Each
/// subscriber buffers up to 64 events; falling behind ends the sequence with an error so the
/// client can reconnect and refresh. The subscription survives the modem going away and coming
/// back: it carries ``ServiceEvent/modemUnavailable(_:)`` and ``ServiceEvent/modemReconnected``.
/// Cancellation releases the reader.
public struct ServiceEvents: AsyncSequence, Sendable {
  /// A typed notification, a completed command with its confirmed result, or a change in the
  /// modem's availability.
  public typealias Element = ServiceEvent

  private let subscription: CommandEventSubscription

  init(subscription: CommandEventSubscription) {
    self.subscription = subscription
  }

  /// Creates the subscription's single reader. Retain either the sequence or reader to
  /// keep receiving events.
  public func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(base: subscription.stream.makeAsyncIterator(), subscription: subscription)
  }

  /// A reader that owns the subscription for its lifetime.
  public struct AsyncIterator: AsyncIteratorProtocol {
    fileprivate var base: AsyncThrowingStream<ServiceEvent, any Error>.Iterator
    fileprivate let subscription: CommandEventSubscription

    /// Returns the next event, or ends when the reader is canceled.
    /// Throws if this subscriber fell behind its bounded queue.
    public mutating func next() async throws -> ServiceEvent? {
      try await base.next()
    }
  }
}

/// Indicates a gap in this subscription. Reconnect and refresh cached device information.
public enum ServiceEventError: Error {
  /// More than 64 events arrived before this client consumed them.
  case slowConsumer
}

/// Immutable ownership of a continuation is Sendable; no task is launched by a subscription.
final class CommandEventSubscription: Sendable {
  let stream: AsyncThrowingStream<ServiceEvent, any Error>
  private let continuation: AsyncThrowingStream<ServiceEvent, any Error>.Continuation

  init() {
    (stream, continuation) = AsyncThrowingStream.makeStream(bufferingPolicy: .bufferingOldest(64))
  }

  func publish(_ event: ServiceEvent) -> Bool {
    switch continuation.yield(event) {
    case .enqueued: return true
    case .dropped:
      continuation.finish(throwing: ServiceEventError.slowConsumer)
      return false
    case .terminated: return false
    @unknown default: return false
    }
  }

  func finish() { continuation.finish() }
}

/// The service doesn't retain abandoned subscriptions or their buffered events. Dead weak
/// entries are pruned on the next subscription or event, without a detached cleanup task.
struct WeakCommandSubscription: Sendable {
  weak var value: CommandEventSubscription?
}
