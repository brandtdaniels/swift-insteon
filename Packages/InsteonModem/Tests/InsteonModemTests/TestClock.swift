import Foundation

/// A clock that only moves when a test advances it, so timing in tests is deterministic.
///
/// Sleeping until a deadline that has already passed returns at once; any other sleep waits
/// for ``advance(by:)`` to reach its deadline, or for its task to be cancelled.
final class TestClock: Clock, @unchecked Sendable {

  struct Instant: InstantProtocol {

    var offset: Duration

    func advanced(by duration: Duration) -> Instant {

      Instant(offset: offset + duration)

    }

    func duration(to other: Instant) -> Duration {

      other.offset - offset

    }

    static func < (lhs: Instant, rhs: Instant) -> Bool {

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

  private var cancelledIDs: Set<Int> = []

  private var sleeperWaiters: [(deadline: Instant, continuation: CheckedContinuation<Void, Never>)] = []

  var now: Instant { lock.withLock { current } }

  var minimumResolution: Duration { .zero }

  func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {

    let id = lock.withLock {

      defer { nextID += 1 }

      return nextID

    }

    try await withTaskCancellationHandler {

      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in

        let woken: [CheckedContinuation<Void, Never>] = lock.withLock {

          if cancelledIDs.remove(id) != nil {

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

      let cancelled: Sleeper? = lock.withLock {

        guard let index = sleepers.firstIndex(where: { $0.id == id }) else {

          cancelledIDs.insert(id)

          return nil

        }

        return sleepers.remove(at: index)

      }

      cancelled?.continuation.resume(throwing: CancellationError())

    }

  }

  /// Moves the clock forward, waking every sleeper whose deadline it reaches.
  func advance(by duration: Duration) {

    let due: [Sleeper] = lock.withLock {

      current = current.advanced(by: duration)

      let due = sleepers.filter { $0.deadline <= current }
      sleepers.removeAll { $0.deadline <= current }

      return due

    }

    due.forEach { $0.continuation.resume() }

  }

  /// Waits until a task is sleeping until `offset` past the clock's start.
  func waitForSleeper(until offset: Duration) async {

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
