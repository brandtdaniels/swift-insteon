import InsteonProtocol

/// What a reply means for the step of an ``Exchange`` waiting on it.
enum Verdict: Sendable {

  /// The reply completes the step.
  case accepted

  /// The reply rejects the command, so it's written again if the retry policy allows. The
  /// error is thrown if every attempt is rejected.
  case rejected(any Error)

  /// The reply fails the command in a way that writing it again won't fix.
  case failed(any Error)

}

/// A command for ``CommandPacer`` to write, and how to recognize the answer to it.
struct Exchange<Reply>: Sendable {

  /// The command's bytes.
  let bytes: [UInt8]

  /// The steps of the answer, in order, such as a modem's echo and then a device's
  /// acknowledgement. Each says what a reply means for it, or `nil` if the reply is about
  /// something else. Only the current step sees each reply, and the reply that completes the
  /// last step answers the command.
  let steps: [@Sendable (Reply) -> Verdict?]

  /// The error to throw if the answer doesn't arrive.
  let timedOut: any Error

  /// How long to wait for the answer, or `nil` for the retry policy's answer timeout.
  var timeout: Duration?

  /// How much longer than the timeout to wait for the answer, for a command that moves a lot
  /// of data.
  var transferTime: Duration

  /// Whether a rejection means the exchange before this one went wrong, so each new attempt
  /// sends that exchange again first. A check that reads back what the previous command wrote
  /// does this, since reading again would find the same mistake. Both count as one attempt.
  var repeatsPrevious: Bool

  /// Creates an exchange whose answer comes in steps.
  init(
    bytes: [UInt8],
    steps: [@Sendable (Reply) -> Verdict?],
    timedOut: any Error,
    timeout: Duration? = nil,
    transferTime: Duration = .zero,
    repeatsPrevious: Bool = false
  ) {

    precondition(!steps.isEmpty, "An exchange needs at least one step to answer it.")

    self.bytes = bytes
    self.steps = steps
    self.timedOut = timedOut
    self.timeout = timeout
    self.transferTime = transferTime
    self.repeatsPrevious = repeatsPrevious

  }

  /// Creates an exchange answered by a single reply.
  ///
  /// - Parameters:
  ///   - answer: Whether a reply answers the command: `true` if it accepts it, `false` if it
  ///     rejects it, or `nil` if it's about something else.
  ///   - rejected: The error to throw if the device rejects every attempt.
  init(
    bytes: [UInt8],
    answer: @escaping @Sendable (Reply) -> Bool?,
    rejected: any Error,
    timedOut: any Error,
    transferTime: Duration = .zero,
    repeatsPrevious: Bool = false
  ) {

    self.init(
      bytes: bytes,
      steps: [{ reply in answer(reply).map { $0 ? .accepted : .rejected(rejected) } }],
      timedOut: timedOut,
      transferTime: transferTime,
      repeatsPrevious: repeatsPrevious
    )

  }

}

/// How an attempt at an exchange ended.
private enum Outcome<Reply: Sendable>: Sendable {

  /// The reply completed every step.
  case accepted(Reply)

  /// A reply rejected the command with this error.
  case rejected(any Error)

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

  private typealias Results = AsyncStream<Result<Outcome<Reply>, any Error>>

  /// The command waiting for its answer.
  private struct PendingAnswer {

    let id: Int

    let steps: [@Sendable (Reply) -> Verdict?]

    /// The step the next reply is checked against.
    var step = 0

    let timedOut: any Error

    let timeout: Duration

    var result: Results.Continuation

  }

  /// A command whose send was canceled before the device answered it.
  private struct UnansweredCommand {

    let id: Int

    let timeout: Duration

    let results: Results

  }

  private let connection: any ModemConnection

  private let retryPolicy: RetryPolicy

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
    retryPolicy: RetryPolicy,
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
  /// - Returns: The reply that answered each command, in order.
  /// - Throws: The error of a reply that rejected or failed a command, an exchange's
  ///   `timedOut` error, `closedError` if the device is closed, `CancellationError` if the
  ///   task is canceled, or the connection's error.
  @discardableResult
  func send(_ exchanges: [Exchange<Reply>]) async throws -> [Reply] {

    try await waitForTurn()
    defer { turns.release() }

    try await waitForUnansweredCommand()

    var answers: [Reply] = []

    for (index, exchange) in exchanges.enumerated() {

      let previous = exchange.repeatsPrevious && index > 0 ? exchanges[index - 1] : nil

      answers.append(try await perform(exchange, repeating: previous))

    }

    return answers

  }

  /// Returns a stream of everything the device sends after this call, which finishes when the
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

  /// Sends an exchange until the device accepts it, as many times as the retry policy allows.
  ///
  /// - Parameter previous: The exchange to send again before each attempt after the first.
  ///   An attempt counts as rejected if the device rejects either one.
  /// - Returns: The reply that answered the exchange.
  private func perform(_ exchange: Exchange<Reply>, repeating previous: Exchange<Reply>? = nil) async throws -> Reply {

    let attempts = retryPolicy.attempts

    // The first attempt sends only the exchange, so its rejection is always set before a
    // previous exchange can be rejected.
    var rejection: (any Error)?

    for attempt in 1...attempts {

      try Task.checkCancellation()

      var isPreviousAccepted = true

      if attempt > 1, let previous, case .rejected = try await transmit(previous) {

        isPreviousAccepted = false

      }

      if isPreviousAccepted {

        switch try await transmit(exchange) {
        case let .accepted(reply):
          return reply
        case let .rejected(error):
          rejection = error
        }

      }

      if attempt < attempts {

        try await clock.sleep(for: retryPolicy.delay)

      }

    }

    throw rejection ?? exchange.timedOut

  }

  /// Writes a command and waits for its answer, the timeout or cancellation.
  ///
  /// - Returns: How the attempt ended.
  private func transmit(_ exchange: Exchange<Reply>) async throws -> Outcome<Reply> {

    guard !isClosed else {

      throw closedError

    }

    let id = makeID()
    let (results, continuation) = Results.makeStream()

    let timeout = (exchange.timeout ?? retryPolicy.answerTimeout) + exchange.transferTime

    pendingAnswer = PendingAnswer(
      id: id,
      steps: exchange.steps,
      timedOut: exchange.timedOut,
      timeout: timeout,
      result: continuation
    )
    defer { abandonAnswer(id) }

    return try await awaitAnswer(id, timeout: timeout, results: results) { [connection] in

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

    _ = await awaitAnswer(unanswered.id, timeout: unanswered.timeout, results: unanswered.results) {}

    try Task.checkCancellation()

  }

  /// Runs `write`, then waits for the pending answer's result, the timeout or cancellation.
  private func awaitAnswer(
    _ id: Int,
    timeout: Duration,
    results: Results,
    write: @escaping @Sendable () async throws -> Void
  ) async -> Result<Outcome<Reply>, any Error> {

    await withTaskGroup(of: Void.self, returning: Result<Outcome<Reply>, any Error>.self) { group in

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

    let (results, continuation) = Results.makeStream()

    var unanswered = pending
    unanswered.result = continuation
    pendingAnswer = unanswered
    unansweredCommand = UnansweredCommand(id: id, timeout: pending.timeout, results: results)

  }

  private func completePendingAnswer(_ result: Result<Outcome<Reply>, any Error>) {

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

      if let pending = pendingAnswer, let verdict = pending.steps[pending.step](reply) {

        switch verdict {
        case .accepted where pending.step < pending.steps.count - 1:
          pendingAnswer?.step += 1
        case .accepted:
          completePendingAnswer(.success(.accepted(reply)))
        case let .rejected(error):
          completePendingAnswer(.success(.rejected(error)))
        case let .failed(error):
          completePendingAnswer(.failure(error))
        }

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
/// - Throws: The error `run` throws, if reading from the device failed, since that's usually
///   why `body` failed too; otherwise the error `body` throws.
package func withRunning<Value>(
  _ run: @escaping @Sendable () async throws -> Void,
  isolation: isolated (any Actor)? = #isolation,
  _ body: () async throws -> Value
) async throws -> Value {

  try await withThrowingTaskGroup(of: Void.self, returning: Value.self) { group in

    group.addTask {

      do {

        try await run()

      } catch is CancellationError {

        // Stopping the reading is how the scope ends, not a failure.

      }

    }

    let result: Value

    do {

      result = try await body()

    } catch {

      group.cancelAll()

      // The group would otherwise discard an error from run.
      try await group.waitForAll()

      throw error

    }

    group.cancelAll()
    try await group.waitForAll()

    return result

  }

}
