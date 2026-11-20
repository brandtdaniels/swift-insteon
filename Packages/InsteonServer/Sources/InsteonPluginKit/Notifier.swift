import Foundation

/// How long a notifier waits before it tries again after a failure: it starts at `initial` and doubles
/// up to `maximum`.
public struct RetryPolicy: Sendable, Equatable {
  /// The wait after the first failure.
  public var initial: Duration
  /// The longest wait.
  public var maximum: Duration

  /// Creates a policy.
  public init(initial: Duration, maximum: Duration) {
    self.initial = initial
    self.maximum = maximum
  }

  /// One second, doubling up to a minute.
  public static let standard = RetryPolicy(initial: .seconds(1), maximum: .seconds(60))

  /// The wait after `failures` failures in a row, which is at least 1.
  public func delay(afterFailures failures: Int) -> Duration {
    var delay = initial
    for _ in 1..<max(failures, 1) where delay < maximum { delay = min(delay * 2, maximum) }
    return min(delay, maximum)
  }
}

/// What a notifier tells its host, for a log or a test. It never carries a token.
public enum NotifierReport: Sendable, Equatable {
  /// The service accepted the connection, so notifications from here on reach the notifier.
  case connected
  /// The notification with this id reached the deliverer.
  case delivered(id: String)
  /// The deliverer failed for the notification with this id. The notifier waits, then tries again.
  case deliveryFailed(id: String, attempt: Int)
  /// The stream ended with an error. The notifier waits, then reconnects from its place.
  case disconnected
  /// The service can't replay what the notifier missed, so notifications may have been lost. They can't be
  /// recovered. `rules` is how many rules the service holds, or `nil` when it couldn't be asked.
  case gap(rules: Int?)
}

/// Follows the service's event stream and hands each `notification` to a ``Deliverer`` once.
///
/// The notifier is an ordinary client with a `read` token. It records the id of the last event it acted
/// on, and reconnects with it as `Last-Event-ID`, so a restart delivers nothing twice. A notification it
/// has already delivered is skipped even if the service sends it again. A delivery that fails is retried
/// with backoff on the injected clock; the service never waits for it. A `gap` means notifications may
/// have been lost and can't be replayed: the notifier re-lists the rules, reports it and continues from
/// the stream's current position.
///
/// Delivery is exactly once while the notifier runs. If the process dies between a delivery and the
/// write of its id, that one notification is delivered again after the restart.
public struct Notifier<Source: NotificationStreaming>: Sendable {
  private let source: Source
  private let deliverer: any Deliverer
  private let state: any NotifierStateStoring
  private let clock: any Clock<Duration>
  private let retry: RetryPolicy
  private let includesDetail: Bool
  private let report: @Sendable (NotifierReport) -> Void

  /// Creates a notifier.
  /// - Parameters:
  ///   - source: The service's events.
  ///   - deliverer: The delivery channel.
  ///   - state: Where the last event id is kept.
  ///   - clock: What backoff waits on.
  ///   - retry: The backoff.
  ///   - includesDetail: Whether a payload names the device and the event. Off by default: a payload carries the rule's name and the time.
  ///   - report: Receives what happens, for a log.
  public init(
    source: Source,
    deliverer: any Deliverer,
    state: any NotifierStateStoring,
    clock: any Clock<Duration> = ContinuousClock(),
    retry: RetryPolicy = .standard,
    includesDetail: Bool = false,
    report: @escaping @Sendable (NotifierReport) -> Void = { _ in }
  ) {
    self.source = source
    self.deliverer = deliverer
    self.state = state
    self.clock = clock
    self.retry = retry
    self.includesDetail = includesDetail
    self.report = report
  }

  /// Follows the stream until the task is canceled.
  ///
  /// A stream that ends or fails is followed again from the notifier's place, with backoff after a failure.
  ///
  /// - Throws: ``PluginError/unauthorized(status:code:)`` when the service refuses the token, because
  ///   waiting can't fix it; a ``NotifierStateError`` when the id can't be kept, because delivering
  ///   without it could repeat notifications; or `CancellationError`.
  public func run() async throws {
    var cursor = try state.lastEventID()
    var delivered = cursor.flatMap(StreamPosition.init)
    var failures = 0
    while true {
      try Task.checkCancellation()
      do {
        for try await item in source.events(after: cursor) {
          failures = 0
          switch item {
          case .connected:
            report(.connected)
          case let .notification(notification):
            if let position = StreamPosition(notification.id), let delivered, !position.follows(delivered) {
              cursor = notification.id
              continue
            }
            try await deliver(notification)
            cursor = notification.id
            delivered = StreamPosition(notification.id)
            try state.record(lastEventID: notification.id)
          case let .gap(id):
            report(.gap(rules: try? await source.ruleCount()))
            if let id {
              cursor = id
              delivered = StreamPosition(id)
              try state.record(lastEventID: id)
            }
          case let .other(id):
            if let id { cursor = id }
          }
        }
      } catch let error as PluginError {
        if case .unauthorized = error { throw error }
        failures += 1
        report(.disconnected)
        try await clock.sleep(for: retry.delay(afterFailures: failures))
      }
    }
  }

  private func deliver(_ notification: NotificationEvent) async throws {
    let payload = DeliveryPayload(
      ruleName: notification.ruleName,
      firedAt: notification.firedAt,
      address: includesDetail ? notification.address : nil,
      event: includesDetail ? notification.event : nil
    )
    var attempt = 0
    while true {
      do {
        try await deliverer.deliver(payload)
        report(.delivered(id: notification.id))
        return
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        attempt += 1
        report(.deliveryFailed(id: notification.id, attempt: attempt))
        try await clock.sleep(for: retry.delay(afterFailures: attempt))
      }
    }
  }
}
