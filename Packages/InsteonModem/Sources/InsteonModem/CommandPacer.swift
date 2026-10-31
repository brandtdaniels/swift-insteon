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

/// One step of the answer to an ``Exchange``, such as a modem's echo.
struct AnswerStep<Reply>: Sendable {

  /// What a reply means for the step, or `nil` if it's about something else.
  let verdict: @Sendable (Reply) -> Verdict?

  /// The error to throw if the step isn't completed in time.
  let timedOut: any Error

  /// The error to throw in place of `timedOut` if the device has sent anything since the pacer
  /// started reading, so it was connected and powered and is more likely busy than gone, or
  /// `nil` to throw `timedOut` either way.
  var timedOutAfterReplies: (any Error)? = nil

}

/// A command for ``CommandPacer`` to write, and how to recognize the answer to it.
struct Exchange<Reply>: Sendable {

  /// The command's bytes.
  let bytes: [UInt8]

  /// The steps of the answer, in order, such as a modem's echo and then a device's
  /// acknowledgment. Only the current step sees each reply, and the reply that completes the
  /// last step answers the command.
  let steps: [AnswerStep<Reply>]

  /// How long to wait for the answer, or `nil` for the retry policy's answer timeout.
  var timeout: Duration?

  /// How much longer than the timeout to wait for the answer, for a command that moves a lot
  /// of data or takes a long time to carry out.
  var transferTime: Duration

  /// Whether a rejection means the exchange before this one went wrong, so each new attempt
  /// sends that exchange again first. A check that reads back what the previous command wrote
  /// does this, since reading again would find the same mistake. Both count as one attempt.
  var repeatsPrevious: Bool

  /// Creates an exchange whose answer comes in steps.
  init(
    bytes: [UInt8],
    steps: [AnswerStep<Reply>],
    timeout: Duration? = nil,
    transferTime: Duration = .zero,
    repeatsPrevious: Bool = false
  ) {

    precondition(!steps.isEmpty, "An exchange needs at least one step to answer it.")

    self.bytes = bytes
    self.steps = steps
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
  ///   - timedOut: The error to throw if the device doesn't answer.
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
      steps: [
        AnswerStep(verdict: { reply in answer(reply).map { $0 ? .accepted : .rejected(rejected) } }, timedOut: timedOut)
      ],
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

  /// A step wasn't completed in time, so the attempt ended with the step's `timedOut` error.
  /// `isUnanswered` is `true` if no step was completed, so nothing answered the command.
  case timedOut(any Error, isUnanswered: Bool)

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

    let steps: [AnswerStep<Reply>]

    /// The step the next reply is checked against.
    var step = 0

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

  /// How many chunks of bytes have arrived, so a timeout can tell whether anything arrived
  /// while it waited.
  private var receivedChunks = 0

  private var isClosed = false

  /// Whether the device has sent anything since the pacer started reading or since the last
  /// command it didn't answer at all.
  private var hasReceivedReplies = false

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

        receivedChunks &+= 1
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
  /// - Throws: The error of a reply that rejected or failed a command, the `timedOut` error of
  ///   a step that wasn't completed in time, `closedError` if the device is closed, `CancellationError` if the
  ///   task is canceled, or the connection's error. A command that was rejected and then not
  ///   answered at all throws the rejection, not the `timedOut` error.
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

  /// The turn a ``CommandPacer/withTurn(_:)`` body holds, through which it sends its commands.
  struct Turn: Sendable {

    fileprivate let pacer: CommandPacer

    /// Writes a command in the held turn and waits for its answer, sending it again as the
    /// retry policy allows if the device rejects it.
    ///
    /// - Parameter exchange: The command to write.
    /// - Returns: The reply that answered the command.
    /// - Throws: The errors of ``CommandPacer/send(_:)``.
    func send(_ exchange: Exchange<Reply>) async throws -> Reply {

      try await pacer.perform(exchange)

    }

    /// Returns a stream of everything the device sends after this call, so a body that
    /// listens from within its turn hears only what follows its own commands.
    func replies() async -> AsyncStream<Reply> {

      await pacer.replies()

    }

  }

  /// Holds one turn while `body` sends commands, for a sequence whose next command depends on
  /// the answer to the last, such as a scan that ends when the device says there's no more.
  ///
  /// No other send writes until `body` returns, so nothing can come between its commands.
  ///
  /// - Parameter body: Sends the commands through the turn it's given.
  /// - Returns: What `body` returns.
  /// - Throws: `CancellationError` if the task is canceled while waiting for the turn, or what
  ///   `body` throws.
  func withTurn<Value: Sendable>(_ body: @Sendable (Turn) async throws -> Value) async throws -> Value {

    try await waitForTurn()
    defer { turns.release() }

    try await waitForUnansweredCommand()

    return try await body(Turn(pacer: self))

  }

  /// Writes a command once in a turn of its own and holds the turn until a step of its answer
  /// fails or the last step is accepted, without writing it again, for a command whose answer
  /// the caller reads from ``CommandPacer/replies()`` itself.
  ///
  /// A step's verdict of `.rejected` ends the wait like `.accepted` does; nothing is retried.
  ///
  /// - Parameter exchange: The command to write, and the replies that end the wait.
  /// - Throws: The `timedOut` error of a step that wasn't completed in time, the error of a
  ///   step that failed, `closedError` if the device is closed, `CancellationError` if the task
  ///   is canceled, or the connection's error.
  func sendOnce(_ exchange: Exchange<Reply>) async throws {

    try await waitForTurn()
    defer { turns.release() }

    try await waitForUnansweredCommand()
    try Task.checkCancellation()

    if case let .timedOut(error, _) = try await transmit(exchange) {

      throw error

    }

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
  /// An attempt that isn't answered in time ends the exchange. If an earlier attempt was
  /// rejected and nothing answered the retry at all, the rejection is thrown, since it says
  /// more about why the command failed than the silence that followed it. A later step that
  /// times out, such as a device's acknowledgment after the modem's echo, throws its own
  /// `timedOut` error, as does the previous exchange.
  ///
  /// - Parameter previous: The exchange to send again before each attempt after the first.
  ///   An attempt counts as rejected if the device rejects either one.
  /// - Returns: The reply that answered the exchange.
  /// - Throws: The error of the last rejection if every attempt is rejected, or if nothing
  ///   answers an attempt after a rejected one; otherwise the `timedOut` error of the step
  ///   that wasn't completed in time; or the errors of ``CommandPacer/send(_:)``.
  private func perform(_ exchange: Exchange<Reply>, repeating previous: Exchange<Reply>? = nil) async throws -> Reply {

    try Task.checkCancellation()

    var rejection: any Error

    switch try await transmit(exchange) {
    case let .accepted(reply):
      return reply
    case let .rejected(error):
      rejection = error
    case let .timedOut(error, _):
      throw error
    }

    for _ in 1..<retryPolicy.attempts {

      try await clock.sleep(for: retryPolicy.delay)
      try Task.checkCancellation()

      if let previous {

        switch try await transmit(previous) {
        case .accepted:
          break
        case .rejected:
          // A previous exchange that's rejected counts as this one being rejected again.
          continue
        case let .timedOut(error, _):
          throw error
        }

      }

      switch try await transmit(exchange) {
      case let .accepted(reply):
        return reply
      case let .rejected(error):
        rejection = error
      case let .timedOut(error, isUnanswered):
        // A device that doesn't answer once the modem has taken the command says more than
        // the modem's earlier rejection.
        throw isUnanswered ? rejection : error
      }

    }

    throw rejection

  }

  /// Writes a command and waits for its answer, the timeout or cancellation.
  ///
  /// - Returns: How the attempt ended, including a step that wasn't completed in time.
  private func transmit(_ exchange: Exchange<Reply>) async throws -> Outcome<Reply> {

    guard !isClosed else {

      throw closedError

    }

    // Pending bytes are read as answers to this command before it can be answered, so a frame
    // that can't answer it doesn't take the answer as its own bytes.
    deliver(parser.willWrite(exchange.bytes))

    let id = makeID()
    let (results, continuation) = Results.makeStream()

    let timeout = (exchange.timeout ?? retryPolicy.answerTimeout) + exchange.transferTime

    pendingAnswer = PendingAnswer(
      id: id,
      steps: exchange.steps,
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
  ///
  /// The timeout bounds the whole exchange, the write included: a write still going when the
  /// timeout passes is canceled, and the answer times out. The time a write takes leaves that
  /// much less for the answer. So that a test on a clock it controls sees one sleeper at the
  /// timeout's deadline, and only once the write is done, the write's own limit is a
  /// nanosecond past it.
  private func awaitAnswer(
    _ id: Int,
    timeout: Duration,
    results: Results,
    write: @escaping @Sendable () async throws -> Void
  ) async -> Result<Outcome<Reply>, any Error> {

    // A frame pending before the write that's still pending at the timeout has stalled.
    let frameBeforeWrite: Int? = parser.pendingFrameStart

    return await withTaskGroup(of: Void.self, returning: Result<Outcome<Reply>, any Error>.self) { group in

      // Writes, then gives up on the answer once the timeout passes. The group cancels this
      // child as soon as the answer arrives, so a timeout never outlives its command.
      group.addTask { [clock] in

        var isWritten = false
        let writing: Duration

        do {

          writing = try await clock.measure {

            isWritten = try await Self.write(write, within: timeout, on: clock)

          }

        } catch {

          await self.failAnswer(id, with: error)

          return

        }

        guard isWritten else {

          await self.answerTimedOut(id, chunksBeforeWait: nil, frameBeforeWrite: frameBeforeWrite)

          return

        }

        // Whether anything arrives during the wait tells a frame still arriving from one that
        // stalled.
        let chunksBeforeWait: Int = await self.receivedChunks

        do {

          try await clock.sleep(for: max(timeout - writing, .zero))

        } catch {

          return

        }

        await self.answerTimedOut(id, chunksBeforeWait: chunksBeforeWait, frameBeforeWrite: frameBeforeWrite)

      }

      defer { group.cancelAll() }

      for await result in results {

        return result

      }

      // The stream ends without a result only when this task is canceled.
      return .failure(CancellationError())

    }

  }

  /// Runs a write, and cancels it if it's still going a nanosecond after `timeout`.
  ///
  /// - Returns: `true` once the write finishes, or `false` if the time ran out first.
  /// - Throws: The write's error.
  private static func write(
    _ write: @escaping @Sendable () async throws -> Void,
    within timeout: Duration,
    on clock: any Clock<Duration>
  ) async throws -> Bool {

    try await withThrowingTaskGroup(of: Bool.self, returning: Bool.self) { group in

      group.addTask {

        try await write()

        return true

      }

      group.addTask {

        try await clock.sleep(for: timeout + .nanoseconds(1))

        return false

      }

      defer { group.cancelAll() }

      return try await group.next() ?? false

    }

  }

  /// Fails the command waiting for an answer, unless the parser is holding back a NAK for it,
  /// which only more bytes or the end of the wait can tell apart from data.
  ///
  /// A frame the parser is still waiting on has stalled when nothing at all arrived during the
  /// wait, or when it was already pending before the command was written, such as one begun by
  /// line noise, so it's discarded whole; a frame still arriving is left alone. Bytes being
  /// skipped stop being skipped either way.
  ///
  /// - Parameters:
  ///   - chunksBeforeWait: How many chunks had arrived when the wait started, or `nil` if the
  ///     write never finished.
  ///   - frameBeforeWrite: Where the frame pending before the write started, if any.
  private func answerTimedOut(_ id: Int, chunksBeforeWait: Int?, frameBeforeWrite: Int?) {

    guard let pending = pendingAnswer, pending.id == id else {

      return

    }

    let step: AnswerStep<Reply> = pending.steps[pending.step]

    deliver(parser.finishPendingReply())

    let pendingFrame: Int? = parser.pendingFrameStart
    let isQuiet: Bool = chunksBeforeWait == receivedChunks
    let isLeftOver: Bool = pendingFrame != nil && pendingFrame == frameBeforeWrite

    if pendingFrame == nil || isQuiet || isLeftOver {

      parser.discardStalledFrame()

    }

    // A NAK the parser was holding back may have answered the command.
    guard pendingAnswer?.id == id else {

      return

    }

    // A device that has sent something since its last unanswered command is connected and
    // powered, so a step with an error for that case reports it. A second unanswered command with
    // nothing heard in between reports the step's own error, since the device may have stopped
    // working.
    let timedOut: any Error = hasReceivedReplies ? (step.timedOutAfterReplies ?? step.timedOut) : step.timedOut

    let isUnanswered: Bool = pending.step == 0

    if isUnanswered {

      hasReceivedReplies = false

    }

    completePendingAnswer(.success(.timedOut(timedOut, isUnanswered: isUnanswered)))

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

    if !replies.isEmpty {

      hasReceivedReplies = true

    }

    for reply in replies {

      if let pending = pendingAnswer, let verdict = pending.steps[pending.step].verdict(reply) {

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
