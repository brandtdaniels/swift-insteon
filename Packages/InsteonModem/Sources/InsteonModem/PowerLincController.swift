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
/// | `SerialCommand.sendStandardMessage(_:)` | Downloads the message to `0x01A4`, then sets bit 4 of `0x0142` |
/// | `SerialCommand.sendX10(_:)` | Downloads the X10 byte to `0x0165`, then sets bit 7 of `0x0166` and bit 3 for a command |
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

  private struct PendingAnswer {

    let id: Int

    let command: IBIOSCommand

    let result: AsyncStream<Result<Bool, any Error>>.Continuation

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
  /// ``PowerLincController/replies()`` finishes. Calling it again, or while it's running,
  /// returns at once.
  ///
  /// - Throws: The connection's error, if reading from it failed.
  public func run() async throws {

    guard !isRunning, !isClosed else {

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

    let steps = try Self.ibiosCommands(for: command)

    try await waitForTurn()
    defer { turns.release() }

    for step in steps {

      try await perform(step)

    }

  }

  /// Sends an IBIOS command and waits for the controller to accept it.
  ///
  /// Commands are sent one at a time, in the order they're called, and a command the
  /// controller rejects is sent again after the retry policy's delay. Canceling a send stops
  /// it, as with ``Modem/send(_:)``.
  ///
  /// - Parameter command: The command to send.
  /// - Throws: ``PowerLincControllerError/rejected(_:)`` if the controller NAKs every attempt,
  ///   ``PowerLincControllerError/timedOut(_:)`` if it doesn't answer,
  ///   ``PowerLincControllerError/connectionClosed`` if the controller is closed,
  ///   `CancellationError` if the task is canceled, or the connection's error.
  public func send(_ command: IBIOSCommand) async throws {

    try await waitForTurn()
    defer { turns.release() }

    try await perform(command)

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

  private static func ibiosCommands(for command: SerialCommand) throws(PowerLincControllerError) -> [IBIOSCommand] {

    switch command {
    case let .sendStandardMessage(message):
      return [
        .download(address: Memory.messageDestination, data: message.bytes),
        .mask(address: Memory.insteonControl, or: Memory.insteonRequestToSend, and: 0xFF)
      ]
    case let .sendX10(code):
      let isCommand = if case .command = code { true } else { false }

      return [
        .download(address: Memory.x10Transmit, data: [code.rawX10]),
        .mask(
          address: Memory.x10Flags,
          or: Memory.x10RequestToSend | (isCommand ? Memory.x10IsCommand : 0),
          and: isCommand ? 0xFF : ~Memory.x10IsCommand
        )
      ]
    case .getModemInfo:
      return [.getVersion]
    default:
      throw .unsupported(command)
    }

  }

  // MARK: - Sending

  private func perform(_ command: IBIOSCommand) async throws {

    for attempt in 1...retryPolicy.attempts {

      try Task.checkCancellation()

      if try await transmit(command) {

        return

      }

      if attempt < retryPolicy.attempts {

        try await clock.sleep(for: retryPolicy.delay)

      }

    }

    throw PowerLincControllerError.rejected(command)

  }

  /// Writes a command and waits for its answer, a NAK, the timeout or cancellation.
  ///
  /// - Returns: Whether the controller accepted the command.
  private func transmit(_ command: IBIOSCommand) async throws -> Bool {

    guard !isClosed else {

      throw PowerLincControllerError.connectionClosed

    }

    let id = makeID()
    let timeout = retryPolicy.echoTimeout
    let (results, continuation) = AsyncStream<Result<Bool, any Error>>.makeStream()

    pendingAnswer = PendingAnswer(id: id, command: command, result: continuation)
    defer { abandonAnswer(id) }

    let result = await withTaskGroup(of: Void.self, returning: Result<Bool, any Error>.self) { group in

      // Writes the command, then gives up on its answer once the timeout passes. The group
      // cancels this child as soon as the answer arrives.
      group.addTask { [connection, clock] in

        do {

          try await connection.write(command.bytes)

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

    return try result.get()

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

  private func abandonAnswer(_ id: Int) {

    guard let pending = pendingAnswer, pending.id == id else {

      return

    }

    pendingAnswer = nil
    pending.result.finish()

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

      if let pending = pendingAnswer, let isAccepted = Self.answer(reply, to: pending.command) {

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

  /// Whether a reply answers a command: `true` if it accepts it, `false` if it rejects it, or
  /// `nil` if it's about something else.
  private static func answer(_ reply: IBIOSReply, to command: IBIOSCommand) -> Bool? {

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
    case let (.memory(address, data, _), .upload(expectedAddress, length)):
      return address == expectedAddress && data.count == Int(length) ? true : nil
    case let (.checksum(address, length, _), .getChecksum(expectedAddress, expectedLength)):
      return address == expectedAddress && length == expectedLength ? true : nil
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
