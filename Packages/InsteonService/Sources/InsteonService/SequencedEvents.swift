/// A position in the service's stream of events: the run that numbered it and its number.
///
/// A run is one start of the service. Its events are numbered 1, 2, 3 and so on, and the numbers
/// restart with a new run, so a number means something only with its run.
public struct EventCursor: Hashable, Sendable {
  /// Names the run. An opaque token of letters and digits, different for every start.
  public let runID: String
  /// The event's number in the run. A cursor before the first event has number 0.
  public let sequence: UInt64

  /// A cursor that stands for an id the server can't read. It never matches a run.
  public static let unrecognized = EventCursor(runID: "", sequence: 0)

  /// Creates a cursor.
  public init(runID: String, sequence: UInt64) {
    self.runID = runID
    self.sequence = sequence
  }

  /// The cursor as one token, the run then a hyphen then the number, such as `9f3a0c41d27e5b86-42`.
  public var token: String { "\(runID)-\(sequence)" }

  /// Reads a token made by ``token``.
  ///
  /// - Returns: `nil` unless the text is a run of letters and digits, one hyphen and a number.
  public init?(token: String) {
    let parts = token.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 2, !parts[0].isEmpty, parts[0].count <= 64,
          parts[0].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
          !parts[1].isEmpty, parts[1].allSatisfy(\.isASCII), parts[1].allSatisfy(\.isNumber),
          let sequence = UInt64(parts[1]) else { return nil }
    self.init(runID: String(parts[0]), sequence: sequence)
  }
}

/// Why a reconnecting client can't be given what it missed.
public enum EventGapReason: String, CaseIterable, Sendable, Equatable {
  /// The client's run isn't this one: the service restarted, or the id isn't one the service made.
  case otherRun
  /// The service doesn't keep the events the client missed.
  case tooOld
  /// The client's number is beyond the newest event of this run.
  case ahead
}

/// One item of a sequenced subscription.
public enum SequencedItem: Equatable, Sendable {
  /// An event and its place in the run.
  case event(ServiceEvent, EventCursor)
  /// Where a subscription with no cursor starts: the run's newest number. Nothing happened at it;
  /// a client keeps it as its place, so it can resume even if no event arrives before it reconnects.
  case position(EventCursor)
  /// The client missed events the service can't replay. It refreshes everything it displays, and
  /// the events that follow are the run's, from `current`.
  case gap(EventGapReason, current: EventCursor)
}

/// A subscription whose events are numbered, which a client can resume.
///
/// Iterate from one task. Each subscriber buffers 64 events beyond what it is replayed; falling
/// behind ends the sequence with ``ServiceEventError/slowConsumer``, and the client reconnects
/// from the last number it saw. Cancellation releases the reader.
public struct SequencedEvents: AsyncSequence, Sendable {
  /// An event with its cursor, or a gap.
  public typealias Element = SequencedItem

  private let stream: AsyncThrowingStream<SequencedItem, any Error>
  private let owner: CommandEventSubscription?

  init(subscription: CommandEventSubscription) {
    stream = subscription.stream
    owner = subscription
  }

  /// Wraps a stream of items, for a service that numbers its own events.
  public init(_ stream: AsyncThrowingStream<SequencedItem, any Error>) {
    self.stream = stream
    owner = nil
  }

  /// Creates the subscription's single reader.
  public func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(base: stream.makeAsyncIterator(), owner: owner)
  }

  /// A reader that owns the subscription for its lifetime.
  public struct AsyncIterator: AsyncIteratorProtocol {
    fileprivate var base: AsyncThrowingStream<SequencedItem, any Error>.Iterator
    fileprivate let owner: CommandEventSubscription?

    /// Returns the next item, or ends when the reader is canceled.
    /// Throws if this subscriber fell behind its bounded queue.
    public mutating func next() async throws -> SequencedItem? {
      try await base.next()
    }
  }
}
