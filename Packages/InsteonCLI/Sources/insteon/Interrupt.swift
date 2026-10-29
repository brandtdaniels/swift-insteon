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

    source.setEventHandler {

      task.cancel()
      signal(SIGINT, SIG_DFL)

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
