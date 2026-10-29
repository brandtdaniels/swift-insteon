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
  /// What was typed before the wait, such as a Return pressed while the command connected to
  /// the modem or read its ALL-Link database, is discarded first, so only a Return pressed
  /// after the instructions ends the wait.
  ///
  /// The line is read on a thread of its own, so the wait doesn't hold up the tasks that keep
  /// the modem running.
  ///
  /// - Throws: `CancellationError` if the task was canceled while waiting.
  static func waitForReturn() async throws {

    discardTypedAhead()

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

  /// Discards what the terminal has received but the command hasn't read yet.
  private static func discardTypedAhead() {

    if readsFromTerminal {

      _ = tcflush(STDIN_FILENO, TCIFLUSH)

    }

  }

  /// Asks the person a yes-or-no question on standard error, and waits for the answer.
  ///
  /// Only `y` or `yes`, in either case, is yes; anything else, an empty line or the end of
  /// input is no.
  ///
  /// - Parameter question: The question, ending with its choices, such as `[y/N]`.
  /// - Returns: Whether the person answered yes.
  /// - Throws: `CancellationError` if the task was canceled while waiting.
  static func confirm(_ question: String) async throws -> Bool {

    Output.prompt(question)

    let answer = OneShot<String?>()

    let line: String? = try await withTaskCancellationHandler {

      DispatchQueue.global().async {

        answer.finish(.success(readLine()))

      }

      return try await answer.value()

    } onCancel: {

      answer.finish(.failure(CancellationError()))

    }

    let text: String = (line ?? "").trimmingCharacters(in: .whitespaces).lowercased()

    return text == "y" || text == "yes"

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
