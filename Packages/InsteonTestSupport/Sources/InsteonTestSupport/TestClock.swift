import Foundation

/// A clock that only moves when a test advances it, so timing in tests is deterministic.
///
/// Sleeping until a deadline that has already passed returns at once; any other sleep waits
/// for ``advance(by:)`` to reach its deadline, or for its task to be canceled.
public final class TestClock: Clock, @unchecked Sendable {

  /// A point in time, measured from the clock's start.
  public struct Instant: InstantProtocol {

    /// How far past the clock's start this instant is.
    public var offset: Duration

    /// Creates an instant.
    ///
    /// - Parameter offset: How far past the clock's start the instant is.
    public init(offset: Duration) {

      self.offset = offset

    }

    /// Returns the instant a duration later.
    public func advanced(by duration: Duration) -> Instant {

      Instant(offset: offset + duration)

    }

    /// Returns the duration until another instant.
    public func duration(to other: Instant) -> Duration {

      other.offset - offset

    }

    /// Returns whether one instant is earlier than another.
    public static func < (lhs: Instant, rhs: Instant) -> Bool {

      lhs.offset < rhs.offset

    }

  }

  private struct Sleeper {

    let id: Int

    let deadline: Instant

    let continuation: CheckedContinuation<Void, any Error>

  }

  // `lock` guards everything below it.
  private let lock = NSLock()

  private var current = Instant(offset: .zero)

  private var nextID = 0

  private var sleepers: [Sleeper] = []

  private var canceledIDs: Set<Int> = []

  private var sleeperWaiters: [(deadline: Instant, continuation: CheckedContinuation<Void, Never>)] = []

  /// Creates a clock at its start.
  public init() {}

  /// The clock's current time.
  public var now: Instant { lock.withLock { current } }

  /// The smallest step the clock moves by: any duration.
  public var minimumResolution: Duration { .zero }

  /// Sleeps until the clock reaches a deadline.
  public func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {

    let id = lock.withLock {

      defer { nextID += 1 }

      return nextID

    }

    try await withTaskCancellationHandler {

      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in

        let woken: [CheckedContinuation<Void, Never>] = lock.withLock {

          if canceledIDs.remove(id) != nil {

            continuation.resume(throwing: CancellationError())

            return []

          }

          if deadline <= current {

            continuation.resume()

            return []

          }

          sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))

          return takeSatisfiedWaiters()

        }

        woken.forEach { $0.resume() }

      }

    } onCancel: {

      let canceled: Sleeper? = lock.withLock {

        guard let index = sleepers.firstIndex(where: { $0.id == id }) else {

          canceledIDs.insert(id)

          return nil

        }

        return sleepers.remove(at: index)

      }

      canceled?.continuation.resume(throwing: CancellationError())

    }

  }

  /// Moves the clock forward, waking every sleeper whose deadline it reaches.
  public func advance(by duration: Duration) {

    let due: [Sleeper] = lock.withLock {

      current = current.advanced(by: duration)

      let due = sleepers.filter { $0.deadline <= current }
      sleepers.removeAll { $0.deadline <= current }

      return due

    }

    due.forEach { $0.continuation.resume() }

  }

  /// Waits until a task is sleeping until `offset` past the clock's start.
  public func waitForSleeper(until offset: Duration) async {

    let deadline = Instant(offset: offset)

    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in

      let ready = lock.withLock {

        guard !sleepers.contains(where: { $0.deadline == deadline }) else {

          return true

        }

        sleeperWaiters.append((deadline, continuation))

        return false

      }

      if ready {

        continuation.resume()

      }

    }

  }

  // Call while holding `lock`.
  private func takeSatisfiedWaiters() -> [CheckedContinuation<Void, Never>] {

    let deadlines = Set(sleepers.map(\.deadline))
    let satisfied = sleeperWaiters.filter { deadlines.contains($0.deadline) }
    sleeperWaiters.removeAll { deadlines.contains($0.deadline) }

    return satisfied.map(\.continuation)

  }

}
