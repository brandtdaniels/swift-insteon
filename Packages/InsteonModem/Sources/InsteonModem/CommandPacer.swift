import InsteonProtocol

/// Parses the replies a device sends, from bytes as they arrive.
protocol ReplyParser: Sendable {

  /// What the device sends.
  associatedtype Reply: Sendable

  /// Parses received bytes, keeping any incomplete reply until the rest arrives.
  mutating func parse(_ bytes: some Sequence<UInt8>) -> [Reply]

  /// Reports a reply held back because it can't yet be told apart from a longer one.
  mutating func finishPendingReply() -> [Reply]

}

extension ModemReplyParser: ReplyParser {}

extension IBIOSReplyParser: ReplyParser {}

/// A command for ``CommandPacer`` to write, and how to recognize the device's answer to it.
struct Exchange<Reply>: Sendable {

  /// The command's bytes.
  let bytes: [UInt8]

  /// Whether a reply answers the command: `true` if it accepts it, `false` if it rejects it,
  /// or `nil` if it's about something else.
  let answer: @Sendable (Reply) -> Bool?

  /// The error to throw if the device rejects every attempt.
  let rejected: any Error

  /// The error to throw if the device doesn't answer.
  let timedOut: any Error

}

/// Paces commands to a device that answers each one before it takes the next, such as a
/// PowerLinc Modem or a PowerLinc Controller.
///
/// Commands are written one at a time, in the order they're sent. Each waits for its answer,
/// is written again after the retry policy's delay if the device rejects it, and fails if the
/// device doesn't answer in time. Everything the device sends is published to every stream from
/// ``CommandPacer/replies()``. The parser and each ``Exchange`` supply what's specific to the
/// device's protocol.
actor CommandPacer<Parser: ReplyParser> {

  typealias Reply = Parser.Reply

  /// The command waiting for its answer.
  private struct PendingAnswer {

    let id: Int

    let answer: @Sendable (Reply) -> Bool?

    let timedOut: any Error

    let result: AsyncStream<Result<Bool, any Error>>.Continuation

  }

  /// A command whose send was canceled before the device answered it.
  private struct UnansweredCommand {

    let id: Int

    let timedOut: any Error

    let results: AsyncStream<Result<Bool, any Error>>

  }

  private let connection: any ModemConnection

  private let retryPolicy: Modem.RetryPolicy

  private let clock: any Clock<Duration>

  private let closedError: any Error

  private var parser: Parser

  private var isRunning = false

  private var isClosed = false

  private var nextID = 0

  private var subscribers: [AsyncStream<Reply>.Continuation] = []

  private var pendingAnswer: PendingAnswer?

  private var unansweredCommand: UnansweredCommand?

  private var turns = TurnQueue()

  /// Creates a pacer for a device on a connection.
  ///
  /// - Parameters:
  ///   - connection: The connection to the device.
  ///   - parser: The parser for what the device sends.
  ///   - retryPolicy: How to wait for and retry commands.
  ///   - clock: The clock that times retry delays and timeouts.
  ///   - closedError: The error sends throw once the device is closed.
  init(
    connection: any ModemConnection,
    parser: Parser,
    retryPolicy: Modem.RetryPolicy,
    clock: any Clock<Duration>,
    closedError: any Error
  ) {

    self.connection = connection
    self.parser = parser
    self.retryPolicy = retryPolicy
    self.clock = clock
    self.closedError = closedError

  }

  /// Reads everything the device sends, until the connection closes or the task is canceled,
  /// then closes the device.
  ///
  /// - Throws: The connection's error, or `closedError` if the device has already closed.
  func run() async throws {

    guard !isClosed else {

      throw closedError

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

  /// Writes commands in one turn, each once the device has accepted the one before.
  ///
  /// A command written by a canceled send still holds the device, so the turn starts by
  /// waiting for that command's answer, or for the timeout.
  ///
  /// - Parameter exchanges: The commands to write, in order.
  /// - Throws: An exchange's `rejected` or `timedOut` error, `closedError` if the device is
  ///   closed, `CancellationError` if the task is canceled, or the connection's error.
  func send(_ exchanges: [Exchange<Reply>]) async throws {

    try await waitForTurn()
    defer { turns.release() }

    try await waitForUnansweredCommand()

    for exchange in exchanges {

      try await perform(exchange)

    }

  }

  /// Returns a stream of everything the device sends from now on, which finishes when the
  /// device closes.
  func replies() -> AsyncStream<Reply> {

    let (stream, continuation) = AsyncStream<Reply>.makeStream()

    if isClosed {

      continuation.finish()

    } else {

      subscribers.append(continuation)

    }

    return stream

  }

  // MARK: - Sending

  private func perform(_ exchange: Exchange<Reply>) async throws {

    for attempt in 1...retryPolicy.attempts {

      try Task.checkCancellation()

      if try await transmit(exchange) {

        return

      }

      if attempt < retryPolicy.attempts {

        try await clock.sleep(for: retryPolicy.delay)

      }

    }

    throw exchange.rejected

  }

  /// Writes a command and waits for its answer, the timeout or cancellation.
  ///
  /// - Returns: Whether the device accepted the command.
  private func transmit(_ exchange: Exchange<Reply>) async throws -> Bool {

    guard !isClosed else {

      throw closedError

    }

    let id = makeID()
    let (results, continuation) = AsyncStream<Result<Bool, any Error>>.makeStream()

    pendingAnswer = PendingAnswer(id: id, answer: exchange.answer, timedOut: exchange.timedOut, result: continuation)
    defer { abandonAnswer(id) }

    return try await awaitAnswer(id, results: results) { [connection] in

      try await connection.write(exchange.bytes)

    }.get()

  }

  /// Waits for the device to answer a command whose send was canceled, so the next command
  /// isn't written while the device is still busy with it.
  private func waitForUnansweredCommand() async throws {

    guard let unanswered = unansweredCommand else {

      return

    }

    unansweredCommand = nil
    defer { abandonAnswer(unanswered.id) }

    _ = await awaitAnswer(unanswered.id, results: unanswered.results) {}

    try Task.checkCancellation()

  }

  /// Runs `write`, then waits for the pending answer's result, the timeout or cancellation.
  private func awaitAnswer(
    _ id: Int,
    results: AsyncStream<Result<Bool, any Error>>,
    write: @escaping @Sendable () async throws -> Void
  ) async -> Result<Bool, any Error> {

    let timeout = retryPolicy.echoTimeout

    return await withTaskGroup(of: Void.self, returning: Result<Bool, any Error>.self) { group in

      // Writes, then gives up on the answer once the timeout passes. The group cancels this
      // child as soon as the answer arrives, so a timeout never outlives its command.
      group.addTask { [clock] in

        do {

          try await write()

        } catch {

          await self.failAnswer(id, with: error)

          return

        }

        do {

          try await clock.sleep(for: timeout)

        } catch {

          return

        }

        await self.answerTimedOut(id)

      }

      defer { group.cancelAll() }

      for await result in results {

        return result

      }

      // The stream ends without a result only when this task is canceled.
      return .failure(CancellationError())

    }

  }

  /// Fails the command waiting for an answer, unless the parser is holding back a NAK for it,
  /// which only more bytes or the end of the wait can tell apart from data.
  private func answerTimedOut(_ id: Int) {

    guard let pending = pendingAnswer, pending.id == id else {

      return

    }

    deliver(parser.finishPendingReply())
    failAnswer(id, with: pending.timedOut)

  }

  private func failAnswer(_ id: Int, with error: any Error) {

    guard pendingAnswer?.id == id else {

      return

    }

    completePendingAnswer(.failure(error))

  }

  /// Stops waiting for an answer whose send was canceled. The command may have been written,
  /// so its answer stays pending, and the next send waits for it.
  private func abandonAnswer(_ id: Int) {

    guard let pending = pendingAnswer, pending.id == id else {

      return

    }

    pending.result.finish()

    let (results, continuation) = AsyncStream<Result<Bool, any Error>>.makeStream()

    pendingAnswer = PendingAnswer(id: id, answer: pending.answer, timedOut: pending.timedOut, result: continuation)
    unansweredCommand = UnansweredCommand(id: id, timedOut: pending.timedOut, results: results)

  }

  private func completePendingAnswer(_ result: Result<Bool, any Error>) {

    guard let pending = pendingAnswer else {

      return

    }

    pendingAnswer = nil
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

  private func deliver(_ replies: [Reply]) {

    for reply in replies {

      if let pending = pendingAnswer, let isAccepted = pending.answer(reply) {

        completePendingAnswer(.success(isAccepted))

      }

      // A stream whose listener has stopped listening is dropped.
      subscribers.removeAll { subscriber in

        if case .terminated = subscriber.yield(reply) {

          return true

        }

        return false

      }

    }

  }

  private func close(with error: (any Error)?) {

    isClosed = true
    completePendingAnswer(.failure(error ?? closedError))

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

/// Runs `body` while `run` reads from a device in a child task, then stops reading.
///
/// - Parameters:
///   - run: Reads from the device until it's canceled.
///   - isolation: The actor `body` runs on.
///   - body: The work to do with the device.
/// - Returns: What `body` returns.
/// - Throws: The error `body` throws, or the error `run` throws.
func withRunning<Value>(
  _ run: @escaping @Sendable () async throws -> Void,
  isolation: isolated (any Actor)? = #isolation,
  _ body: () async throws -> Value
) async throws -> Value {

  try await withThrowingTaskGroup(of: Void.self, returning: Value.self) { group in

    group.addTask { try await run() }
    defer { group.cancelAll() }

    let result = try await body()

    group.cancelAll()

    // The group would otherwise discard an error from run.
    try await group.waitForAll()

    return result

  }

}
