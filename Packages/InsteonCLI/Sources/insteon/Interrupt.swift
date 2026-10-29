import Dispatch
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Turns Control-C into task cancellation, so a command can stop cleanly, such as by taking
/// the modem out of linking mode, rather than leaving the modem as it was.
enum Interrupt {

  /// Runs an operation in a task that Control-C cancels.
  ///
  /// While the operation runs, the first Control-C cancels it, and a second one ends the
  /// command at once, in case stopping cleanly takes too long.
  ///
  /// - Parameter operation: The work to run.
  /// - Throws: The operation's error, such as `CancellationError` after Control-C.
  static func cancellingOnInterrupt(_ operation: @escaping @Sendable () async throws -> Void) async throws {

    let task = Task { try await operation() }

    #if canImport(Darwin)
    // Dispatch on Darwin reports only signals that nothing else handles, so the default action,
    // which ends the process, is turned off while the source listens. Dispatch on Linux handles
    // the signal itself.
    signal(SIGINT, SIG_IGN)
    #endif

    let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: DispatchQueue(label: "insteon.interrupt"))
    let count = InterruptCount()

    source.setEventHandler {

      count.value += 1

      guard count.value == 1 else {

        // Dispatch on Linux keeps its own handler for the signal, so restoring the default
        // action alone may not end the process. End it here, with the status of SIGINT.
        _exit(130)

      }

      task.cancel()

      #if canImport(Darwin)
      // The next Control-C ends the process before it reaches the source.
      signal(SIGINT, SIG_DFL)
      #endif

    }

    source.resume()

    defer {

      source.cancel()
      signal(SIGINT, SIG_DFL)

    }

    try await withTaskCancellationHandler {

      try await task.value

    } onCancel: {

      task.cancel()

    }

  }

}

/// How many times Control-C was pressed while a command ran.
///
/// It's read and changed only by the signal source's handler, on the source's serial queue,
/// so it needs no lock.
private final class InterruptCount: @unchecked Sendable {

  var value = 0

}
