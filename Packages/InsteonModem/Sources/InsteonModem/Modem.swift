import InsteonProtocol

/// Talks to an INSTEON modem, such as a PowerLinc Modem, over a ``ModemConnection``.
///
/// ``Modem/send(_:)`` sends one command at a time and waits for the modem's echo, retrying
/// when the modem answers with a NAK because it's busy. Modems expect this pacing: a command
/// sent before the previous one is answered may be lost. Everything the modem sends, including
/// messages from devices, is published to every stream returned by ``Modem/replies()``.
///
/// ``Modem/withConnection(_:retryPolicy:clock:isolation:_:)`` reads what the modem sends while
/// your code uses it, and closes the modem when your code is done:
///
/// ```swift
/// try await Modem.withConnection(SerialPort(path: "/dev/ttyUSB0")) { modem in
///   let replies = await modem.replies()
///   try await modem.send(.getModemInfo)
///
///   for await reply in replies {
///     if case let .modemInfo(info) = reply {
///       print("Modem address:", info.address)
///       break
///     }
///   }
/// }
/// ```
///
/// To keep a modem open for the life of an app instead, create one and call ``Modem/run()``
/// in a task that lasts as long as the app.
public actor Modem: SerialCommandSender {

  private let pacer: CommandPacer<ModemReplyParser>

  /// Creates a modem that talks over a connection.
  ///
  /// - Parameters:
  ///   - connection: The connection to the modem.
  ///   - retryPolicy: How to wait for and retry commands. Defaults to ``RetryPolicy/init(attempts:delay:answerTimeout:)``.
  ///   - clock: The clock that times retry delays and echo timeouts. Defaults to a
  ///     `ContinuousClock`; tests can pass a clock they control.
  public init(
    connection: any ModemConnection,
    retryPolicy: RetryPolicy = RetryPolicy(),
    clock: any Clock<Duration> = ContinuousClock()
  ) {

    pacer = CommandPacer(
      connection: connection,
      parser: ModemReplyParser(),
      retryPolicy: retryPolicy,
      clock: clock,
      closedError: ModemError.connectionClosed
    )

  }

  /// Opens a modem on a connection, runs `body` with it while reading what it sends, then
  /// closes it.
  ///
  /// The modem is closed when `body` returns or throws, so don't keep it beyond `body`.
  ///
  /// - Parameters:
  ///   - connection: The connection to the modem.
  ///   - retryPolicy: How to wait for and retry commands. Defaults to ``RetryPolicy/init(attempts:delay:answerTimeout:)``.
  ///   - clock: The clock that times retry delays and echo timeouts. Defaults to a
  ///     `ContinuousClock`; tests can pass a clock they control.
  ///   - isolation: The actor `body` runs on. Defaults to the caller's.
  ///   - body: The work to do with the modem.
  /// - Returns: What `body` returns.
  /// - Throws: The error `body` throws, or the connection's error if reading from it failed.
  public static func withConnection<Value>(
    _ connection: any ModemConnection,
    retryPolicy: RetryPolicy = RetryPolicy(),
    clock: any Clock<Duration> = ContinuousClock(),
    isolation: isolated (any Actor)? = #isolation,
    _ body: (Modem) async throws -> Value
  ) async throws -> Value {

    let modem = Modem(connection: connection, retryPolicy: retryPolicy, clock: clock)

    return try await withRunning({ try await modem.run() }) { try await body(modem) }

  }

  /// Reads everything the modem sends, until the connection closes or the task is canceled.
  ///
  /// ``Modem/withConnection(_:retryPolicy:clock:isolation:_:)`` calls this for you. Call it
  /// yourself to keep a modem open for as long as a task runs, alongside the code that sends
  /// commands.
  ///
  /// Echoes and replies arrive only while this runs. When it returns, the modem is closed:
  /// waiting sends fail with ``ModemError/connectionClosed``, and every stream from
  /// ``Modem/replies()`` finishes. Calling it while it's running returns at once.
  ///
  /// - Throws: The connection's error, if reading from it failed, or
  ///   ``ModemError/connectionClosed`` if the modem has already closed.
  public func run() async throws {

    try await pacer.run()

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

    try await pacer.send([Self.exchange(for: command)])

  }

  /// How long a request waits for a device's acknowledgement by default: 3 seconds.
  public static let defaultRequestTimeout: Duration = .seconds(3)

  /// Sends a standard direct message to a device and waits for the device to acknowledge it.
  ///
  /// Devices acknowledge only direct messages, so a broadcast sent this way times out. The
  /// request takes the modem's turn until the device answers, so no other command is sent
  /// while the message is crossing the network. The modem echoes the message first, and the
  /// message is sent again as the retry policy allows if the modem is busy. Then the first
  /// acknowledgement from the device answers the request. An i2cs device that's still
  /// searching its ALL-Link database answers with ``NAKReason/databaseSearchPending`` first,
  /// and then again once its search finishes, so the request keeps waiting.
  ///
  /// ```swift
  /// let device = InsteonAddress(0x1A, 0x2B, 0x3C)
  /// let acknowledgement = try await modem.request(
  ///   StandardMessage(to: device, command: StandardDirectCommand.getEngineVersion)
  /// )
  /// let engine = InsteonEngine(rawValue: acknowledgement.command.command2)
  /// ```
  ///
  /// - Parameters:
  ///   - message: The message to send.
  ///   - timeout: How long to wait for the modem's echo and the device's acknowledgement
  ///     together. Defaults to ``Modem/defaultRequestTimeout``.
  /// - Returns: The device's acknowledgement.
  /// - Throws: ``ModemError/deviceRejected(_:_:)`` if the device rejects the message,
  ///   ``ModemError/deviceTimedOut(_:)`` if it doesn't answer, ``ModemError/rejected(_:)`` if
  ///   the modem NAKs every attempt, ``ModemError/connectionClosed`` if the modem is closed,
  ///   `CancellationError` if the task is canceled, or the connection's error.
  @discardableResult
  public func request(
    _ message: StandardMessage,
    timeout: Duration = Modem.defaultRequestTimeout
  ) async throws -> ReceivedMessage {

    try await request(.sendStandardMessage(message), to: message.destination, timeout: timeout)

  }

  /// Sends an extended direct message to a device and waits for the device to acknowledge it.
  ///
  /// The device acknowledges an extended message with a standard one. Data it sends in reply,
  /// such as the extended reply to ``ExtendedDirectCommand/getSet(variant:)``, follows through
  /// ``Modem/replies()``. Otherwise this works like the request for a standard message.
  ///
  /// - Parameters:
  ///   - message: The message to send.
  ///   - timeout: How long to wait for the modem's echo and the device's acknowledgement
  ///     together. Defaults to ``Modem/defaultRequestTimeout``.
  /// - Returns: The device's acknowledgement.
  /// - Throws: ``ModemError/deviceRejected(_:_:)`` if the device rejects the message,
  ///   ``ModemError/deviceTimedOut(_:)`` if it doesn't answer, ``ModemError/rejected(_:)`` if
  ///   the modem NAKs every attempt, ``ModemError/connectionClosed`` if the modem is closed,
  ///   `CancellationError` if the task is canceled, or the connection's error.
  @discardableResult
  public func request(
    _ message: ExtendedMessage,
    timeout: Duration = Modem.defaultRequestTimeout
  ) async throws -> ReceivedMessage {

    try await request(.sendExtendedMessage(message), to: message.destination, timeout: timeout)

  }

  /// Returns a stream of everything the modem sends after this call.
  ///
  /// Each call returns a new stream, so several parts of an app can listen at once. A stream
  /// finishes when the modem closes.
  ///
  /// - Returns: The modem's replies, in the order they arrive.
  public func replies() async -> AsyncStream<ModemReply> {

    await pacer.replies()

  }

  private func request(_ command: SerialCommand, to device: InsteonAddress, timeout: Duration) async throws -> ReceivedMessage {

    let exchange = Exchange(
      bytes: command.bytes,
      steps: Self.exchange(for: command).steps + [Self.acknowledgement(from: device)],
      timedOut: ModemError.deviceTimedOut(device),
      timeout: timeout
    )

    // The last step only accepts a message received from the device.
    guard case let .messageReceived(acknowledgement) = try await pacer.send([exchange])[0] else {

      preconditionFailure("A request is answered only by a message from its device.")

    }

    return acknowledgement

  }

  /// The step that waits for a device to acknowledge a direct message.
  private static func acknowledgement(from device: InsteonAddress) -> @Sendable (ModemReply) -> Verdict? {

    { reply in

      guard case let .messageReceived(message) = reply, message.sender == device else {

        return nil

      }

      switch message.flags.messageType {
      case .directAcknowledgement:
        return .accepted
      case .directNegativeAcknowledgement:
        let reason = NAKReason(rawValue: message.command.command2)

        // The device answers again once its database search finishes.
        return reason == .databaseSearchPending ? nil : .failed(ModemError.deviceRejected(device, reason))
      default:
        return nil
      }

    }

  }

  private static func exchange(for command: SerialCommand) -> Exchange<ModemReply> {

    let number = command.number
    let parameters = command.parameters

    return Exchange(
      bytes: command.bytes,
      answer: { reply in

        switch reply {
        // Matching the parameters keeps a late echo of an earlier command from answering this one.
        case let .echo(echo) where echo.number == number && echo.parameters == parameters:
          return echo.isAccepted
        // These commands are answered with their data in place of a plain echo.
        case .modemInfo where number == .getModemInfo,
             .modemConfiguration where number == .getModemConfiguration:
          return true
        case .negativeAcknowledgement:
          return false
        default:
          return nil
        }

      },
      rejected: ModemError.rejected(number),
      timedOut: ModemError.timedOut(number)
    )

  }

}
