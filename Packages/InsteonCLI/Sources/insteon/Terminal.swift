import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Reads from the person at the terminal.
enum Terminal {

  /// Whether standard input is a terminal, so the command can wait for Return.
  static var readsFromTerminal: Bool {

    isatty(STDIN_FILENO) == 1

  }

  /// Waits for the person to press Return, or for the task to be canceled, such as by
  /// Control-C.
  ///
  /// The line is read on a thread of its own, so the wait doesn't hold up the tasks that keep
  /// the modem running.
  ///
  /// - Throws: `CancellationError` if the task was canceled while waiting.
  static func waitForReturn() async throws {

    let resumption = Resumption()

    await withTaskCancellationHandler {

      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in

        resumption.set(continuation)

        DispatchQueue.global().async {

          _ = readLine()
          resumption.resume()

        }

      }

    } onCancel: {

      resumption.resume()

    }

    try Task.checkCancellation()

  }

}

/// Resumes a continuation once, from whichever of Return and cancellation comes first.
private final class Resumption: @unchecked Sendable {

  private let lock = NSLock()

  private var continuation: CheckedContinuation<Void, Never>?

  private var isResumed = false

  /// Keeps the continuation, or resumes it at once if the wait already ended.
  func set(_ continuation: CheckedContinuation<Void, Never>) {

    lock.lock()

    guard !isResumed else {

      lock.unlock()
      continuation.resume()

      return

    }

    self.continuation = continuation
    lock.unlock()

  }

  /// Ends the wait, if it hasn't ended.
  func resume() {

    lock.lock()

    let continuation = self.continuation
    self.continuation = nil
    isResumed = true

    lock.unlock()

    continuation?.resume()

  }

}
