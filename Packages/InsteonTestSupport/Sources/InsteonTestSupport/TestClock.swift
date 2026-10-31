import Foundation

/// A clock that only moves when a test advances it, so timing in tests is deterministic.
///
/// Sleeping until a deadline that has already passed returns at once; any other sleep waits
/// for ``advance(by:)`` to reach its deadline, or for its task to be canceled.
///
/// A test waits for the code it runs to start sleeping with ``waitForSleeper(until:after:)``
/// before it advances the clock. When an earlier sleep may still be waiting at the same
/// deadline, such as an earlier exchange's timeout, the test takes a ``mark()`` first and waits
/// for a sleep that starts after it, or waits for a number of sleepers with
/// ``waitForSleepers(_:until:)``.
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

  /// A point in the order sleeps start in, from ``mark()``.
  public struct Mark: Hashable, Sendable {

    /// How many sleeps had started waiting when the mark was taken.
    fileprivate let started: Int

  }

  private struct Sleeper {

    let id: Int

    /// Its place in the order sleeps started waiting in, from 0.
    let order: Int

    let deadline: Instant

    let continuation: CheckedContinuation<Void, any Error>

  }

  // `lock` guards everything below it.
  private let lock = NSLock()

  private var current = Instant(offset: .zero)

  private var nextID = 0

  private var sleepers: [Sleeper] = []

  /// How many sleeps have started waiting, so far.
  private var started = 0

  /// Sleeps and waits that have been issued an ID and haven't finished.
  private var pendingIDs: Set<Int> = []

  /// Pending sleeps and waits canceled before they started waiting.
  private var canceledIDs: Set<Int> = []

  private struct SleeperWaiter {

    let id: Int

    let deadline: Instant

    /// The order from which a sleep counts.
    let startedFrom: Int

    /// How many sleepers it waits for.
    let count: Int

    let continuation: CheckedContinuation<Void, Never>

  }

  private var sleeperWaiters: [SleeperWaiter] = []

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

          sleepers.append(Sleeper(id: id, order: started, deadline: deadline, continuation: continuation))
          started += 1

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

  /// Returns how many tasks are sleeping until `offset` past the clock's start.
  ///
  /// - Parameter offset: The deadline, as a duration past the clock's start.
  /// - Returns: The number of sleepers.
  public func sleeperCount(until offset: Duration) -> Int {

    let deadline = Instant(offset: offset)

    return lock.withLock { sleepers.filter { $0.deadline == deadline }.count }

  }

  /// Marks the point in the order sleeps start in, for ``waitForSleeper(until:after:)``.
  ///
  /// Take the mark before starting what should sleep, so its sleep comes after the mark.
  ///
  /// - Returns: The mark.
  public func mark() -> Mark {

    lock.withLock { Mark(started: started) }

  }

  /// Waits until a task is sleeping until `offset` past the clock's start, or until the waiting
  /// task is canceled, for example by a test's time limit.
  ///
  /// Any task sleeping until the deadline counts, even one that started sleeping before the
  /// call. To wait for a sleep that starts later, while an earlier one may still be waiting at
  /// the same deadline, pass a mark taken before the later sleep could start.
  ///
  /// - Parameters:
  ///   - offset: The deadline, as a duration past the clock's start.
  ///   - mark: A mark from ``mark()``, after which the sleep must have started, or `nil` for
  ///     any sleep. Defaults to `nil`.
  public func waitForSleeper(until offset: Duration, after mark: Mark? = nil) async {

    await waitForSleepers(1, until: offset, startedFrom: mark?.started ?? 0)

  }

  /// Waits until at least `count` tasks are sleeping until `offset` past the clock's start, or
  /// until the waiting task is canceled, for example by a test's time limit.
  ///
  /// - Parameters:
  ///   - count: How many sleepers to wait for.
  ///   - offset: The deadline, as a duration past the clock's start.
  public func waitForSleepers(_ count: Int, until offset: Duration) async {

    await waitForSleepers(count, until: offset, startedFrom: 0)

  }

  private func waitForSleepers(_ count: Int, until offset: Duration, startedFrom: Int) async {

    let deadline = Instant(offset: offset)
    let id = makeID()

    await withTaskCancellationHandler {

      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in

        let ready = lock.withLock {

          let waiter = SleeperWaiter(
            id: id,
            deadline: deadline,
            startedFrom: startedFrom,
            count: count,
            continuation: continuation
          )

          guard canceledIDs.remove(id) == nil, !isSatisfied(waiter) else {

            pendingIDs.remove(id)

            return true

          }

          sleeperWaiters.append(waiter)

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
  private func isSatisfied(_ waiter: SleeperWaiter) -> Bool {

    let matching = sleepers.filter { $0.deadline == waiter.deadline && $0.order >= waiter.startedFrom }

    return matching.count >= waiter.count

  }

  // Call while holding `lock`.
  private func takeSatisfiedWaiters() -> [CheckedContinuation<Void, Never>] {

    let satisfied = sleeperWaiters.filter { isSatisfied($0) }
    let satisfiedIDs = Set(satisfied.map(\.id))
    sleeperWaiters.removeAll { satisfiedIDs.contains($0.id) }
    pendingIDs.subtract(satisfiedIDs)

    return satisfied.map(\.continuation)

  }

}
