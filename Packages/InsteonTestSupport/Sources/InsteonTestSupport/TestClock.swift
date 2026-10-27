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

  /// Sleeps and waits that have been issued an ID and haven't finished.
  private var pendingIDs: Set<Int> = []

  /// Pending sleeps and waits canceled before they started waiting.
  private var canceledIDs: Set<Int> = []

  private var sleeperWaiters: [(id: Int, deadline: Instant, continuation: CheckedContinuation<Void, Never>)] = []

  /// Creates a clock at its start.
  public init() {}

  /// The clock's current time.
  public var now: Instant { lock.withLock { current } }

  /// The smallest step the clock moves by: any duration.
  public var minimumResolution: Duration { .zero }

  /// Sleeps until the clock reaches a deadline.
  public func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {

    let id = makeID()

    try await withTaskCancellationHandler {

      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in

        let woken: [CheckedContinuation<Void, Never>] = lock.withLock {

          if canceledIDs.remove(id) != nil {

            pendingIDs.remove(id)
            continuation.resume(throwing: CancellationError())

            return []

          }

          if deadline <= current {

            pendingIDs.remove(id)
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

          // A sleep that already finished needs nothing; one that hasn't started yet stops
          // as it starts.
          if pendingIDs.contains(id) {

            canceledIDs.insert(id)

          }

          return nil

        }

        pendingIDs.remove(id)

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
      pendingIDs.subtract(due.map(\.id))

      return due

    }

    due.forEach { $0.continuation.resume() }

  }

  /// Waits until a task is sleeping until `offset` past the clock's start, or until the waiting
  /// task is canceled, for example by a test's time limit.
  public func waitForSleeper(until offset: Duration) async {

    let deadline = Instant(offset: offset)
    let id = makeID()

    await withTaskCancellationHandler {

      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in

        let ready = lock.withLock {

          guard
            canceledIDs.remove(id) == nil,
            !sleepers.contains(where: { $0.deadline == deadline })
          else {

            pendingIDs.remove(id)

            return true

          }

          sleeperWaiters.append((id, deadline, continuation))

          return false

        }

        if ready {

          continuation.resume()

        }

      }

    } onCancel: {

      let canceled: CheckedContinuation<Void, Never>? = lock.withLock {

        guard let index = sleeperWaiters.firstIndex(where: { $0.id == id }) else {

          if pendingIDs.contains(id) {

            canceledIDs.insert(id)

          }

          return nil

        }

        pendingIDs.remove(id)

        return sleeperWaiters.remove(at: index).continuation

      }

      canceled?.resume()

    }

  }

  private func makeID() -> Int {

    lock.withLock {

      defer { nextID += 1 }

      pendingIDs.insert(nextID)

      return nextID

    }

  }

  // Call while holding `lock`.
  private func takeSatisfiedWaiters() -> [CheckedContinuation<Void, Never>] {

    let deadlines = Set(sleepers.map(\.deadline))
    let satisfied = sleeperWaiters.filter { deadlines.contains($0.deadline) }
    sleeperWaiters.removeAll { deadlines.contains($0.deadline) }
    pendingIDs.subtract(satisfied.map(\.id))

    return satisfied.map(\.continuation)

  }

}
