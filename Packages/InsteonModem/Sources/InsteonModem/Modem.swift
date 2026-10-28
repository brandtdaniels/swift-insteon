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
  /// - Throws: ``ModemError/rejected(_:)`` if the modem NAKs every attempt,
  ///   ``ModemError/timedOut(_:)`` if it doesn't echo the command,
  ///   ``ModemError/connectionClosed`` if the modem is closed, `CancellationError` if the
  ///   task is canceled, or the connection's error.
  public func send(_ command: SerialCommand) async throws {

    try await pacer.send([Self.exchange(for: command)])

  }

  /// Asks the modem about itself with Get IM Info (`0x60`).
  ///
  /// - Returns: The modem's address, device category, subcategory and firmware version. Every
  ///   INSTEON modem reports category `DeviceCategory.networkBridges`, and the subcategory
  ///   names the model; see <doc:SupportedModems>.
  /// - Throws: The errors of ``Modem/send(_:)``.
  public func modemInfo() async throws -> ModemInfo {

    guard case let .modemInfo(info) = try await pacer.send([Self.exchange(for: .getModemInfo)])[0] else {

      preconditionFailure("Get IM Info is answered only by the modem's information.")

    }

    return info

  }

  /// How long ``Modem/sendAllLinkCommand(group:command:timeout:)`` waits for the cleanups by
  /// default: 10 seconds.
  ///
  /// The Developer's Guide gives the worst case as 2.150 seconds from the broadcast to the
  /// first member's cleanup report and 1.550 seconds to each one after, so 10 seconds covers a
  /// group of up to six members that all need every retry. Pass more for a larger group.
  public static let defaultAllLinkCommandTimeout: Duration = .seconds(10)

  /// Sends a command to one of the modem's ALL-Link groups and waits for the modem to finish
  /// its cleanups.
  ///
  /// The modem broadcasts the command to the group, then sends each member a cleanup message,
  /// as Send ALL-Link Command (`0x61`) describes. The modem's turn is held until the modem's
  /// ALL-Link Cleanup Status Report (`0x58`), since the guide says any message sent before then
  /// cancels the rest of the cleanups. Meanwhile each member's cleanup acknowledgement, cleanup
  /// NAK or ALL-Link Cleanup Failure Report (`0x56`) is collected.
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
  ///   - command: The command to broadcast. Its cmd2 goes in the broadcast; the cleanups carry
  ///     the group number instead. The guide says not to send Light Start Manual Change
  ///     (cmd1 `0x17`) this way, so it isn't allowed.
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
    let parameters = serialCommand.parameters

    // Listening starts first, so no cleanup report can be missed.
    let replies = await pacer.replies()

    let status = AnswerStep<ModemReply>(
      verdict: { reply in

        if case .allLinkCleanupStatus = reply {

          return .accepted

        }

        return nil

      },
      timedOut: ModemError.timedOut(.sendAllLinkCommand)
    )

    _ = try await pacer.send([
      Exchange(bytes: serialCommand.bytes, steps: Self.exchange(for: serialCommand).steps + [status], timeout: timeout)
    ])

    // The stream has everything up to the status report that answered the command. What came
    // before the command's accepted echo belongs to something else.
    var hasStarted = false
    var acknowledged: [InsteonAddress] = []
    var unacknowledged: [InsteonAddress] = []

    for await reply in replies {

      switch reply {
      case let .echo(echo) where echo.number == .sendAllLinkCommand && echo.parameters == parameters && echo.isAccepted:
        hasStarted = true
      case let .messageReceived(message) where hasStarted && message.command.command1 == command.command1:
        switch message.flags.messageType {
        case .allLinkCleanupAcknowledgement:
          acknowledged.append(message.sender)
        case .allLinkCleanupNegativeAcknowledgement:
          unacknowledged.append(message.sender)
        default:
          break
        }
      case let .allLinkCleanupFailed(failedGroup, address) where hasStarted && failedGroup == group:
        unacknowledged.append(address)
      case let .allLinkCleanupStatus(isComplete) where hasStarted:
        return AllLinkCleanupReport(acknowledged: acknowledged, unacknowledged: unacknowledged, isComplete: isComplete)
      default:
        break
      }

    }

    throw ModemError.connectionClosed

  }

  /// How long a request for a standard message waits for the device's answer by default:
  /// 3 seconds.
  ///
  /// The Developer's Guide gives 2.00 seconds for the INSTEON engine to retry a standard
  /// message five times from Max Hops 3, the most it retries. The extra second covers the
  /// modem's echo.
  public static let defaultRequestTimeout: Duration = .seconds(3)

  /// How long a request for an extended message waits for the device's answer by default:
  /// 4.17 seconds.
  ///
  /// The Developer's Guide gives 3.17 seconds for the INSTEON engine to retry an extended
  /// message five times from Max Hops 3. The extra second covers the modem's echo, as in
  /// ``Modem/defaultRequestTimeout``.
  public static let defaultExtendedRequestTimeout: Duration = .milliseconds(4_170)

  /// Sends a standard direct message to a device and waits for the device to acknowledge it.
  ///
  /// Devices acknowledge only direct messages, so `message` must be one. The request takes the modem's turn until the device answers, so no other command is sent
  /// while the message is crossing the network. The modem echoes the message first, and the
  /// message is sent again as the retry policy allows if the modem is busy. Then the first
  /// acknowledgement from the device that repeats the message's cmd1 answers the request; a
  /// status request is answered by the device's first acknowledgement, since it carries other
  /// data in cmd1. With the modem's monitor mode on, an acknowledgement the device sends
  /// another controller for the same cmd1 can answer it too. An i2cs device that's still
  /// searching its ALL-Link database answers with `NAKReason.databaseSearchPending` first,
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
  ///   the modem NAKs every attempt, ``ModemError/timedOut(_:)`` if the modem doesn't echo
  ///   the message, ``ModemError/connectionClosed`` if the modem is closed,
  ///   `CancellationError` if the task is canceled, or the connection's error.
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
  ///   - timeout: How long to wait for the modem's echo and the device's acknowledgement
  ///     together. Defaults to ``Modem/defaultExtendedRequestTimeout``.
  /// - Returns: The device's acknowledgement.
  /// - Throws: ``ModemError/deviceRejected(_:_:)`` if the device rejects the message,
  ///   ``ModemError/deviceTimedOut(_:)`` if it doesn't answer, ``ModemError/rejected(_:)`` if
  ///   the modem NAKs every attempt, ``ModemError/timedOut(_:)`` if the modem doesn't echo
  ///   the message, ``ModemError/connectionClosed`` if the modem is closed,
  ///   `CancellationError` if the task is canceled, or the connection's error.
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
  /// request that returns the acknowledgement.
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
  ///     sees only messages from the device that arrive after its acknowledgement.
  ///   - timeout: How long to wait for the modem's echo, the device's acknowledgement and its
  ///     reply together. Defaults to ``Modem/defaultExtendedRequestTimeout``, which covers the
  ///     guide's retries of the message but not also those of the reply, so a reply that needs
  ///     every retry can arrive late.
  /// - Returns: The device's reply.
  /// - Throws: ``ModemError/deviceRejected(_:_:)`` if the device rejects the message,
  ///   ``ModemError/deviceTimedOut(_:)`` if it doesn't acknowledge it or doesn't reply,
  ///   ``ModemError/rejected(_:)`` if the modem NAKs every attempt, ``ModemError/timedOut(_:)``
  ///   if the modem doesn't echo the message, ``ModemError/connectionClosed`` if the modem is
  ///   closed, `CancellationError` if the task is canceled, or the connection's error.
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
  /// The modem reports its records one at a time: Get First ALL-Link Record (`0x69`) starts
  /// the scan and Get Next ALL-Link Record (`0x6A`) continues it, each answered by an ALL-Link
  /// Record Response. The Developer's Guide says the modem NAKs Get First when its database is
  /// empty and Get Next when there are no more records, so that NAK ends the scan. A NAK
  /// without the echo means the modem is busy, so the command is sent again.
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
    var steps = modemExchange.steps + [Self.acknowledgement(from: device, of: command1)]

    if let isReply {

      steps.append(Self.reply(from: device, matching: isReply))

    }

    let exchange = Exchange(bytes: command.bytes, steps: steps, timeout: timeout, transferTime: modemExchange.transferTime)

    // The last step, the acknowledgement or the reply after it, only accepts a message
    // received from the device.
    guard case let .messageReceived(answer) = try await pacer.send([exchange])[0] else {

      preconditionFailure("A request is answered only by a message from its device.")

    }

    return answer

  }

  /// The step that waits for a device to acknowledge a direct message.
  ///
  /// The acknowledgement repeats the message's cmd1, except for a status request (`0x19`),
  /// whose acknowledgement carries the device's ALL-Link database delta in its place.
  private static func acknowledgement(from device: InsteonAddress, of command1: UInt8) -> AnswerStep<ModemReply> {

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
        case .directAcknowledgement:
          return .accepted
        case .directNegativeAcknowledgement:
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
            case .negativeAcknowledgement:
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
      timedOut: ModemError.timedOut(number),
      transferTime: transferTime(of: number)
    )

  }

  /// How much longer than the answer timeout a command may take. The Developer's Guide says
  /// the modem answers Reset the IM once it has erased its memory, which takes about 20
  /// seconds on a model with external EEPROM.
  private static func transferTime(of number: SerialCommandNumber) -> Duration {

    number == .resetModem ? .seconds(20) : .zero

  }

}
