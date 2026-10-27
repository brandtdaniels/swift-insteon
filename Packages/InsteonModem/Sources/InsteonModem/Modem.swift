import InsteonProtocol

/// Talks to an INSTEON modem, such as a PowerLinc Modem, over a ``ModemConnection``.
///
/// ``Modem/send(_:)`` sends one command at a time and waits for the modem's echo, retrying
/// when the modem answers with a NAK because it's busy. Modems expect this pacing: a command
/// sent before the previous one is answered may be lost. Everything the modem sends, including
/// messages from devices, is published to every stream returned by ``Modem/replies()``.
///
/// ``Modem/run()`` reads what the modem sends, so run it alongside the code that sends
/// commands, for example in a task group. Canceling it closes the modem.
///
/// ```swift
/// let modem = Modem(connection: try SerialPort(path: "/dev/ttyUSB0"))
///
/// try await withThrowingTaskGroup(of: Void.self) { group in
///   group.addTask { try await modem.run() }
///
///   let replies = await modem.replies()
///   try await modem.send(.getModemInfo)
///
///   for await reply in replies {
///     if case let .modemInfo(info) = reply {
///       print("Modem address:", info.address)
///       break
///     }
///   }
///
///   group.cancelAll()
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

    let result: AsyncStream<Result<CommandEcho, any Error>>.Continuation

  }

  /// A command whose send was canceled before the modem answered it.
  private struct UnansweredEcho {

    let id: Int

    let number: SerialCommandNumber

    let results: AsyncStream<Result<CommandEcho, any Error>>

  }

  private let connection: any ModemConnection

  private let retryPolicy: RetryPolicy

  private let clock: any Clock<Duration>

  private var parser = ModemReplyParser()

  private var isRunning = false

  private var isClosed = false

  private var nextID = 0

  private var subscribers: [AsyncStream<ModemReply>.Continuation] = []

  private var pendingEcho: PendingEcho?

  private var unansweredEcho: UnansweredEcho?

  private var turns = TurnQueue()

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

  /// Reads everything the modem sends, until the connection closes or the task is canceled.
  ///
  /// Echoes and replies arrive only while this runs, so run it alongside the code that sends
  /// commands. When it returns, the modem is closed: waiting sends fail with
  /// ``ModemError/connectionClosed``, and every stream from ``Modem/replies()`` finishes.
  /// Calling it while it's running returns at once.
  ///
  /// - Throws: The connection's error, if reading from it failed, or
  ///   ``ModemError/connectionClosed`` if the modem has already closed.
  public func run() async throws {

    guard !isClosed else {

      throw ModemError.connectionClosed

    }

    guard !isRunning else {

      return

    }

    isRunning = true

    do {

      for try await chunk in connection.receive() {

        deliver(parser.parse(chunk))

      }

      close(with: nil)

    } catch {

      close(with: error)

      throw error

    }

  }

  /// Sends a command and waits for the modem to accept it.
  ///
  /// Commands are sent one at a time, in the order they're called. Any data the command
  /// requests, such as an ALL-Link record, arrives afterwards through ``Modem/replies()``. The
  /// echo is read by ``Modem/run()``, so a send made while it isn't running times out.
  ///
  /// Canceling a send stops it: a send waiting for its turn leaves the queue, a send waiting
  /// for its echo stops waiting, and a rejected command isn't sent again. A command that was
  /// written still holds the modem, so the next send waits for the modem to answer it, or for
  /// the echo timeout, before writing.
  ///
  /// - Parameter command: The command to send.
  /// - Throws: ``ModemError/rejected(_:)`` if the modem NAKs every attempt,
  ///   ``ModemError/timedOut(_:)`` if it doesn't echo the command,
  ///   ``ModemError/connectionClosed`` if the modem is closed, `CancellationError` if the
  ///   task is canceled, or the connection's error.
  public func send(_ command: SerialCommand) async throws {

    try await waitForTurn()
    defer { turns.release() }

    try await waitForUnansweredEcho()

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
  /// finishes when the modem closes.
  ///
  /// - Returns: The modem's replies, in the order they arrive.
  public func replies() -> AsyncStream<ModemReply> {

    let (stream, continuation) = AsyncStream<ModemReply>.makeStream()

    if isClosed {

      continuation.finish()

    } else {

      subscribers.append(continuation)

    }

    return stream

  }

  // MARK: - Sending

  /// Writes a command and waits for its echo, a lone NAK, the timeout or cancellation.
  private func transmit(_ command: SerialCommand) async throws -> CommandEcho {

    guard !isClosed else {

      throw ModemError.connectionClosed

    }

    let id = makeID()
    let (results, continuation) = AsyncStream<Result<CommandEcho, any Error>>.makeStream()

    pendingEcho = PendingEcho(id: id, number: command.number, parameters: command.parameters, result: continuation)
    defer { abandonEcho(id) }

    return try await awaitEcho(id, number: command.number, results: results) { [connection] in

      try await connection.write(command.bytes)

    }.get()

  }

  /// Waits for the modem to answer a command whose send was canceled, so the next command
  /// isn't written while the modem is still busy with it.
  private func waitForUnansweredEcho() async throws {

    guard let unanswered = unansweredEcho else {

      return

    }

    unansweredEcho = nil
    defer { abandonEcho(unanswered.id) }

    _ = await awaitEcho(unanswered.id, number: unanswered.number, results: unanswered.results) {}

    try Task.checkCancellation()

  }

  /// Runs `write`, then waits for the pending echo's result, the timeout or cancellation.
  private func awaitEcho(
    _ id: Int,
    number: SerialCommandNumber,
    results: AsyncStream<Result<CommandEcho, any Error>>,
    write: @escaping @Sendable () async throws -> Void
  ) async -> Result<CommandEcho, any Error> {

    let echoTimeout = retryPolicy.echoTimeout

    return await withTaskGroup(of: Void.self, returning: Result<CommandEcho, any Error>.self) { group in

      // Writes, then gives up on the echo once the timeout passes. The group cancels this
      // child as soon as the echo arrives, so a timeout never outlives its command.
      group.addTask { [clock] in

        do {

          try await write()

        } catch {

          await self.failEcho(id, with: error)

          return

        }

        do {

          try await clock.sleep(for: echoTimeout)

        } catch {

          return

        }

        await self.echoTimedOut(id, number: number)

      }

      defer { group.cancelAll() }

      for await result in results {

        return result

      }

      // The stream ends without a result only when this task is canceled.
      return .failure(CancellationError())

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

  /// Stops waiting for an echo whose send was canceled. The command may have been written, so
  /// its echo stays pending, and the next send waits for it.
  private func abandonEcho(_ id: Int) {

    guard let pending = pendingEcho, pending.id == id else {

      return

    }

    pending.result.finish()

    let (results, continuation) = AsyncStream<Result<CommandEcho, any Error>>.makeStream()

    pendingEcho = PendingEcho(id: id, number: pending.number, parameters: pending.parameters, result: continuation)
    unansweredEcho = UnansweredEcho(id: id, number: pending.number, results: results)

  }

  /// Completes the command waiting for an echo, if there is one.
  private func completePendingEcho(_ result: Result<CommandEcho, any Error>) {

    guard let pending = pendingEcho else {

      return

    }

    pendingEcho = nil
    pending.result.yield(result)
    pending.result.finish()

  }

  /// Waits for the turn to send, in the order sends were called.
  private func waitForTurn() async throws {

    if let ticket = turns.request() {

      for await _ in ticket.handoff {}

      guard turns.settle(ticket) else {

        throw CancellationError()

      }

    }

    if Task.isCancelled {

      turns.release()

      throw CancellationError()

    }

  }

  // MARK: - Receiving

  private func deliver(_ replies: [ModemReply]) {

    for reply in replies {

      resolvePendingEcho(with: reply)

      // A stream whose listener has stopped listening is dropped.
      subscribers.removeAll { subscriber in

        if case .terminated = subscriber.yield(reply) {

          return true

        }

        return false

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

    for subscriber in subscribers {

      subscriber.finish()

    }

    subscribers.removeAll()

  }

  private func makeID() -> Int {

    defer { nextID += 1 }

    return nextID

  }

}
