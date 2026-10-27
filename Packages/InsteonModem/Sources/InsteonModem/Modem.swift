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
public final class Modem: SerialCommandSender {

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

  private let pacer: CommandPacer<ModemReplyParser>

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
  ///   - retryPolicy: How to wait for and retry commands. Defaults to ``Modem/RetryPolicy/init(attempts:delay:echoTimeout:)``.
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

  /// Returns a stream of everything the modem sends from now on.
  ///
  /// Each call returns a new stream, so several parts of an app can listen at once. A stream
  /// finishes when the modem closes.
  ///
  /// - Returns: The modem's replies, in the order they arrive.
  public func replies() async -> AsyncStream<ModemReply> {

    await pacer.replies()

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
