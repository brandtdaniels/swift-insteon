import Dispatch
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Waits for the process to be asked to stop, so a plugin can clean up before it exits.
public enum TerminationSignal {
  /// Returns when the process receives SIGINT or SIGTERM, or when the calling task is canceled.
  public static func received() async {
    let (signals, continuation) = AsyncStream<Void>.makeStream()
    let sources = [SIGINT, SIGTERM].map { number -> any DispatchSourceSignal in
      signal(number, SIG_IGN)
      let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
      source.setEventHandler { continuation.yield() }
      source.resume()
      return source
    }
    defer { for source in sources { source.cancel() } }
    for await _ in signals { return }
  }
}
