import Foundation
import InsteonModem

/// A wire tracer that keeps what it is given, for tests that check what a library traces.
public final class RecordingWireTrace: WireTrace, @unchecked Sendable {

  /// One call to ``trace(_:_:at:)``.
  public struct Event: Equatable, Sendable {

    /// What the bytes were.
    public let direction: WireTraceDirection

    /// The bytes.
    public let bytes: [UInt8]

    /// Creates an event.
    public init(direction: WireTraceDirection, bytes: [UInt8]) {

      self.direction = direction
      self.bytes = bytes

    }

  }

  // `lock` guards `recorded`.
  private let lock = NSLock()

  private var recorded: [Event] = []

  /// Creates a tracer with nothing recorded.
  public init() {}

  /// The events so far, oldest first.
  public var events: [Event] {

    lock.withLock { recorded }

  }

  /// Records the event.
  public func trace(_ direction: WireTraceDirection, _ bytes: [UInt8], at instant: ContinuousClock.Instant) {

    lock.withLock { recorded.append(Event(direction: direction, bytes: bytes)) }

  }

}
