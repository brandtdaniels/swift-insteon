import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Runs an operation, such as a request, and gives up on it once a time has passed in all.
///
/// A `URLRequest`'s `timeoutInterval` limits only the wait between bytes, so an answer that
/// trickles in a byte at a time never times out. This limits the whole operation. When the
/// time is up, the operation is canceled and `URLError(.timedOut)` is thrown, the error a
/// request that timed out throws, so callers treat it the same way. The operation must stop
/// when it's canceled, as a request sent with `URLSession` does; this waits for it to stop.
///
/// - Parameters:
///   - timeout: How long the operation may take.
///   - clock: The clock that times it. Defaults to a `ContinuousClock`.
///   - operation: The operation.
/// - Returns: The operation's result.
/// - Throws: `URLError(.timedOut)` if the time is up first, the operation's error, or
///   `CancellationError` if the calling task is canceled.
package func withDeadline<Value: Sendable>(
  _ timeout: Duration,
  clock: any Clock<Duration> = ContinuousClock(),
  _ operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {

  try await withThrowingTaskGroup(of: DeadlineOutcome<Value>.self) { group in

    group.addTask {

      let value: Value = try await operation()

      return DeadlineOutcome<Value>.finished(value)

    }

    group.addTask {

      try await clock.sleep(for: timeout)

      return DeadlineOutcome<Value>.timedOut

    }

    // Whichever finishes first decides; the other is canceled, and the group waits for it.
    defer {

      group.cancelAll()

    }

    guard let first: DeadlineOutcome<Value> = try await group.next() else {

      throw CancellationError()

    }

    switch first {
    case let .finished(value):
      return value
    case .timedOut:
      throw URLError(.timedOut)
    }

  }

}

/// Which of an operation and its deadline finished first.
private enum DeadlineOutcome<Value: Sendable>: Sendable {

  /// The operation finished with a value.
  case finished(Value)

  /// The time ran out first.
  case timedOut

}
