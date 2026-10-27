import InsteonProtocol

/// Talks to an INSTEON modem, such as a PowerLinc Modem, over a ``ModemConnection``.
///
/// ``Modem/send(_:)`` sends one command at a time and waits for the modem's echo, retrying
/// when the modem answers with a NAK because it's busy. Modems expect this pacing: a command
/// sent before the previous one is answered may be lost. Everything the modem sends, including
/// messages from devices, is published to every stream returned by ``Modem/replies()``.
///
/// ```swift
/// let modem = Modem(connection: try SerialPort(path: "/dev/ttyUSB0"))
///
/// let replies = await modem.replies()
/// try await modem.send(.getModemInfo)
///
/// for await reply in replies {
///   if case let .modemInfo(info) = reply {
///     print("Modem address:", info.address)
///   }
/// }
/// ```
public actor Modem: SerialCommandSender {

  /// How ``Modem`` waits for and retries commands.
  public struct RetryPolicy: Hashable, Sendable {

    /// How many times to send a command before giving up. At least 1.
    public var attempts: Int

    /// How long to wait before sending a rejected command again.
    public var delay: Duration

    /// How long to wait for the modem to echo a command.
    public var echoTimeout: Duration

    /// Creates a retry policy.
    ///
    /// - Parameters:
    ///   - attempts: How many times to send a command before giving up. Defaults to 3.
    ///   - delay: How long to wait before resending a rejected command. Defaults to half a
    ///     second, which gives a busy modem time to finish.
    ///   - echoTimeout: How long to wait for an echo. Defaults to 2 seconds.
    public init(attempts: Int = 3, delay: Duration = .milliseconds(500), echoTimeout: Duration = .seconds(2)) {

      self.attempts = max(1, attempts)
      self.delay = delay
      self.echoTimeout = echoTimeout

    }

  }

  private struct PendingEcho {

    let id: Int

    let number: SerialCommandNumber

    let parameters: [UInt8]

    let continuation: CheckedContinuation<CommandEcho, any Error>

    let timeout: Task<Void, Never>

  }

  private let connection: any ModemConnection

  private let retryPolicy: RetryPolicy

  private let clock: any Clock<Duration>

  private var parser = ModemReplyParser()

  private var reader: Task<Void, Never>?

  private var isClosed = false

  private var nextID = 0

  private var subscribers: [Int: AsyncStream<ModemReply>.Continuation] = [:]

  private var pendingEcho: PendingEcho?

  private var isSending = false

  private var waitingSenders: [CheckedContinuation<Void, Never>] = []

  /// Creates a modem that talks over a connection.
  ///
  /// - Parameters:
  ///   - connection: The connection to the modem.
  ///   - retryPolicy: How to wait for and retry commands. Defaults to ``Modem/RetryPolicy/init(attempts:delay:echoTimeout:)``.
  ///   - clock: The clock that times retry delays and echo timeouts. Defaults to a
  ///     `ContinuousClock`; tests can pass a clock they control.
  public init(
    connection: any ModemConnection,
    retryPolicy: RetryPolicy = RetryPolicy(),
    clock: any Clock<Duration> = ContinuousClock()
  ) {

    self.connection = connection
    self.retryPolicy = retryPolicy
    self.clock = clock

  }

  /// Sends a command and waits for the modem to accept it.
  ///
  /// Commands are sent one at a time, in the order they're called. Any data the command
  /// requests, such as an ALL-Link record, arrives afterwards through ``Modem/replies()``.
  ///
  /// A canceled send isn't written to the modem once its turn comes, and isn't sent again
  /// after a NAK. A send already written waits for its echo or its timeout.
  ///
  /// - Parameter command: The command to send.
  /// - Throws: ``ModemError/rejected(_:)`` if the modem NAKs every attempt,
  ///   ``ModemError/timedOut(_:)`` if it doesn't echo the command,
  ///   ``ModemError/connectionClosed`` if the connection closes, `CancellationError` if the
  ///   task is canceled, or the connection's error.
  public func send(_ command: SerialCommand) async throws {

    startReading()

    await waitForTurn()
    defer { finishTurn() }

    for attempt in 1...retryPolicy.attempts {

      try Task.checkCancellation()

      if try await transmit(command).isAccepted {

        return

      }

      if attempt < retryPolicy.attempts {

        try await clock.sleep(for: retryPolicy.delay)

      }

    }

    throw ModemError.rejected(command.number)

  }

  /// Returns a stream of everything the modem sends from now on.
  ///
  /// Each call returns a new stream, so several parts of an app can listen at once. A stream
  /// finishes when the connection closes.
  ///
  /// - Returns: The modem's replies, in the order they arrive.
  public func replies() -> AsyncStream<ModemReply> {

    startReading()

    let id = makeID()
    var streamContinuation: AsyncStream<ModemReply>.Continuation!
    let stream = AsyncStream<ModemReply> { streamContinuation = $0 }

    if isClosed {

      streamContinuation.finish()

      return stream

    }

    streamContinuation.onTermination = { [weak self] _ in

      Task { await self?.removeSubscriber(id) }

    }

    subscribers[id] = streamContinuation

    return stream

  }

  // MARK: - Sending

  /// Writes a command and waits for its echo, or a lone NAK, or the timeout.
  private func transmit(_ command: SerialCommand) async throws -> CommandEcho {

    let id = makeID()
    let echoTimeout = retryPolicy.echoTimeout

    return try await withCheckedThrowingContinuation { continuation in

      if isClosed {

        continuation.resume(throwing: ModemError.connectionClosed)

        return

      }

      // Writes the command, then fails it if no echo arrives in time. Completing the command
      // cancels this task, so a timeout never outlives the command it belongs to.
      let timeout = Task { [connection, clock] in

        do {

          try await connection.write(command.bytes)

        } catch {

          self.failEcho(id, with: error)

          return

        }

        do {

          try await clock.sleep(for: echoTimeout)

        } catch {

          return

        }

        self.echoTimedOut(id, number: command.number)

      }

      pendingEcho = PendingEcho(
        id: id,
        number: command.number,
        parameters: command.parameters,
        continuation: continuation,
        timeout: timeout
      )

    }

  }

  /// Fails the command waiting for an echo, unless the parser is holding back a NAK for it,
  /// which only more bytes or the end of the wait can tell apart from data.
  private func echoTimedOut(_ id: Int, number: SerialCommandNumber) {

    guard pendingEcho?.id == id else {

      return

    }

    deliver(parser.finishPendingReply())
    failEcho(id, with: ModemError.timedOut(number))

  }

  private func failEcho(_ id: Int, with error: any Error) {

    guard pendingEcho?.id == id else {

      return

    }

    completePendingEcho(.failure(error))

  }

  /// Completes the command waiting for an echo, if there is one, and stops its timeout.
  private func completePendingEcho(_ result: Result<CommandEcho, any Error>) {

    guard let pending = pendingEcho else {

      return

    }

    pendingEcho = nil
    pending.timeout.cancel()
    pending.continuation.resume(with: result)

  }

  private func waitForTurn() async {

    guard isSending else {

      isSending = true

      return

    }

    await withCheckedContinuation { waitingSenders.append($0) }

  }

  private func finishTurn() {

    if waitingSenders.isEmpty {

      isSending = false

    } else {

      waitingSenders.removeFirst().resume()

    }

  }

  // MARK: - Receiving

  private func startReading() {

    guard reader == nil, !isClosed else {

      return

    }

    let stream = connection.receive()

    reader = Task { [weak self] in

      do {

        for try await chunk in stream {

          await self?.handle(chunk)

        }

        await self?.close(with: nil)

      } catch {

        await self?.close(with: error)

      }

    }

  }

  private func handle(_ chunk: [UInt8]) {

    deliver(parser.parse(chunk))

  }

  private func deliver(_ replies: [ModemReply]) {

    for reply in replies {

      resolvePendingEcho(with: reply)

      for subscriber in subscribers.values {

        subscriber.yield(reply)

      }

    }

  }

  private func resolvePendingEcho(with reply: ModemReply) {

    guard let pending = pendingEcho else {

      return

    }

    switch reply {
    // Matching the parameters keeps a late echo of an earlier command from answering this one.
    case let .echo(echo) where echo.number == pending.number && echo.parameters == pending.parameters:
      completePendingEcho(.success(echo))
    // These commands are answered with their data in place of a plain echo.
    case .modemInfo where pending.number == .getModemInfo,
         .modemConfiguration where pending.number == .getModemConfiguration:
      completePendingEcho(.success(CommandEcho(number: pending.number, parameters: [], isAccepted: true)))
    case .negativeAcknowledgement:
      completePendingEcho(.success(CommandEcho(number: pending.number, parameters: [], isAccepted: false)))
    default:
      break
    }

  }

  private func close(with error: (any Error)?) {

    isClosed = true
    completePendingEcho(.failure(error ?? ModemError.connectionClosed))

    for subscriber in subscribers.values {

      subscriber.finish()

    }

    subscribers.removeAll()

  }

  private func removeSubscriber(_ id: Int) {

    subscribers[id] = nil

  }

  private func makeID() -> Int {

    defer { nextID += 1 }

    return nextID

  }

}
