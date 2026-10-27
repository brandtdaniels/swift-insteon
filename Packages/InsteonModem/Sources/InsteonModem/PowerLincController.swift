import InsteonProtocol

/// Talks to a PowerLinc Controller (2414S) over a ``ModemConnection``, using IBIOS.
///
/// A PowerLinc Controller doesn't take modem commands. Instead it gives the host access to its
/// memory: an INSTEON message is sent by writing it into the controller's construction buffer
/// and setting its request-to-send flag. Sending a `SerialCommand` translates the modem
/// commands the controller can carry, so code written against `SerialCommandSender` works with
/// it too:
///
/// | Command | IBIOS |
/// | --- | --- |
/// | `SerialCommand.sendStandardMessage(_:)` | Downloads the message to `0x01A4`, confirms it with Get Checksum, then sets bit 4 of `0x0142` |
/// | `SerialCommand.sendX10(_:)` | Downloads the X10 byte to `0x0165`, confirms it with Get Checksum, then sets bit 7 of `0x0166` and bit 3 for a command |
/// | `SerialCommand.getModemInfo` | Get Version, answered with `IBIOSReply.version(_:)` |
///
/// The addresses come from the worked examples in the INSTEON Developer's Guide, chapter 9,
/// which use the i1 INSTEON engine. Other commands, including extended messages, throw
/// ``PowerLincControllerError/unsupported(_:)``.
///
/// The controller's serial port runs at 4800 baud, and messages from devices arrive through
/// the SALad program the controller ships with. Run ``PowerLincController/run()`` alongside
/// the code that sends commands, as with ``Modem``:
///
/// ```swift
/// let controller = PowerLincController(connection: try SerialPort(path: "/dev/ttyUSB0", baudRate: .baud4800))
///
/// try await withThrowingTaskGroup(of: Void.self) { group in
///   group.addTask { try await controller.run() }
///
///   let lamp = InsteonAddress(0xAA, 0xBB, 0xCC)
///   try await controller.send(.sendStandardMessage(
///     StandardMessage(to: lamp, command: StandardDirectCommand.on(level: 0xFF))
///   ))
///
///   group.cancelAll()
/// }
/// ```
public actor PowerLincController: SerialCommandSender {

  /// An IBIOS command, and how to tell that the controller carried it out.
  private struct Step {

    let command: IBIOSCommand

    /// For a Get Checksum that confirms a download, the checksums the download's data reads
    /// back as. Any other checksum means the data wasn't written correctly.
    var confirmingChecksums: Set<UInt16> = []

    /// The error to throw if the controller rejects every attempt.
    var rejected: PowerLincControllerError

    init(_ command: IBIOSCommand) {

      self.command = command
      self.rejected = .rejected(command)

    }

    /// A Get Checksum that confirms a download wrote its data correctly.
    init(confirming address: UInt16, data: [UInt8]) {

      let length = UInt16(data.count)

      self.command = .getChecksum(address: address, length: length)
      // The developer guide describes this checksum as covering the region's bytes, and the
      // download's as also covering its address and length, so either confirms the data.
      self.confirmingChecksums = [
        IBIOSCommand.checksum(of: data),
        IBIOSCommand.checksum(of: [UInt8(address >> 8), UInt8(address & 0xFF), UInt8(length >> 8), UInt8(length & 0xFF)] + data)
      ]
      self.rejected = .unconfirmedDownload(address: address)

    }

  }

  private struct PendingAnswer {

    let id: Int

    let step: Step

    let result: AsyncStream<Result<Bool, any Error>>.Continuation

  }

  /// A command whose send was canceled before the controller answered it.
  private struct UnansweredCommand {

    let id: Int

    let step: Step

    let results: AsyncStream<Result<Bool, any Error>>

  }

  private let connection: any ModemConnection

  private let retryPolicy: Modem.RetryPolicy

  private let clock: any Clock<Duration>

  private var parser = IBIOSReplyParser()

  private var isRunning = false

  private var isClosed = false

  private var nextID = 0

  private var subscribers: [AsyncStream<IBIOSReply>.Continuation] = []

  private var pendingAnswer: PendingAnswer?

  private var unansweredCommand: UnansweredCommand?

  private var turns = TurnQueue()

  /// Creates a controller that talks over a connection.
  ///
  /// - Parameters:
  ///   - connection: The connection to the controller, such as a ``SerialPort`` opened at
  ///     ``SerialPort/BaudRate/baud4800``.
  ///   - retryPolicy: How to wait for and retry commands. Defaults to ``Modem/RetryPolicy/init(attempts:delay:echoTimeout:)``.
  ///   - clock: The clock that times retry delays and timeouts. Defaults to a
  ///     `ContinuousClock`; tests can pass a clock they control.
  public init(
    connection: any ModemConnection,
    retryPolicy: Modem.RetryPolicy = Modem.RetryPolicy(),
    clock: any Clock<Duration> = ContinuousClock()
  ) {

    self.connection = connection
    self.retryPolicy = retryPolicy
    self.clock = clock

  }

  /// Reads everything the controller sends, until the connection closes or the task is
  /// canceled.
  ///
  /// Answers and reports arrive only while this runs, so run it alongside the code that sends
  /// commands. When it returns, the controller is closed: waiting sends fail with
  /// ``PowerLincControllerError/connectionClosed``, and every stream from
  /// ``PowerLincController/replies()`` finishes. Calling it while it's running returns at
  /// once.
  ///
  /// - Throws: The connection's error, if reading from it failed, or
  ///   ``PowerLincControllerError/connectionClosed`` if the controller has already closed.
  public func run() async throws {

    guard !isClosed else {

      throw PowerLincControllerError.connectionClosed

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

  /// Sends a modem command the controller can carry, and waits for the controller to accept
  /// it.
  ///
  /// - Parameter command: A standard message, X10 or `getModemInfo`. The answer to
  ///   `getModemInfo` arrives through ``PowerLincController/replies()`` as
  ///   `IBIOSReply.version(_:)`.
  /// - Throws: ``PowerLincControllerError/unsupported(_:)`` for any other command, without
  ///   sending anything; otherwise the errors sending an `IBIOSCommand` throws.
  public func send(_ command: SerialCommand) async throws {

    let steps = try Self.steps(for: command)

    try await waitForTurn()
    defer { turns.release() }

    try await waitForUnansweredCommand()

    for step in steps {

      try await perform(step)

    }

  }

  /// Sends an IBIOS command and waits for the controller to accept it.
  ///
  /// Commands are sent one at a time, in the order they're called, and a command the
  /// controller rejects is sent again after the retry policy's delay. Canceling a send stops
  /// it, and the next send waits for a canceled command that was written, as with
  /// ``Modem/send(_:)``.
  ///
  /// - Parameter command: The command to send.
  /// - Throws: ``PowerLincControllerError/rejected(_:)`` if the controller NAKs every attempt,
  ///   ``PowerLincControllerError/timedOut(_:)`` if it doesn't answer,
  ///   ``PowerLincControllerError/connectionClosed`` if the controller is closed,
  ///   `CancellationError` if the task is canceled, or the connection's error.
  public func send(_ command: IBIOSCommand) async throws {

    try await waitForTurn()
    defer { turns.release() }

    try await waitForUnansweredCommand()

    try await perform(Step(command))

  }

  /// Returns a stream of everything the controller sends from now on.
  ///
  /// Each call returns a new stream, so several parts of an app can listen at once. A stream
  /// finishes when the controller closes.
  ///
  /// - Returns: The controller's replies, in the order they arrive.
  public func replies() -> AsyncStream<IBIOSReply> {

    let (stream, continuation) = AsyncStream<IBIOSReply>.makeStream()

    if isClosed {

      continuation.finish()

    } else {

      subscribers.append(continuation)

    }

    return stream

  }

  // MARK: - Translating modem commands

  /// Addresses in the controller's memory, from the developer guide's worked examples.
  private enum Memory {

    /// The To address in the message construction buffer. The controller fills in the From
    /// address before it.
    static let messageDestination: UInt16 = 0x01A4

    /// I_Control, whose bit 4 requests that the message in the construction buffer be sent.
    static let insteonControl: UInt16 = 0x0142

    static let insteonRequestToSend: UInt8 = 0b0001_0000

    /// X10_TX, the X10 transmit buffer.
    static let x10Transmit: UInt16 = 0x0165

    /// X10_FLAGS, whose bit 7 requests that the X10 byte be sent and bit 3 marks it a command.
    static let x10Flags: UInt16 = 0x0166

    static let x10RequestToSend: UInt8 = 0b1000_0000

    static let x10IsCommand: UInt8 = 0b0000_1000

  }

  /// The steps that carry a modem command. Each download is confirmed with Get Checksum before
  /// the flag that sends it is set, as the developer guide advises, since an ACK means only that
  /// the controller received the bytes.
  private static func steps(for command: SerialCommand) throws(PowerLincControllerError) -> [Step] {

    switch command {
    case let .sendStandardMessage(message):
      return download(message.bytes, to: Memory.messageDestination) + [
        Step(.mask(address: Memory.insteonControl, or: Memory.insteonRequestToSend, and: 0xFF))
      ]
    case let .sendX10(code):
      let isCommand = if case .command = code { true } else { false }

      return download([code.rawX10], to: Memory.x10Transmit) + [
        Step(.mask(
          address: Memory.x10Flags,
          or: Memory.x10RequestToSend | (isCommand ? Memory.x10IsCommand : 0),
          and: isCommand ? 0xFF : ~Memory.x10IsCommand
        ))
      ]
    case .getModemInfo:
      return [Step(.getVersion)]
    default:
      throw .unsupported(command)
    }

  }

  private static func download(_ data: [UInt8], to address: UInt16) -> [Step] {

    [Step(.download(address: address, data: data)), Step(confirming: address, data: data)]

  }

  // MARK: - Sending

  private func perform(_ step: Step) async throws {

    for attempt in 1...retryPolicy.attempts {

      try Task.checkCancellation()

      if try await transmit(step) {

        return

      }

      if attempt < retryPolicy.attempts {

        try await clock.sleep(for: retryPolicy.delay)

      }

    }

    throw step.rejected

  }

  /// Writes a command and waits for its answer, a NAK, the timeout or cancellation.
  ///
  /// - Returns: Whether the controller accepted the command.
  private func transmit(_ step: Step) async throws -> Bool {

    guard !isClosed else {

      throw PowerLincControllerError.connectionClosed

    }

    let id = makeID()
    let (results, continuation) = AsyncStream<Result<Bool, any Error>>.makeStream()

    pendingAnswer = PendingAnswer(id: id, step: step, result: continuation)
    defer { abandonAnswer(id) }

    return try await awaitAnswer(id, command: step.command, results: results) { [connection] in

      try await connection.write(step.command.bytes)

    }.get()

  }

  /// Waits for the controller to answer a command whose send was canceled, so the next
  /// command isn't written while the controller is still busy with it.
  private func waitForUnansweredCommand() async throws {

    guard let unanswered = unansweredCommand else {

      return

    }

    unansweredCommand = nil
    defer { abandonAnswer(unanswered.id) }

    _ = await awaitAnswer(unanswered.id, command: unanswered.step.command, results: unanswered.results) {}

    try Task.checkCancellation()

  }

  /// Runs `write`, then waits for the pending answer's result, the timeout or cancellation.
  private func awaitAnswer(
    _ id: Int,
    command: IBIOSCommand,
    results: AsyncStream<Result<Bool, any Error>>,
    write: @escaping @Sendable () async throws -> Void
  ) async -> Result<Bool, any Error> {

    let timeout = retryPolicy.echoTimeout + Self.transferTime(of: command)

    return await withTaskGroup(of: Void.self, returning: Result<Bool, any Error>.self) { group in

      // Writes, then gives up on the answer once the timeout passes. The group cancels this
      // child as soon as the answer arrives.
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

        await self.answerTimedOut(id, command: command)

      }

      defer { group.cancelAll() }

      for await result in results {

        return result

      }

      // The stream ends without a result only when this task is canceled.
      return .failure(CancellationError())

    }

  }

  /// Fails the command waiting for an answer, unless the parser is holding back a NAK for it.
  private func answerTimedOut(_ id: Int, command: IBIOSCommand) {

    guard pendingAnswer?.id == id else {

      return

    }

    deliver(parser.finishPendingReply())
    failAnswer(id, with: PowerLincControllerError.timedOut(command))

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

    pendingAnswer = PendingAnswer(id: id, step: pending.step, result: continuation)
    unansweredCommand = UnansweredCommand(id: id, step: pending.step, results: results)

  }

  private func completePendingAnswer(_ result: Result<Bool, any Error>) {

    guard let pending = pendingAnswer else {

      return

    }

    pendingAnswer = nil
    pending.result.yield(result)
    pending.result.finish()

  }

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

  private func deliver(_ replies: [IBIOSReply]) {

    for reply in replies {

      if let pending = pendingAnswer, let isAccepted = Self.answer(reply, to: pending.step) {

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

  /// How long the data a command moves takes to cross the serial port at 4800 baud, where
  /// each byte takes 10 bits, so a large upload or download isn't timed out before it
  /// finishes.
  private static func transferTime(of command: IBIOSCommand) -> Duration {

    let byteCount = switch command {
    case let .download(_, data): data.count
    case let .upload(_, length): Int(length)
    default: 0
    }

    return .seconds(byteCount * 10) / 4800

  }

  /// Whether a reply answers a step: `true` if it accepts it, `false` if it rejects it, or
  /// `nil` if it's about something else.
  private static func answer(_ reply: IBIOSReply, to step: Step) -> Bool? {

    let command = step.command

    switch (reply, command) {
    case let (.echo(echo), _) where echo.number == command.number:
      // A download's echo repeats only its address and length. Matching the parameters keeps a
      // late echo of an earlier command from answering this one.
      let expected = Array(command.parameters.prefix(command.number == 0x40 ? 4 : command.parameters.count))

      if echo.isAccepted {

        return echo.parameters == expected ? true : nil

      }

      return echo.parameters.isEmpty || echo.parameters == expected ? false : nil
    case (.version, .getVersion):
      return true
    case let (.memory(address, data, isIntact), .upload(expectedAddress, length)):
      // Memory that arrives damaged is read again.
      return address == expectedAddress && data.count == Int(length) ? isIntact : nil
    case let (.checksum(address, length, checksum), .getChecksum(expectedAddress, expectedLength)):
      guard address == expectedAddress && length == expectedLength else {

        return nil

      }

      return step.confirmingChecksums.isEmpty || step.confirmingChecksums.contains(checksum)
    case (.negativeAcknowledgement, _):
      return false
    default:
      return nil
    }

  }

  private func close(with error: (any Error)?) {

    isClosed = true
    completePendingAnswer(.failure(error ?? PowerLincControllerError.connectionClosed))

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
