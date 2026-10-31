import InsteonProtocol

/// Talks to an Insteon modem, such as a PowerLinc Modem, over a ``ModemConnection``.
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

  private let retryPolicy: RetryPolicy

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

    self.retryPolicy = retryPolicy
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
  /// the time it was given to answer, before writing. For `SerialCommand.resetModem` that's
  /// 20 seconds longer than the retry policy's answer timeout.
  ///
  /// - Parameter command: The command to send.
  /// - Throws: ``ModemError/rejected(_:)`` if the modem NAKs every attempt, or NAKs the
  ///   command and then doesn't echo it when it's sent again; ``ModemError/timedOut(_:)`` if
  ///   it doesn't echo the command at all; ``ModemError/connectionClosed`` if the modem is
  ///   closed; `CancellationError` if the task is canceled; or the connection's error.
  public func send(_ command: SerialCommand) async throws {

    try await pacer.send([Self.exchange(for: command)])

  }

  /// Writes bytes to the modem as they are, for exploring commands the package doesn't model.
  ///
  /// The bytes wait for their turn like any command and hold it until the modem echoes a
  /// command with the same number, answers with a NAK (`0x15`), or the retry policy's answer
  /// timeout passes, so no other command is written while the modem may still be busy with
  /// them. They're written once, never again, and nothing checks them; a timeout isn't an
  /// error. Listen with ``Modem/replies()`` before writing to read the modem's echo and
  /// anything that follows it. The modem's replies are read as `ModemReply` values, so a
  /// reply to a command number the package doesn't know isn't reported, and the turn is held
  /// for the whole timeout. Prefer ``Modem/send(_:)`` for anything a `SerialCommand`
  /// describes.
  ///
  /// The echo is read by ``Modem/run()``, so a write made while it isn't running holds the
  /// turn for the whole timeout.
  ///
  /// ```swift
  /// let replies = await modem.replies()
  /// try await modem.write(rawCommand: [0x02, 0x77, 0x01])
  /// ```
  ///
  /// - Parameter bytes: The bytes to write, starting with `0x02`.
  /// - Throws: ``ModemError/connectionClosed`` if the modem is closed, `CancellationError` if
  ///   the task is canceled, or the connection's error.
  public func write(rawCommand bytes: [UInt8]) async throws {

    let number: UInt8? = bytes.count >= 2 ? bytes[1] : nil

    let step = AnswerStep<ModemReply>(
      verdict: { (reply: ModemReply) -> Verdict? in

        Self.endsRawCommand(reply, number: number) ? .accepted : nil

      },
      timedOut: RawCommandUnanswered()
    )

    do {

      try await pacer.sendOnce(Exchange(bytes: bytes, steps: [step]))

    } catch is RawCommandUnanswered {

      // The modem didn't answer in time, which a raw command may not; what it did send is in
      // the caller's replies.

    }

  }

  /// Whether a reply ends the wait for a raw command with a command number.
  private static func endsRawCommand(_ reply: ModemReply, number: UInt8?) -> Bool {

    switch reply {
    case let .echo(echo):
      return echo.number.rawValue == number
    case .negativeAcknowledgment:
      return true
    case .modemInfo:
      return number == SerialCommandNumber.getModemInfo.rawValue
    case .modemConfiguration:
      return number == SerialCommandNumber.getModemConfiguration.rawValue
    case .radioStatus:
      return number == SerialCommandNumber.readRadioStatus.rawValue
    default:
      return false
    }

  }

  /// Asks the modem about itself with Get IM Info (`0x60`).
  ///
  /// - Returns: The modem's address, device category, subcategory and firmware version. Every
  ///   Insteon modem reports category `DeviceCategory.networkBridges`, and the subcategory
  ///   names the model; see <doc:SupportedModems>.
  /// - Throws: The errors of ``Modem/send(_:)``.
  public func modemInfo() async throws -> ModemInfo {

    guard case let .modemInfo(info) = try await pacer.send([Self.exchange(for: .getModemInfo)])[0] else {

      preconditionFailure("Get IM Info is answered only by the modem's information.")

    }

    return info

  }

  /// Asks the modem about its radio with Read RF Frequency (`0x7E`), which only later modem
  /// firmware answers.
  ///
  /// - Returns: The radio's frequency code and flags, and whether it's on.
  /// - Throws: ``ModemError/rejected(_:)`` from a modem without the command, or the errors of
  ///   ``Modem/send(_:)``.
  public func radioStatus() async throws -> ModemRadioStatus {

    guard case let .radioStatus(status) = try await pacer.send([Self.exchange(for: .readRadioStatus)])[0] else {

      preconditionFailure("Read RF Frequency is answered only by the radio's status.")

    }

    return status

  }

  /// Reads the modem's configuration with Get IM Configuration (`0x73`).
  ///
  /// - Returns: The modem's configuration flags, and the two bytes that follow them.
  /// - Throws: The errors of ``Modem/send(_:)``.
  public func configuration() async throws -> ModemConfigurationReport {

    guard case let .modemConfiguration(report) = try await pacer.send([Self.exchange(for: .getModemConfiguration)])[0] else {

      preconditionFailure("Get IM Configuration is answered only by the modem's configuration.")

    }

    return report

  }

  /// Changes some of the modem's configuration flags and keeps the rest.
  ///
  /// Set IM Configuration (`0x6B`) replaces every flag at once, so this reads the flags with Get IM
  /// Configuration (`0x73`), applies `change` and writes the result, all in one turn so that no
  /// other command comes between. It doesn't write when `change` leaves the flags as they were.
  ///
  /// ```swift
  /// // Report messages from linked devices to other devices, and keep every other flag.
  /// try await modem.updateConfiguration { $0.insert(.monitorMode) }
  /// ```
  ///
  /// - Parameter change: Changes the flags the modem reported.
  /// - Returns: The flags as the modem reported them, or as it accepted them if they changed.
  /// - Throws: The errors of ``Modem/send(_:)``.
  @discardableResult
  public func updateConfiguration(
    _ change: @Sendable (inout ModemConfiguration) -> Void
  ) async throws -> ModemConfiguration {

    try await pacer.withTurn { turn in

      guard case let .modemConfiguration(report) = try await turn.send(Self.exchange(for: .getModemConfiguration)) else {

        preconditionFailure("Get IM Configuration is answered only by the modem's configuration.")

      }

      var configuration = report.configuration
      change(&configuration)

      if configuration != report.configuration {

        _ = try await turn.send(Self.exchange(for: .setModemConfiguration(configuration)))

      }

      return configuration

    }

  }

  /// How long ``Modem/sendAllLinkCommand(group:command:timeout:)`` waits for the cleanups by
  /// default: 10 seconds.
  ///
  /// The Insteon Developer's Guide gives the worst case as 2.150 seconds from the broadcast to the
  /// first member's cleanup report and 1.550 seconds to each one after, so 10 seconds covers a
  /// group of up to six members that all need every retry. Pass more for a larger group.
  public static let defaultAllLinkCommandTimeout: Duration = .seconds(10)

  /// Sends a command to one of the modem's ALL-Link groups and waits for the modem to finish
  /// its cleanups.
  ///
  /// The modem broadcasts the command to the group, then sends each member a cleanup message, as
  /// Send ALL-Link Command (`0x61`) describes. The modem's turn is held until the modem's ALL-Link
  /// Cleanup Status Report (`0x58`), since the Insteon Developer's Guide says any message sent
  /// before then cancels the rest of the cleanups. Meanwhile each member's cleanup acknowledgment,
  /// cleanup NAK or ALL-Link Cleanup Failure Report (`0x56`) is collected.
  ///
  /// ```swift
  /// let report = try await modem.sendAllLinkCommand(group: 0x01, command: StandardDirectCommand.on(level: 0xFF).command)
  /// print(report.unacknowledged)   // Members to retry with a direct message.
  /// ```
  ///
  /// To send a command without waiting for its cleanups, send `SerialCommand.sendAllLinkCommand`
  /// with ``Modem/send(_:)``.
  ///
  /// - Parameters:
  ///   - group: The modem's ALL-Link group to send the command to.
  ///   - command: The command to broadcast. Its cmd2 goes in the broadcast; the cleanups carry the
  ///     group number instead. The Insteon Developer's Guide says not to send Light Start Manual
  ///     Change (cmd1 `0x17`) this way, so it isn't allowed.
  ///   - timeout: How long to wait for the modem's echo and every cleanup together. Defaults to
  ///     ``Modem/defaultAllLinkCommandTimeout``.
  /// - Returns: Which members acknowledged their cleanup, which didn't, and whether the modem
  ///   reached them all.
  /// - Throws: ``ModemError/rejected(_:)`` if the modem NAKs every attempt, as it does for a
  ///   group it has no records for, ``ModemError/timedOut(_:)`` if the cleanups don't finish
  ///   in time, ``ModemError/connectionClosed`` if the modem is closed, `CancellationError` if
  ///   the task is canceled, or the connection's error.
  public func sendAllLinkCommand(
    group: AllLinkGroupNumber,
    command: Command,
    timeout: Duration = Modem.defaultAllLinkCommandTimeout
  ) async throws -> AllLinkCleanupReport {

    precondition(command.command1 != 0x17, "Send Light Start Manual Change as a direct message, not to a group.")

    let serialCommand = SerialCommand.sendAllLinkCommand(group: group, command: command)
    let echo = Self.exchange(for: serialCommand).steps
    let status = AnswerStep<ModemReply>(
      verdict: { reply in

        if case .allLinkCleanupStatus = reply {

          return .accepted

        }

        return nil

      },
      timedOut: ModemError.timedOut(.sendAllLinkCommand)
    )
    let exchange = Exchange(bytes: serialCommand.bytes, steps: echo + [status], timeout: timeout)

    return try await pacer.withTurn { turn in

      // Listening starts within the turn, after any earlier command has been answered, so
      // only this command's cleanups are heard.
      let replies = await turn.replies()

      _ = try await turn.send(exchange)

      return try await Self.cleanupReport(in: replies, for: serialCommand, group: group, command1: command.command1)

    }

  }

  /// Reads a group command's cleanups from the replies that followed it, up to the modem's
  /// status report.
  private static func cleanupReport(
    in replies: AsyncStream<ModemReply>,
    for serialCommand: SerialCommand,
    group: AllLinkGroupNumber,
    command1: UInt8
  ) async throws -> AllLinkCleanupReport {

    // What came before the command's accepted echo belongs to something else.
    var hasStarted = false
    var acknowledged: [InsteonAddress] = []
    var unacknowledged: [InsteonAddress] = []

    for await reply in replies {

      switch reply {
      case let .echo(echo) where isAcceptedEcho(echo, of: serialCommand):
        hasStarted = true
      // A cleanup acknowledgment repeats the command, with the group in cmd2.
      case let .messageReceived(message)
        where hasStarted && message.command == Command(command1: command1, command2: group.rawValue)
          && message.flags.messageType == .allLinkCleanupAcknowledgment:
        acknowledged.append(message.sender)
      // A cleanup NAK carries its reason in cmd2. A device still searching its database
      // answers again once it's done, so that one isn't a failure.
      case let .messageReceived(message)
        where hasStarted && message.command.command1 == command1
          && message.flags.messageType == .allLinkCleanupNegativeAcknowledgment
          && message.nakReason != .databaseSearchPending:
        unacknowledged.append(message.sender)
      case let .allLinkCleanupFailed(failedGroup, address) where hasStarted && failedGroup == group:
        unacknowledged.append(address)
      case let .allLinkCleanupStatus(isComplete) where hasStarted:
        let answered = Set(acknowledged)

        return AllLinkCleanupReport(
          acknowledged: unique(acknowledged),
          unacknowledged: unique(unacknowledged.filter { !answered.contains($0) }),
          isComplete: isComplete
        )
      default:
        break
      }

    }

    throw ModemError.connectionClosed

  }

  /// The addresses in order, each once.
  private static func unique(_ addresses: [InsteonAddress]) -> [InsteonAddress] {

    var seen: Set<InsteonAddress> = []

    return addresses.filter { seen.insert($0).inserted }

  }

  /// Whether an echo accepts a command: it repeats the command's number and parameters, so a
  /// late echo of an earlier command doesn't count, and ends with an ACK.
  private static func isAcceptedEcho(_ echo: CommandEcho, of command: SerialCommand) -> Bool {

    echo.number == command.number && echo.parameters == command.parameters && echo.isAccepted

  }

  /// How long a request for a standard message waits for the device's answer by default:
  /// 3 seconds.
  ///
  /// The Insteon Developer's Guide gives 2.00 seconds for the Insteon engine to retry a standard
  /// message five times from Max Hops 3, the most it retries. The extra second covers the
  /// modem's echo.
  public static let defaultRequestTimeout: Duration = .seconds(3)

  /// How long a request for an extended message waits for the device's answer by default:
  /// 4.17 seconds.
  ///
  /// The Insteon Developer's Guide gives 3.17 seconds for the Insteon engine to retry an extended
  /// message five times from Max Hops 3. The extra second covers the modem's echo, as in
  /// ``Modem/defaultRequestTimeout``.
  public static let defaultExtendedRequestTimeout: Duration = .milliseconds(4_170)

  /// Sends a standard direct message to a device and waits for the device to acknowledge it.
  ///
  /// Devices acknowledge only direct messages, so `message` must be one. The request takes the modem's turn until the device answers, so no other command is sent
  /// while the message is crossing the network. The modem echoes the message first, and the
  /// message is sent again as the retry policy allows if the modem is busy. Then the first
  /// acknowledgment from the device that repeats the message's cmd1 answers the request; a
  /// status request is answered by the device's first acknowledgment, since it carries other
  /// data in cmd1. With the modem's monitor mode on, an acknowledgment the device sends
  /// another controller for the same cmd1 can answer it too. An i2CS device that's still
  /// searching its ALL-Link database answers with `NAKReason.databaseSearchPending` first,
  /// and then again once its search finishes, so the request keeps waiting.
  ///
  /// ```swift
  /// let device = InsteonAddress(0x1A, 0x2B, 0x3C)
  /// let acknowledgment = try await modem.request(
  ///   StandardMessage(to: device, command: StandardDirectCommand.getEngineVersion)
  /// )
  /// let engine = InsteonEngine(rawValue: acknowledgment.command.command2)
  /// ```
  ///
  /// - Parameters:
  ///   - message: The message to send.
  ///   - timeout: How long to wait for the modem's echo and the device's acknowledgment
  ///     together. Defaults to ``Modem/defaultRequestTimeout``.
  /// - Returns: The device's acknowledgment.
  /// - Throws: ``ModemError/deviceRejected(_:_:)`` if the device rejects the message,
  ///   ``ModemError/deviceTimedOut(_:)`` if it doesn't answer, ``ModemError/rejected(_:)`` if
  ///   the modem NAKs every attempt, ``ModemStoppedEchoing`` if the modem doesn't echo the
  ///   message after it has sent anything else, ``ModemError/timedOut(_:)`` if it doesn't echo
  ///   the message and hasn't sent anything, ``ModemError/connectionClosed`` if the modem is
  ///   closed, `CancellationError` if the task is canceled, or the connection's error.
  @discardableResult
  public func request(
    _ message: StandardMessage,
    timeout: Duration = Modem.defaultRequestTimeout
  ) async throws -> ReceivedMessage {

    precondition(message.flags.messageType == .direct, "Devices acknowledge only direct messages.")

    return try await request(
      .sendStandardMessage(message),
      to: message.destination,
      command1: message.command.command1,
      timeout: timeout
    )

  }

  /// Sends an extended direct message to a device and waits for the device to acknowledge it.
  ///
  /// The device acknowledges an extended message with a standard one. Data it sends in reply,
  /// such as the extended reply to `ExtendedDirectCommand.getSet(variant:)`, follows through
  /// ``Modem/replies()``. Otherwise this works like the request for a standard message.
  ///
  /// - Parameters:
  ///   - message: The message to send.
  ///   - timeout: How long to wait for the modem's echo and the device's acknowledgment
  ///     together. Defaults to ``Modem/defaultExtendedRequestTimeout``.
  /// - Returns: The device's acknowledgment.
  /// - Throws: ``ModemError/deviceRejected(_:_:)`` if the device rejects the message,
  ///   ``ModemError/deviceTimedOut(_:)`` if it doesn't answer, ``ModemError/rejected(_:)`` if
  ///   the modem NAKs every attempt, ``ModemStoppedEchoing`` if the modem doesn't echo the
  ///   message after it has sent anything else, ``ModemError/timedOut(_:)`` if it doesn't echo
  ///   the message and hasn't sent anything, ``ModemError/connectionClosed`` if the modem is
  ///   closed, `CancellationError` if the task is canceled, or the connection's error.
  @discardableResult
  public func request(
    _ message: ExtendedMessage,
    timeout: Duration = Modem.defaultExtendedRequestTimeout
  ) async throws -> ReceivedMessage {

    precondition(message.flags.messageType == .direct, "Devices acknowledge only direct messages.")

    return try await request(
      .sendExtendedMessage(message),
      to: message.destination,
      command1: message.command.command1,
      timeout: timeout
    )

  }

  /// Sends an extended direct message to a device and waits for the reply the device sends
  /// after acknowledging it.
  ///
  /// Some commands are answered in two parts: the device acknowledges the message, then sends
  /// the data it asked for in a message of its own, such as an ALL-Link Record Response. The
  /// request holds the modem's turn until that reply arrives. Otherwise this works like the
  /// request that returns the acknowledgment.
  ///
  /// ```swift
  /// let response = try await modem.request(
  ///   AllLinkDatabaseRequest.read(address: 0x0000).message(to: device),
  ///   awaitingReply: AllLinkRecordResponse.init
  /// )
  /// ```
  ///
  /// - Parameters:
  ///   - message: The message to send.
  ///   - reply: Reads the reply from a message, or returns `nil` if the message isn't it. It
  ///     sees only messages from the device that arrive after its acknowledgment.
  ///   - timeout: How long to wait for the modem's echo, the device's acknowledgment and its
  ///     reply together. Defaults to ``Modem/defaultExtendedRequestTimeout``, which covers the
  ///     guide's retries of the message but not also those of the reply, so a reply that needs
  ///     every retry can arrive late.
  /// - Returns: The device's reply.
  /// - Throws: ``ModemError/deviceRejected(_:_:)`` if the device rejects the message,
  ///   ``ModemError/deviceTimedOut(_:)`` if it doesn't acknowledge it or doesn't reply,
  ///   ``ModemError/rejected(_:)`` if the modem NAKs every attempt, ``ModemStoppedEchoing`` if
  ///   the modem doesn't echo the message after it has sent anything else,
  ///   ``ModemError/timedOut(_:)`` if it doesn't echo the message and hasn't sent anything,
  ///   ``ModemError/connectionClosed`` if the modem is closed, `CancellationError` if the task
  ///   is canceled, or the connection's error.
  public func request<Reply: Sendable>(
    _ message: ExtendedMessage,
    awaitingReply reply: @escaping @Sendable (ReceivedMessage) -> Reply?,
    timeout: Duration = Modem.defaultExtendedRequestTimeout
  ) async throws -> Reply {

    precondition(message.flags.messageType == .direct, "Devices acknowledge only direct messages.")

    let answer = try await request(
      .sendExtendedMessage(message),
      to: message.destination,
      command1: message.command.command1,
      awaitingReply: { reply($0) != nil },
      timeout: timeout
    )

    // The last step accepted the answer only because `reply` read it.
    guard let value = reply(answer) else {

      preconditionFailure("A request's reply is the message its reader accepted.")

    }

    return value

  }

  /// Reads every record in a device's ALL-Link database, one record at a time.
  ///
  /// Each record is requested by its address, starting with `0x0000` for the first and then
  /// counting down by 8 from the address the device reports, until the device reports the
  /// record that marks the end of its database. A record that doesn't arrive in time is asked
  /// for again, as many times as the modem's ``RetryPolicy`` allows, so a message lost on the
  /// network costs one short wait rather than the whole read.
  ///
  /// - Parameters:
  ///   - device: The device whose database to read.
  ///   - timeout: How long to wait for each record. Defaults to
  ///     ``Modem/defaultExtendedRequestTimeout``.
  /// - Returns: The records in the device's order. The last is the record that marks the end
  ///   of the database, whose address is where a new record goes, unless the read reached the
  ///   bottom of the database's memory first.
  /// - Throws: The errors of ``Modem/request(_:awaitingReply:timeout:)``, once every attempt
  ///   at a record has failed.
  public func readAllLinkDatabase(
    of device: InsteonAddress,
    timeout: Duration = Modem.defaultExtendedRequestTimeout
  ) async throws -> [AllLinkRecordResponse] {

    var responses: [AllLinkRecordResponse] = []
    var address: UInt16 = 0x0000

    while true {

      let response = try await readAllLinkRecord(of: device, at: address, timeout: timeout)

      responses.append(response)

      guard !response.isEndOfDatabase else {

        return responses

      }

      // Addresses count down by 8, and 0x0000 asks for the first record again, so the read
      // ends at the bottom of the database's memory.
      guard response.address > 8 else {

        return responses

      }

      address = response.address - 8

    }

  }

  /// Reads the record at an address in a device's ALL-Link database.
  ///
  /// A record that doesn't arrive in time is asked for again, as many times as the modem's
  /// ``RetryPolicy`` allows.
  ///
  /// - Parameters:
  ///   - device: The device whose database to read.
  ///   - address: The record's address, or `0x0000` for the first record.
  ///   - timeout: How long to wait for each attempt. Defaults to
  ///     ``Modem/defaultExtendedRequestTimeout``.
  /// - Returns: The record and its address.
  /// - Throws: The errors of ``Modem/request(_:awaitingReply:timeout:)``, once every attempt
  ///   has failed.
  public func readAllLinkRecord(
    of device: InsteonAddress,
    at address: UInt16,
    timeout: Duration = Modem.defaultExtendedRequestTimeout
  ) async throws -> AllLinkRecordResponse {

    var attempt = 1

    while true {

      do {

        return try await request(
          AllLinkDatabaseRequest.read(address: address).message(to: device),
          awaitingReply: { message in

            // Address 0x0000 asks for the first record, which the device reports at its own address.
            AllLinkRecordResponse(message).flatMap { address == 0x0000 || $0.address == address ? $0 : nil }

          },
          timeout: timeout
        )

      } catch let ModemError.deviceTimedOut(address) where address == device && attempt < retryPolicy.attempts {

        attempt += 1

      }

    }

  }

  /// Finds every record in the modem's own ALL-Link database for a group and device: its
  /// controller record and its responder record, either or both.
  ///
  /// The modem searches with Manage ALL-Link Record's Find First and Find Next, which match a
  /// record's group and address and report it in an ALL-Link Record Response. The modem NAKs
  /// once there are no more, so a NAK ends the search rather than being sent again.
  ///
  /// - Parameters:
  ///   - group: The group the records belong to.
  ///   - device: The device the records link to.
  /// - Returns: The matching records, in the order the modem finds them.
  /// - Throws: ``ModemError/rejected(_:)`` if the modem stays busy through every attempt,
  ///   ``ModemError/timedOut(_:)`` if it doesn't answer, ``ModemError/connectionClosed`` if
  ///   the modem is closed, `CancellationError` if the task is canceled, or the connection's
  ///   error.
  public func allLinkRecords(group: AllLinkGroupNumber, device: InsteonAddress) async throws -> [AllLinkRecord] {

    let key = AllLinkRecord(flags: [], group: group, address: device)

    return try await records(
      first: .manageAllLinkRecord(action: .findFirst, record: key),
      next: .manageAllLinkRecord(action: .findNext, record: key)
    )

  }

  /// Reads every record in the modem's own ALL-Link database.
  ///
  /// The modem reports its records one at a time: Get First ALL-Link Record (`0x69`) starts the
  /// scan and Get Next ALL-Link Record (`0x6A`) continues it, each answered by an ALL-Link Record
  /// Response. The Insteon Developer's Guide says the modem NAKs Get First when its database is
  /// empty and Get Next when there are no more records, so that NAK ends the scan. A NAK without
  /// the echo means the modem is busy, so the command is sent again.
  ///
  /// The scan holds the modem's turn from the first record to the last, so no other command
  /// can move the modem's place in its database partway through. A record that's lost after
  /// the modem accepts the command fails the scan, since asking again would skip it.
  ///
  /// - Returns: The modem's records, in its order. An empty database returns an empty array.
  /// - Throws: ``ModemError/rejected(_:)`` if the modem stays busy through every attempt,
  ///   ``ModemError/timedOut(_:)`` if it doesn't answer, ``ModemError/connectionClosed`` if
  ///   the modem is closed, `CancellationError` if the task is canceled, or the connection's
  ///   error.
  public func allLinkRecords() async throws -> [AllLinkRecord] {

    try await records(first: .getFirstAllLinkRecord, next: .getNextAllLinkRecord)

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

  private func request(
    _ command: SerialCommand,
    to device: InsteonAddress,
    command1: UInt8,
    awaitingReply isReply: (@Sendable (ReceivedMessage) -> Bool)? = nil,
    timeout: Duration
  ) async throws -> ReceivedMessage {

    let modemExchange = Self.exchange(for: command)
    let unconfirmed: ModemStoppedEchoing = ModemStoppedEchoing(device: device, command: command.number)

    // A modem that has answered before and then doesn't echo a message to a device is most
    // likely still busy with a device that doesn't answer, not disconnected.
    let echoSteps: [AnswerStep<ModemReply>] = modemExchange.steps.map { (step: AnswerStep<ModemReply>) -> AnswerStep<ModemReply> in

      var echoStep: AnswerStep<ModemReply> = step
      echoStep.timedOutAfterReplies = unconfirmed

      return echoStep

    }
    var steps: [AnswerStep<ModemReply>] = echoSteps + [Self.acknowledgment(from: device, of: command1)]

    if let isReply {

      steps.append(Self.reply(from: device, matching: isReply))

    }

    let exchange = Exchange(bytes: command.bytes, steps: steps, timeout: timeout, transferTime: modemExchange.transferTime)

    // The last step, the acknowledgment or the reply after it, only accepts a message
    // received from the device.
    guard case let .messageReceived(answer) = try await pacer.send([exchange])[0] else {

      preconditionFailure("A request is answered only by a message from its device.")

    }

    return answer

  }

  /// The step that waits for a device to acknowledge a direct message.
  ///
  /// The acknowledgment repeats the message's cmd1, except for a status request (`0x19`),
  /// whose acknowledgment carries the device's ALL-Link database delta in its place.
  private static func acknowledgment(from device: InsteonAddress, of command1: UInt8) -> AnswerStep<ModemReply> {

    AnswerStep(
      verdict: { reply in

        guard
          case let .messageReceived(message) = reply,
          message.sender == device,
          command1 == 0x19 || message.command.command1 == command1
        else {

          return nil

        }

        switch message.flags.messageType {
        case .directAcknowledgment:
          return .accepted
        case .directNegativeAcknowledgment:
          guard let reason = message.nakReason, reason != .databaseSearchPending else {

            // The device answers again once its database search finishes.
            return nil

          }

          return .failed(ModemError.deviceRejected(device, reason))
        default:
          return nil
        }

      },
      timedOut: ModemError.deviceTimedOut(device)
    )

  }

  /// Collects the records the modem reports for `first` and then `next`, until it NAKs
  /// because there are no more, holding the modem's turn throughout.
  private func records(first: SerialCommand, next: SerialCommand) async throws -> [AllLinkRecord] {

    try await pacer.withTurn { turn in

      var records: [AllLinkRecord] = []
      var command = first

      while let record = try await Self.nextRecord(answering: command, in: turn) {

        records.append(record)
        command = next

      }

      return records

    }

  }

  /// Sends a command that the modem answers with one of its ALL-Link records, such as a search
  /// or a step of a scan.
  ///
  /// - Returns: The record, or `nil` once the modem NAKs because there are no more.
  private static func nextRecord(
    answering command: SerialCommand,
    in turn: CommandPacer<ModemReplyParser>.Turn
  ) async throws -> AllLinkRecord? {

    struct NotFound: Error {}

    let number = command.number
    let parameters = command.parameters
    let timedOut = ModemError.timedOut(number)

    let exchange = Exchange<ModemReply>(
      bytes: command.bytes,
      steps: [
        AnswerStep(
          verdict: { reply in

            switch reply {
            case let .echo(echo) where echo.number == number && echo.parameters == parameters:
              // A NAK to a search or a scan means there's no record to report.
              return echo.isAccepted ? .accepted : .failed(NotFound())
            case .negativeAcknowledgment:
              return .rejected(ModemError.rejected(number))
            default:
              return nil
            }

          },
          timedOut: timedOut
        ),
        AnswerStep(
          verdict: { reply in

            if case .allLinkRecord = reply {

              return .accepted

            }

            return nil

          },
          timedOut: timedOut
        ),
      ]
    )

    do {

      guard case let .allLinkRecord(record) = try await turn.send(exchange) else {

        preconditionFailure("A search or a scan is answered only by an ALL-Link Record Response.")

      }

      return record

    } catch is NotFound {

      return nil

    }

  }

  /// The step that waits for a message a device sends after acknowledging a request.
  private static func reply(
    from device: InsteonAddress,
    matching isReply: @escaping @Sendable (ReceivedMessage) -> Bool
  ) -> AnswerStep<ModemReply> {

    AnswerStep(
      verdict: { reply in

        guard case let .messageReceived(message) = reply, message.sender == device, isReply(message) else {

          return nil

        }

        return .accepted

      },
      timedOut: ModemError.deviceTimedOut(device)
    )

  }

  private static func exchange(for command: SerialCommand) -> Exchange<ModemReply> {

    if command == .doubleBeep {

      return doubleBeepExchange()

    }

    let number = command.number
    let parameters = command.parameters

    return Exchange(
      bytes: command.bytes,
      answer: { reply in

        switch reply {
        // Matching the parameters keeps a late echo of an earlier command from answering this one.
        case let .echo(echo) where echo.number == number && echo.parameters == parameters:
          return isAcceptedEcho(echo, of: command)
        // These commands are answered with their data in place of a plain echo.
        case .modemInfo where number == .getModemInfo,
             .modemConfiguration where number == .getModemConfiguration,
             .radioStatus where number == .readRadioStatus:
          return true
        case .negativeAcknowledgment:
          return false
        default:
          return nil
        }

      },
      rejected: ModemError.rejected(number),
      timedOut: ModemError.timedOut(number),
      transferTime: transferTime(of: number)
    )

  }

  /// Beep with its parameter byte, which isn't written again after a NAK: a modem whose
  /// firmware doesn't take the parameter NAKs it, or echoes Beep without it, every time.
  private static func doubleBeepExchange() -> Exchange<ModemReply> {

    let command: SerialCommand = .doubleBeep
    let rejected: ModemError = .rejected(.beep)

    let step = AnswerStep<ModemReply>(
      verdict: { (reply: ModemReply) -> Verdict? in

        switch reply {
        case let .echo(echo) where echo.number == .beep:
          return isAcceptedEcho(echo, of: command) ? .accepted : .failed(rejected)
        case .negativeAcknowledgment:
          return .failed(rejected)
        default:
          return nil
        }

      },
      timedOut: ModemError.timedOut(.beep)
    )

    return Exchange(bytes: command.bytes, steps: [step])

  }

  /// How much longer than the answer timeout a command may take. The Insteon Developer's Guide says
  /// the modem answers Reset the IM once it has erased its memory, which takes about 20
  /// seconds on a model with external EEPROM.
  private static func transferTime(of number: SerialCommandNumber) -> Duration {

    number == .resetModem ? .seconds(20) : .zero

  }

}

/// The modem didn't answer a raw command in time, which `Modem.write(rawCommand:)` doesn't
/// treat as an error.
private struct RawCommandUnanswered: Error {}
