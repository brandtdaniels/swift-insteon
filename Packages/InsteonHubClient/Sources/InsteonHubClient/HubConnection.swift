import Foundation
import InsteonModem

/// A `ModemConnection` to the modem inside an INSTEON Hub, model 2245 or 2242.
///
/// Writes go to the Hub as HTTP requests, and the Hub's reply buffer is polled for the bytes
/// the modem sends back. Drive it with a `Modem` to get the same pacing, retries and stream of
/// replies as a modem on a USB or serial port:
///
/// ```swift
/// let hub = Hub(endpoint: HubEndpoint(host: "192.168.1.20"), user: username, password: password)
/// let modem = Modem(connection: HubConnection(hub: hub))
///
/// try await withThrowingTaskGroup(of: Void.self) { group in
///   group.addTask { try await modem.run() }
///   try await modem.send(.getModemInfo)
///   group.cancelAll()
/// }
/// ```
///
/// Polling happens only while the stream from ``HubConnection/receive()`` is being read, in the
/// reading task, so it stops when that task is canceled.
///
/// Requests to the Hub go one at a time, and the first one clears the Hub's buffer so replies
/// from before the connection was made are ignored. The Hub starts its buffer over for each
/// command, so each write first reads the bytes that arrived since the last poll, which the
/// stream then delivers ahead of the command's reply.
///
/// A poll that fails, for example because a request timed out, is tried again at the next
/// interval. The stream fails after ``HubConnection/defaultFailureLimit`` failed polls in a
/// row by default, or at once if the Hub answers with an error status.
public actor HubConnection: ModemConnection {

  /// How often the Hub's buffer is read by default: every half second.
  public static let defaultPollInterval: Duration = .milliseconds(500)

  /// How many polls in a row can fail by default before the stream fails: 3.
  public static let defaultFailureLimit = 3

  private let hub: Hub

  private let pollInterval: Duration

  private let clock: any Clock<Duration>

  private let failureLimit: Int

  private var cursor = HubBufferCursor()

  private var hasClearedBuffer = false

  /// Bytes read before a write that the stream hasn't delivered yet.
  private var unreadBytes: [UInt8] = []

  /// How many polls in a row have failed for the stream being read.
  private var failedPolls = 0

  private var requests = TurnQueue()

  /// The stream that has read the buffer at least once, so its next read waits for the interval.
  private var polledStream: Int?

  private nonisolated let streams = StreamCounter()

  /// Creates a connection to a Hub's modem.
  ///
  /// - Parameters:
  ///   - hub: The Hub to talk to.
  ///   - pollInterval: How long to wait between reads of the Hub's buffer. Defaults to
  ///     ``HubConnection/defaultPollInterval``.
  ///   - failureLimit: How many polls in a row can fail before the stream fails. At least 1.
  ///     Defaults to ``HubConnection/defaultFailureLimit``.
  ///   - clock: The clock that times polling. Defaults to a `ContinuousClock`; tests can pass a
  ///     clock they control.
  public init(
    hub: Hub,
    pollInterval: Duration = HubConnection.defaultPollInterval,
    failureLimit: Int = HubConnection.defaultFailureLimit,
    clock: any Clock<Duration> = ContinuousClock()
  ) {

    self.hub = hub
    self.pollInterval = pollInterval
    self.failureLimit = max(1, failureLimit)
    self.clock = clock

  }

  /// Sends bytes to the Hub's modem.
  ///
  /// - Parameter bytes: The bytes to send.
  /// - Throws: ``HubError`` if the Hub rejected the request, or the HTTP client's error.
  public func write(_ bytes: [UInt8]) async throws {

    try await beginRequest()
    defer { requests.release() }

    try await clearBufferIfNeeded()

    // The Hub starts its buffer over for each command, so keep what arrived since the last poll.
    // If the buffer can't be read, the command still goes out.
    if let buffer = try? await hub.readBuffer() {

      unreadBytes += Self.collapsingNAKRun(cursor.advance(to: buffer))

    }

    // Read the next reply from the start even if the request fails, since the Hub may have
    // received the command anyway: a reply read twice parses, but one read from its middle
    // doesn't.
    cursor.reset()

    try await hub.write(bytes)

  }

  /// Returns the bytes the Hub's modem sends, polling the Hub's buffer as the stream is read.
  ///
  /// The buffer is read once right away, then once per poll interval, in the task reading the
  /// stream. Calling this again finishes the previous stream. The stream finishes when the
  /// reading task is canceled, or with an error if the Hub answers with an error status or too
  /// many polls in a row fail.
  ///
  /// - Returns: A stream of received byte chunks.
  public nonisolated func receive() -> AsyncThrowingStream<[UInt8], any Error> {

    let id = streams.next()

    return AsyncThrowingStream(unfolding: { try await self.nextChunk(forStream: id) })

  }

  // MARK: - Polling

  /// Polls until the buffer has new bytes, or returns `nil` once a newer stream replaces this
  /// one or the reading task is canceled.
  private func nextChunk(forStream id: Int) async throws -> [UInt8]? {

    do {

      while streams.isLatest(id) {

        if polledStream == id {

          try await clock.sleep(for: pollInterval)

        } else {

          polledStream = id
          failedPolls = 0

        }

        guard streams.isLatest(id) else {

          break

        }

        do {

          let received = try await readNewBytes()
          failedPolls = 0

          if !received.isEmpty {

            return received

          }

        } catch {

          failedPolls += 1

          guard Self.isTransient(error), failedPolls < failureLimit else {

            throw error

          }

        }

      }

      return nil

    } catch {

      // Canceling the reading task ends the stream rather than failing it, whether the
      // cancellation interrupted the wait between polls or a request to the Hub.
      if error is CancellationError || Task.isCancelled {

        return nil

      }

      throw error

    }

  }

  private func readNewBytes() async throws -> [UInt8] {

    try await beginRequest()
    defer { requests.release() }

    try await clearBufferIfNeeded()

    let received = unreadBytes + Self.collapsingNAKRun(cursor.advance(to: try await hub.readBuffer()))
    unreadBytes = []

    return received

  }

  /// Whether a failed poll is worth trying again: anything but an answer from the Hub that it
  /// won't serve the request, or cancellation.
  private static func isTransient(_ error: any Error) -> Bool {

    switch error {
    case HubError.unexpectedStatus, HubError.invalidEndpoint, is CancellationError:
      false
    default:
      true
    }

  }

  private func clearBufferIfNeeded() async throws {

    guard !hasClearedBuffer else {

      return

    }

    try await hub.clearBuffer()
    cursor.reset()
    hasClearedBuffer = true

  }

  /// Some Hubs fill the buffer with NAKs in place of a rejected command's echo. Passes such a
  /// run on as a single lone NAK, which `Modem` reads as the rejection and retries.
  private static func collapsingNAKRun(_ bytes: [UInt8]) -> [UInt8] {

    let negativeAcknowledgement: UInt8 = 0x15

    guard bytes.count > 1, bytes.allSatisfy({ $0 == negativeAcknowledgement }) else {

      return bytes

    }

    return [negativeAcknowledgement]

  }

  // MARK: - One request at a time

  private func beginRequest() async throws {

    if let ticket = requests.request() {

      for await _ in ticket.handoff {}

      guard requests.settle(ticket) else {

        throw CancellationError()

      }

    }

    if Task.isCancelled {

      requests.release()

      throw CancellationError()

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
