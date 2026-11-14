import AsyncAlgorithms
import InsteonCore

/// A subscription combining passive device notifications and explicit command completions.
///
/// Subscribe before sending a command to observe its completion. Iterate from one task.
/// Each subscriber buffers up to 64 command completions; falling behind ends the sequence
/// with an error so the client can reconnect and refresh. Cancellation releases both readers.
public struct ServiceEvents: AsyncSequence, Sendable {
  /// A typed notification or a completed command with its confirmed result.
  public typealias Element = ServiceEvent

  private let monitor: MonitorEvents
  private let subscription: CommandEventSubscription

  init(monitor: AsyncStream<DeviceMonitorEvent>, subscription: CommandEventSubscription) {
    self.monitor = MonitorEvents(events: monitor.compactMap { ServiceEvent($0) }, subscription: subscription)
    self.subscription = subscription
  }

  /// Creates the subscription's single reader. Retain either the sequence or reader to
  /// keep receiving command completions.
  public func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(base: merge(monitor, subscription.stream).makeAsyncIterator(), subscription: subscription)
  }

  /// A reader that owns both upstream subscriptions for its lifetime.
  public struct AsyncIterator: AsyncIteratorProtocol {
    fileprivate var base: AsyncMerge2Sequence<MonitorEvents, AsyncThrowingStream<ServiceEvent, any Error>>.Iterator
    fileprivate let subscription: CommandEventSubscription

    /// Returns the next event, or ends when the modem closes or the reader is canceled.
    /// Throws if this subscriber fell behind its bounded completion queue.
    public mutating func next() async throws -> ServiceEvent? {
      try await base.next()
    }
  }
}

/// Indicates a gap in this subscription. Reconnect and refresh cached device information.
public enum ServiceEventError: Error {
  /// More than 64 command completions arrived before this client consumed them.
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
/// entries are pruned on the next subscription or command, without a detached cleanup task.
struct WeakCommandSubscription: Sendable {
  weak var value: CommandEventSubscription?
}

fileprivate struct MonitorEvents: AsyncSequence, Sendable {
  typealias Element = ServiceEvent
  let events: AsyncCompactMapSequence<AsyncStream<DeviceMonitorEvent>, ServiceEvent>
  let subscription: CommandEventSubscription

  func makeAsyncIterator() -> Iterator {
    Iterator(base: events.makeAsyncIterator(), subscription: subscription)
  }

  struct Iterator: AsyncIteratorProtocol {
    var base: AsyncCompactMapSequence<AsyncStream<DeviceMonitorEvent>, ServiceEvent>.AsyncIterator
    let subscription: CommandEventSubscription
    mutating func next() async -> ServiceEvent? {
      let event = await base.next()
      if event == nil { subscription.finish() }
      return event
    }
  }
}
