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

  try await withThrowingTaskGroup(of: Value?.self) { group in

    group.addTask {

      try await operation()

    }

    group.addTask {

      try await clock.sleep(for: timeout)

      return nil

    }

    // Whichever finishes first decides; the other is canceled, and the group waits for it.
    defer {

      group.cancelAll()

    }

    guard let first: Value? = try await group.next() else {

      throw CancellationError()

    }

    guard let value: Value = first else {

      throw URLError(.timedOut)

    }

    return value

  }

}
