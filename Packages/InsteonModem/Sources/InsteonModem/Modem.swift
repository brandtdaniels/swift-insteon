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

    let continuation: CheckedContinuation<CommandEcho, any Error>

  }

  private let connection: any ModemConnection

  private let retryPolicy: RetryPolicy

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
  public init(connection: any ModemConnection, retryPolicy: RetryPolicy = RetryPolicy()) {

    self.connection = connection
    self.retryPolicy = retryPolicy

  }

  /// Sends a command and waits for the modem to accept it.
  ///
  /// Commands are sent one at a time, in the order they're called. Any data the command
  /// requests, such as an ALL-Link record, arrives afterwards through ``Modem/replies()``.
  ///
  /// - Parameter command: The command to send.
  /// - Throws: ``ModemError/rejected(_:)`` if the modem NAKs every attempt,
  ///   ``ModemError/timedOut(_:)`` if it doesn't echo the command,
  ///   ``ModemError/connectionClosed`` if the connection closes, or the connection's error.
  public func send(_ command: SerialCommand) async throws {

    startReading()

    await waitForTurn()
    defer { finishTurn() }

    for attempt in 1...retryPolicy.attempts {

      if try await transmit(command).isAccepted {

        return

      }

      if attempt < retryPolicy.attempts {

        try await Task.sleep(for: retryPolicy.delay)

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
    let timeout = retryPolicy.echoTimeout

    return try await withCheckedThrowingContinuation { continuation in

      pendingEcho = PendingEcho(id: id, number: command.number, continuation: continuation)

      Task { [connection] in

        do {

          try await connection.write(command.bytes)

        } catch {

          self.failEcho(id, with: error)

          return

        }

        try? await Task.sleep(for: timeout)

        self.failEcho(id, with: ModemError.timedOut(command.number))

      }

    }

  }

  private func failEcho(_ id: Int, with error: any Error) {

    guard let pending = pendingEcho, pending.id == id else {

      return

    }

    pendingEcho = nil
    pending.continuation.resume(throwing: error)

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

    for reply in parser.parse(chunk) {

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
    case let .echo(echo) where echo.number == pending.number:
      pendingEcho = nil
      pending.continuation.resume(returning: echo)
    case .negativeAcknowledgement:
      pendingEcho = nil
      pending.continuation.resume(returning: CommandEcho(number: pending.number, parameters: [], isAccepted: false))
    default:
      break
    }

  }

  private func close(with error: (any Error)?) {

    isClosed = true

    if let pending = pendingEcho {

      pendingEcho = nil
      pending.continuation.resume(throwing: error ?? ModemError.connectionClosed)

    }

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
