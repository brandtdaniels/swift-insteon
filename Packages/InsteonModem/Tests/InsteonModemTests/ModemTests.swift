import Testing
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// Every test runs on a ``TestClock`` that only moves when the test advances it, so retry
/// delays and echo timeouts never depend on how fast the machine running the tests is.
struct ModemTests {

  let clock = TestClock()

  let policy = RetryPolicy(attempts: 3, delay: .zero, answerTimeout: .seconds(2))

  func makeModem(_ connection: ScriptedConnection) -> Modem {

    Modem(connection: connection, retryPolicy: policy, clock: clock)

  }

  /// Runs `body` while `modem` reads from its connection, then stops the modem.
  ///
  /// - Throws: The error `body` throws, or the error `Modem/run()` throws.
  func run(_ modem: Modem, _ body: () async throws -> Void) async throws {

    try await withRunning({ try await modem.run() }, body)

  }

  @Test func retryPolicyKeepsAtLeastOneAttempt() {

    var policy = RetryPolicy()
    policy.attempts = 0

    #expect(policy.attempts == 1)
    #expect(RetryPolicy(attempts: -2).attempts == 1)

  }

  @Test func withConnectionReturnsWhatItsBodyReturns() async throws {

    let connection = ScriptedConnection()

    let written = try await Modem.withConnection(connection, retryPolicy: policy, clock: clock) { modem in

      try await modem.send(.beep)

      return connection.written

    }

    #expect(written == [[0x02, 0x77]])

  }

  @Test func withConnectionClosesTheModemWhenItsBodyReturns() async throws {

    let modem = try await Modem.withConnection(ScriptedConnection(), retryPolicy: policy, clock: clock) { $0 }

    await #expect(throws: ModemError.connectionClosed) {

      try await modem.send(.beep)

    }

  }

  @Test func withConnectionThrowsTheConnectionsError() async {

    struct Unplugged: Error {}

    let connection = ScriptedConnection()

    await #expect(throws: Unplugged.self) {

      try await Modem.withConnection(connection, retryPolicy: policy, clock: clock) { modem in

        let replies = await modem.replies()
        connection.incoming.finish(throwing: Unplugged())

        // The stream finishes once the modem closes.
        for await _ in replies {}

      }

    }

  }

  @Test func withConnectionThrowsTheConnectionsErrorRatherThanTheOneItCaused() async {

    struct Unplugged: Error {}

    let connection = ScriptedConnection()

    await #expect(throws: Unplugged.self) {

      try await Modem.withConnection(connection, retryPolicy: policy, clock: clock) { modem in

        let replies = await modem.replies()
        connection.incoming.finish(throwing: Unplugged())

        for await _ in replies {}

        // Fails with connectionClosed, because the connection failed.
        try await modem.send(.beep)

      }

    }

  }

  @Test func withConnectionSucceedsWhenItsConnectionThrowsAsItStops() async throws {

    let connection = CancellationThrowingConnection(clock: clock)

    let value = try await Modem.withConnection(connection, retryPolicy: policy, clock: clock) { _ in 42 }

    #expect(value == 42)

  }

  @Test func sendReturnsOnceTheModemAcknowledges() async throws {

    let connection = ScriptedConnection()
    let modem = makeModem(connection)

    try await run(modem) { try await modem.send(.beep) }

    #expect(connection.written == [[0x02, 0x77]])

  }

  @Test(arguments: [
    (SerialCommand.getModemInfo, [UInt8]([0x02, 0x60, 0x1A, 0x2B, 0x3C, 0x03, 0x37, 0x9C, 0x06])),
    (SerialCommand.getModemConfiguration, [UInt8]([0x02, 0x73, 0x40, 0x05, 0x00, 0x06])),
  ])
  func sendReturnsWhenTheModemRepliesWithData(command: SerialCommand, reply: [UInt8]) async throws {

    let connection = ScriptedConnection { _, _ in reply }
    let modem = makeModem(connection)

    try await run(modem) { try await modem.send(command) }

    #expect(connection.written == [command.bytes])

  }

  @Test func sendRetriesAfterANak() async throws {

    let connection = ScriptedConnection { written, index in written + [index == 0 ? 0x15 : 0x06] }
    let modem = makeModem(connection)

    try await run(modem) { try await modem.send(.ledOn) }

    #expect(connection.written == [[0x02, 0x6D], [0x02, 0x6D]])

  }

  @Test func sendRetriesAfterALoneNak() async throws {

    let connection = ScriptedConnection { written, index in index == 0 ? [0x15] : written + [0x06] }
    let modem = makeModem(connection)

    try await run(modem) { try await modem.send(.beep) }

    #expect(connection.written.count == 2)

  }

  @Test func sendWaitsBeforeRetrying() async throws {

    let connection = ScriptedConnection { written, index in written + [index == 0 ? 0x15 : 0x06] }
    let modem = Modem(connection: connection, retryPolicy: RetryPolicy(delay: .milliseconds(500)), clock: clock)

    try await run(modem) {

      async let sent: Void = modem.send(.ledOn)

      // Wait for the retry delay specifically; the first attempt's timeout may also be asleep
      // until the NAK cancels it.
      await clock.waitForSleeper(until: .milliseconds(500))
      #expect(connection.written.count == 1)

      clock.advance(by: .milliseconds(500))
      try await sent

    }

    #expect(connection.written.count == 2)

  }

  @Test func sendThrowsWhenEveryAttemptIsRejected() async throws {

    let connection = ScriptedConnection { written, _ in written + [0x15] }
    let modem = makeModem(connection)

    try await run(modem) {

      await #expect(throws: ModemError.rejected(.ledOff)) {

        try await modem.send(.ledOff)

      }

    }

    #expect(connection.written.count == 3)

  }

  @Test func sendTimesOutWithoutAnEcho() async throws {

    let connection = ScriptedConnection { _, _ in [] }
    let modem = makeModem(connection)

    try await run(modem) {

      await #expect(throws: ModemError.timedOut(.getModemInfo)) {

        async let sent: Void = modem.send(.getModemInfo)
        await clock.waitForSleeper(until: .seconds(2))
        clock.advance(by: .seconds(2))
        try await sent

      }

    }

  }

  // The guide: the modem answers once it has erased its memory, which takes about 20 seconds
  // on a model with external EEPROM.
  @Test func waitsForTheModemToEraseItsMemoryWhenItResets() async throws {

    let connection = ScriptedConnection { _, _ in [] }
    let modem = makeModem(connection)

    try await run(modem) {

      await #expect(throws: ModemError.timedOut(.resetModem)) {

        async let sent: Void = modem.send(.resetModem)
        await clock.waitForSleeper(until: .seconds(22))
        clock.advance(by: .seconds(22))
        try await sent

      }

    }

  }

  @Test func sendFailsWhenTheConnectionCloses() async throws {

    let connection = ScriptedConnection { _, _ in [] }
    let modem = makeModem(connection)

    try await run(modem) {

      await #expect(throws: ModemError.connectionClosed) {

        async let sent: Void = modem.send(.getModemInfo)
        var writes = connection.writeLog.makeAsyncIterator()
        _ = await writes.next()
        connection.incoming.finish()
        try await sent

      }

    }

  }

  @Test func sendFailsAfterTheConnectionHasClosed() async throws {

    let connection = ScriptedConnection()
    let modem = makeModem(connection)
    let replies = await modem.replies()

    connection.incoming.finish()
    try await modem.run()

    for await _ in replies {}

    await #expect(throws: ModemError.connectionClosed) {

      try await modem.send(.beep)

    }

    #expect(connection.written.isEmpty)

  }

  @Test func cancelingRunClosesTheModem() async throws {

    let connection = ScriptedConnection()
    let modem = makeModem(connection)
    let replies = await modem.replies()

    try await run(modem) {}

    for await _ in replies {}

    await #expect(throws: ModemError.connectionClosed) {

      try await modem.send(.beep)

    }

    #expect(connection.written.isEmpty)

  }

  @Test func repliesIncludeEchoesAndMessagesFromDevices() async throws {

    let deviceMessage: [UInt8] = [0x02, 0x50, 0xAA, 0xBB, 0xCC, 0x11, 0x22, 0x33, 0x2B, 0x11, 0xFF]
    let connection = ScriptedConnection { written, _ in written + [0x06] + deviceMessage }
    let modem = makeModem(connection)

    let replies = await modem.replies()
    try await run(modem) { try await modem.send(.beep) }

    var iterator = replies.makeAsyncIterator()
    let echo = await iterator.next()
    let next = await iterator.next()

    #expect(echo == .echo(CommandEcho(number: .beep, parameters: [], isAccepted: true)))

    guard case let .messageReceived(message)? = next else {

      Issue.record("Expected a received message")

      return

    }

    #expect(message.sender == InsteonAddress(0xAA, 0xBB, 0xCC))

  }

  @Test func ignoresALateEchoOfAnEarlierCommand() async throws {

    let late = SerialCommand.setAcknowledgementByte(0x01)
    let current = SerialCommand.setAcknowledgementByte(0x02)
    let connection = ScriptedConnection { _, index in

      switch index {
      case 0: []
      // The first command's echo arrives late, ahead of a NAK for the second.
      case 1: late.bytes + [0x06] + current.bytes + [0x15]
      default: current.bytes + [0x06]
      }

    }
    let modem = makeModem(connection)

    try await run(modem) {

      await #expect(throws: ModemError.timedOut(.setAcknowledgementByte)) {

        async let sent: Void = modem.send(late)
        await clock.waitForSleeper(until: .seconds(2))
        clock.advance(by: .seconds(2))
        try await sent

      }

      try await modem.send(current)

    }

    #expect(connection.written == [late.bytes, current.bytes, current.bytes])

  }

  @Test func retriesAnInfoRequestRejectedWithAShortNak() async throws {

    let info: [UInt8] = [0x02, 0x60, 0x1A, 0x2B, 0x3C, 0x03, 0x37, 0x9C, 0x06]
    // A user reset arrives with the NAK, so the test can tell the NAK has been read.
    let connection = ScriptedConnection { _, index in index == 0 ? [0x02, 0x55, 0x02, 0x60, 0x15] : info }
    let modem = makeModem(connection)
    var replies = await modem.replies().makeAsyncIterator()

    try await run(modem) {

      async let sent: Void = modem.send(.getModemInfo)

      #expect(await replies.next() == .userReset)

      // The NAK can't be told apart from the start of a reply until the wait for an echo ends.
      await clock.waitForSleeper(until: .seconds(2))
      clock.advance(by: .seconds(2))
      try await sent

    }

    #expect(connection.written == [[0x02, 0x60], [0x02, 0x60]])

  }

  @Test func doesntWriteACanceledSend() async throws {

    let connection = ScriptedConnection { _, _ in [] }
    let modem = makeModem(connection)

    try await run(modem) {

      async let first: Void = modem.send(.ledOn)
      var writes = connection.writeLog.makeAsyncIterator()
      let frame = try #require(await writes.next())

      // Canceled while the first command holds the modem.
      await withThrowingTaskGroup(of: Void.self) { group in

        group.addTask { try await modem.send(.ledOff) }
        group.cancelAll()

        await #expect(throws: CancellationError.self) {

          try await group.next()

        }

      }

      connection.incoming.yield(frame + [0x06])
      try await first

    }

    #expect(connection.written == [[0x02, 0x6D]])

  }

  @Test func cancelingASendStopsWaitingForItsEcho() async throws {

    let connection = ScriptedConnection { _, _ in [] }
    let modem = makeModem(connection)

    try await run(modem) {

      var writes = connection.writeLog.makeAsyncIterator()

      await withThrowingTaskGroup(of: Void.self) { group in

        group.addTask { try await modem.send(.ledOn) }
        _ = await writes.next()
        group.cancelAll()

        await #expect(throws: CancellationError.self) {

          try await group.next()

        }

      }

      // The canceled command was written, so the next one waits for the modem to answer it.
      async let next: Void = modem.send(.ledOff)
      await clock.waitForSleeper(until: .seconds(2))
      #expect(connection.written == [[0x02, 0x6D]])

      connection.incoming.yield([0x02, 0x6D, 0x06])
      let frame = try #require(await writes.next())
      connection.incoming.yield(frame + [0x06])
      try await next

    }

    #expect(connection.written == [[0x02, 0x6D], [0x02, 0x6E]])

  }

  @Test func theNextSendWaitsOutACanceledSendsEchoTimeout() async throws {

    let connection = ScriptedConnection { _, _ in [] }
    let modem = makeModem(connection)

    try await run(modem) {

      var writes = connection.writeLog.makeAsyncIterator()

      await withThrowingTaskGroup(of: Void.self) { group in

        group.addTask { try await modem.send(.ledOn) }
        _ = await writes.next()
        group.cancelAll()
        _ = try? await group.next()

      }

      // The modem never answers the canceled command, so the next one goes out after the
      // echo timeout.
      async let next: Void = modem.send(.ledOff)
      await clock.waitForSleeper(until: .seconds(2))
      #expect(connection.written == [[0x02, 0x6D]])

      clock.advance(by: .seconds(2))
      let frame = try #require(await writes.next())
      connection.incoming.yield(frame + [0x06])
      try await next

    }

    #expect(connection.written == [[0x02, 0x6D], [0x02, 0x6E]])

  }

  @Test func runThrowsOnceTheModemHasClosed() async throws {

    let connection = ScriptedConnection()
    let modem = makeModem(connection)

    connection.incoming.finish()
    try await modem.run()

    await #expect(throws: ModemError.connectionClosed) {

      try await modem.run()

    }

  }

  @Test func sendsCommandsOneAtATime() async throws {

    // The test answers each write itself, so it can check nothing else is written first.
    let connection = ScriptedConnection { _, _ in [] }
    let modem = makeModem(connection)

    try await run(modem) {

      async let first: Void = modem.send(.ledOn)
      async let second: Void = modem.send(.ledOff)
      async let third: Void = modem.send(.beep)

      var writes = connection.writeLog.makeAsyncIterator()

      for count in 1...3 {

        let frame = try #require(await writes.next())
        #expect(connection.written.count == count)
        connection.incoming.yield(frame + [0x06])

      }

      _ = try await (first, second, third)

    }

    #expect(Set(connection.written) == [[0x02, 0x6D], [0x02, 0x6E], [0x02, 0x77]])

  }

}

/// A connection whose stream waits for bytes that never come, and throws `CancellationError`
/// when it's stopped.
private struct CancellationThrowingConnection: ModemConnection {

  let clock: TestClock

  func write(_ bytes: [UInt8]) async throws {}

  func receive() -> AsyncThrowingStream<[UInt8], any Error> {

    AsyncThrowingStream(unfolding: { [clock] in

      try await clock.sleep(for: .seconds(1))

      return nil

    })

  }

}
