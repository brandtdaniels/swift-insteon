import Foundation

/// A result that's set once, by whichever of several tasks finishes first, and waited for.
///
/// Unlike a task group, which waits for each of its tasks, waiting here ends as soon as the
/// result is set, so a task that ignores cancellation can't hold up its caller.
final class OneShot<Value: Sendable>: @unchecked Sendable {

  private let lock = NSLock()

  private var continuation: CheckedContinuation<Value, any Error>?

  private var result: Result<Value, any Error>?

  /// Waits for the result, and returns its value or throws its error.
  ///
  /// Call it once.
  func value() async throws -> Value {

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, any Error>) in

      lock.lock()

      guard let result else {

        self.continuation = continuation
        lock.unlock()

        return

      }

      lock.unlock()
      continuation.resume(with: result)

    }

  }

  /// Sets the result, if it isn't set, and ends the wait for it.
  func finish(_ result: Result<Value, any Error>) {

    lock.lock()

    guard self.result == nil else {

      lock.unlock()

      return

    }

    self.result = result

    let continuation = self.continuation
    self.continuation = nil

    lock.unlock()

    continuation?.resume(with: result)

  }

}
