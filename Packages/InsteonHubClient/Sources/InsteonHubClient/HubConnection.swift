import Foundation
import InsteonModem

/// A `ModemConnection` to the modem inside an INSTEON Hub.
///
/// Writes go to the Hub as HTTP requests, and the Hub's reply buffer is polled for the bytes
/// the modem sends back. Drive it with a `Modem` to get the same pacing, retries and stream of
/// replies as a modem on a USB or serial port:
///
/// ```swift
/// let hub = Hub(endpoint: HubEndpoint(host: "192.168.1.20"), user: username, password: password)
/// let modem = Modem(connection: HubConnection(hub: hub))
///
/// try await modem.send(.getModemInfo)
/// ```
///
/// Requests to the Hub go one at a time, and the first one clears the Hub's buffer so replies
/// from before the connection was made are ignored.
public actor HubConnection: ModemConnection {

  /// How often the Hub's buffer is read by default: every half second.
  public static let defaultPollInterval: Duration = .milliseconds(500)

  private let hub: Hub

  private let pollInterval: Duration

  private let clock: any Clock<Duration>

  private var cursor = HubBufferCursor()

  private var hasClearedBuffer = false

  private var lastWritten: [UInt8]?

  private var isBusy = false

  private var waitingRequests: [CheckedContinuation<Void, Never>] = []

  private var activeStream: AsyncThrowingStream<[UInt8], any Error>.Continuation?

  private nonisolated let streams = StreamCounter()

  /// Creates a connection to a Hub's modem.
  ///
  /// - Parameters:
  ///   - hub: The Hub to talk to.
  ///   - pollInterval: How long to wait between reads of the Hub's buffer. Defaults to
  ///     ``HubConnection/defaultPollInterval``.
  ///   - clock: The clock that times polling. Defaults to a `ContinuousClock`; tests can pass a
  ///     clock they control.
  public init(
    hub: Hub,
    pollInterval: Duration = HubConnection.defaultPollInterval,
    clock: any Clock<Duration> = ContinuousClock()
  ) {

    self.hub = hub
    self.pollInterval = pollInterval
    self.clock = clock

  }

  /// Sends bytes to the Hub's modem.
  ///
  /// - Parameter bytes: The bytes to send.
  /// - Throws: ``HubError`` if the Hub rejected the request, or the HTTP client's error.
  public func write(_ bytes: [UInt8]) async throws {

    await beginRequest()
    defer { endRequest() }

    try await clearBufferIfNeeded()
    try await hub.write(bytes)

    // The Hub starts its buffer over for each command, so read the next reply from the start.
    cursor.reset()
    lastWritten = bytes

  }

  /// Returns the bytes the Hub's modem sends, polling the Hub's buffer until the stream ends.
  ///
  /// Calling this again finishes the previous stream. The stream finishes with an error if
  /// reading the buffer fails.
  ///
  /// - Returns: A stream of received byte chunks.
  public nonisolated func receive() -> AsyncThrowingStream<[UInt8], any Error> {

    let (stream, continuation) = AsyncThrowingStream<[UInt8], any Error>.makeStream()
    let id = streams.next()
    let task = Task { await self.poll(into: continuation, id: id) }

    continuation.onTermination = { _ in task.cancel() }

    return stream

  }

  // MARK: - Polling

  private func poll(into continuation: AsyncThrowingStream<[UInt8], any Error>.Continuation, id: Int) async {

    // A newer call to `receive()` wins, whichever task starts first.
    guard streams.isLatest(id) else {

      continuation.finish()

      return

    }

    activeStream?.finish()
    activeStream = continuation

    do {

      while streams.isLatest(id) {

        let received = try await readNewBytes()

        if !received.isEmpty {

          continuation.yield(received)

        }

        try await clock.sleep(for: pollInterval)

      }

      continuation.finish()

    } catch is CancellationError {

      continuation.finish()

    } catch {

      continuation.finish(throwing: error)

    }

  }

  private func readNewBytes() async throws -> [UInt8] {

    await beginRequest()
    defer { endRequest() }

    try await clearBufferIfNeeded()

    return repairingNAKRun(cursor.advance(to: try await hub.readBuffer()))

  }

  private func clearBufferIfNeeded() async throws {

    guard !hasClearedBuffer else {

      return

    }

    try await hub.clearBuffer()
    cursor.reset()
    hasClearedBuffer = true

  }

  /// Some Hubs fill the buffer with NAKs in place of a rejected command's echo. Rewrites such a
  /// run as the echo of the last command with a NAK, so `Modem` sees a rejection and retries.
  private func repairingNAKRun(_ bytes: [UInt8]) -> [UInt8] {

    let negativeAcknowledgement: UInt8 = 0x15

    guard
      bytes.count > 1,
      bytes.allSatisfy({ $0 == negativeAcknowledgement }),
      let lastWritten
    else {

      return bytes

    }

    return lastWritten + [negativeAcknowledgement]

  }

  // MARK: - One request at a time

  private func beginRequest() async {

    guard isBusy else {

      isBusy = true

      return

    }

    await withCheckedContinuation { waitingRequests.append($0) }

  }

  private func endRequest() {

    if waitingRequests.isEmpty {

      isBusy = false

    } else {

      waitingRequests.removeFirst().resume()

    }

  }

}

/// Numbers the streams returned by ``HubConnection/receive()`` so the newest one can be told
/// apart synchronously.
private final class StreamCounter: @unchecked Sendable {

  // `lock` guards `latest`.
  private let lock = NSLock()

  private var latest = 0

  func next() -> Int {

    lock.withLock {

      latest += 1

      return latest

    }

  }

  func isLatest(_ id: Int) -> Bool {

    lock.withLock { latest == id }

  }

}
