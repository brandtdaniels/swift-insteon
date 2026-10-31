import Foundation

/// Reads lines from an input on a thread of its own, one read at a time, for whichever caller
/// is waiting when a line arrives.
///
/// A blocking read, such as `readLine()` on standard input, can't be stopped. So a caller
/// that's canceled stops waiting, but the read goes on, and the line it returns goes to the
/// next caller, rather than a second read starting and the first one taking that caller's
/// line. A line that arrives while no caller waits is discarded.
///
/// ```swift
/// let lines = LineReader { readLine() }
/// let answer = try await lines.line()
/// ```
public final class LineReader: @unchecked Sendable {

  private let read: @Sendable () -> String?

  // `lock` guards everything below it.
  private let lock = NSLock()

  /// Whether a read is in progress.
  private var isReading = false

  /// The caller waiting for a line, if any.
  private var waiter: (id: Int, continuation: CheckedContinuation<String?, any Error>)?

  /// Callers canceled before they started waiting.
  private var canceled: Set<Int> = []

  private var nextID = 0

  /// Creates a reader.
  ///
  /// - Parameter read: Reads a line, blocking until one arrives, or returns `nil` at the end
  ///   of the input.
  public init(reading read: @escaping @Sendable () -> String?) {

    self.read = read

  }

  /// Whether a caller is waiting for a line.
  public var hasWaiter: Bool {

    lock.withLock { waiter != nil }

  }

  /// Waits for the next line.
  ///
  /// - Returns: The line, without its newline, or `nil` at the end of the input.
  /// - Throws: `CancellationError` if the task is canceled first, or if another caller starts
  ///   waiting.
  public func line() async throws -> String? {

    let id: Int = lock.withLock { () -> Int in

      defer { nextID += 1 }

      return nextID

    }

    defer { lock.withLock { _ = canceled.remove(id) } }

    return try await withTaskCancellationHandler {

      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String?, any Error>) in

        let (isCanceled, replaced, startsReading): (Bool, CheckedContinuation<String?, any Error>?, Bool) = lock.withLock {

          if canceled.contains(id) {

            return (true, nil, false)

          }

          let replaced: CheckedContinuation<String?, any Error>? = waiter?.continuation
          let startsReading: Bool = !isReading

          waiter = (id, continuation)
          isReading = true

          return (false, replaced, startsReading)

        }

        if isCanceled {

          continuation.resume(throwing: CancellationError())

          return

        }

        replaced?.resume(throwing: CancellationError())

        if startsReading {

          DispatchQueue.global().async {

            self.readLine()

          }

        }

      }

    } onCancel: {

      let continuation: CheckedContinuation<String?, any Error>? = lock.withLock {

        guard let waiter, waiter.id == id else {

          canceled.insert(id)

          return nil

        }

        self.waiter = nil

        return waiter.continuation

      }

      continuation?.resume(throwing: CancellationError())

    }

  }

  /// Reads a line and hands it to the caller waiting, if any.
  private func readLine() {

    let line: String? = read()

    let continuation: CheckedContinuation<String?, any Error>? = lock.withLock {

      isReading = false
      defer { waiter = nil }

      return waiter?.continuation

    }

    continuation?.resume(returning: line)

  }

}
