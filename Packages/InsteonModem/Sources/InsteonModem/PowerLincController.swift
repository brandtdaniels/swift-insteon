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
/// the SALad program the controller ships with. Use it the way you use ``Modem``:
///
/// ```swift
/// let port = try SerialPort(path: "/dev/ttyUSB0", baudRate: .baud4800)
///
/// try await PowerLincController.withConnection(port) { controller in
///   let lamp = InsteonAddress(0xAA, 0xBB, 0xCC)
///   try await controller.send(.sendStandardMessage(
///     StandardMessage(to: lamp, command: StandardDirectCommand.on(level: 0xFF))
///   ))
/// }
/// ```
public final class PowerLincController: SerialCommandSender {

  private let pacer: CommandPacer<IBIOSReplyParser>

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

    pacer = CommandPacer(
      connection: connection,
      parser: IBIOSReplyParser(),
      retryPolicy: retryPolicy,
      clock: clock,
      closedError: PowerLincControllerError.connectionClosed
    )

  }

  /// Opens a controller on a connection, runs `body` with it while reading what it sends,
  /// then closes it.
  ///
  /// The controller is closed when `body` returns or throws, so don't keep it beyond `body`.
  ///
  /// - Parameters:
  ///   - connection: The connection to the controller, such as a ``SerialPort`` opened at
  ///     ``SerialPort/BaudRate/baud4800``.
  ///   - retryPolicy: How to wait for and retry commands. Defaults to ``Modem/RetryPolicy/init(attempts:delay:echoTimeout:)``.
  ///   - clock: The clock that times retry delays and timeouts. Defaults to a
  ///     `ContinuousClock`; tests can pass a clock they control.
  ///   - isolation: The actor `body` runs on. Defaults to the caller's.
  ///   - body: The work to do with the controller.
  /// - Returns: What `body` returns.
  /// - Throws: The error `body` throws, or the connection's error if reading from it failed.
  public static func withConnection<Value>(
    _ connection: any ModemConnection,
    retryPolicy: Modem.RetryPolicy = Modem.RetryPolicy(),
    clock: any Clock<Duration> = ContinuousClock(),
    isolation: isolated (any Actor)? = #isolation,
    _ body: (PowerLincController) async throws -> Value
  ) async throws -> Value {

    let controller = PowerLincController(connection: connection, retryPolicy: retryPolicy, clock: clock)

    return try await withRunning({ try await controller.run() }) { try await body(controller) }

  }

  /// Reads everything the controller sends, until the connection closes or the task is
  /// canceled.
  ///
  /// ``PowerLincController/withConnection(_:retryPolicy:clock:isolation:_:)`` calls this for
  /// you. Call it yourself to keep a controller open for as long as a task runs, alongside the
  /// code that sends commands.
  ///
  /// Answers and reports arrive only while this runs. When it returns, the controller is
  /// closed: waiting sends fail with ``PowerLincControllerError/connectionClosed``, and every
  /// stream from ``PowerLincController/replies()`` finishes. Calling it while it's running
  /// returns at once.
  ///
  /// - Throws: The connection's error, if reading from it failed, or
  ///   ``PowerLincControllerError/connectionClosed`` if the controller has already closed.
  public func run() async throws {

    try await pacer.run()

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

    try await pacer.send(Self.ibiosCommands(for: command).map(Self.exchange(for:)))

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

    try await pacer.send([Self.exchange(for: command)])

  }

  /// Returns a stream of everything the controller sends from now on.
  ///
  /// Each call returns a new stream, so several parts of an app can listen at once. A stream
  /// finishes when the controller closes.
  ///
  /// - Returns: The controller's replies, in the order they arrive.
  public func replies() async -> AsyncStream<IBIOSReply> {

    await pacer.replies()

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

  // MARK: - Answers

  private static func exchange(for command: IBIOSCommand) -> Exchange<IBIOSReply> {

    Exchange(
      bytes: command.bytes,
      answer: { reply in Self.answer(reply, to: command) },
      rejected: PowerLincControllerError.rejected(command),
      timedOut: PowerLincControllerError.timedOut(command)
    )

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

}
