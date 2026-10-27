import Testing
import InsteonModem
import InsteonProtocol

struct ModemTests {

  let fastRetries = Modem.RetryPolicy(attempts: 3, delay: .milliseconds(10), echoTimeout: .milliseconds(200))

  @Test func sendReturnsOnceTheModemAcknowledges() async throws {

    let connection = ScriptedConnection()
    let modem = Modem(connection: connection, retryPolicy: fastRetries)

    try await modem.send(.getModemConfiguration)

    #expect(connection.written == [[0x02, 0x73]])

  }

  @Test func sendRetriesAfterANak() async throws {

    let connection = ScriptedConnection { written, index in written + [index == 0 ? 0x15 : 0x06] }
    let modem = Modem(connection: connection, retryPolicy: fastRetries)

    try await modem.send(.ledOn)

    #expect(connection.written == [[0x02, 0x6D], [0x02, 0x6D]])

  }

  @Test func sendRetriesAfterALoneNak() async throws {

    let connection = ScriptedConnection { written, index in index == 0 ? [0x15] : written + [0x06] }
    let modem = Modem(connection: connection, retryPolicy: fastRetries)

    try await modem.send(.beep)

    #expect(connection.written.count == 2)

  }

  @Test func sendThrowsWhenEveryAttemptIsRejected() async {

    let connection = ScriptedConnection { written, _ in written + [0x15] }
    let modem = Modem(connection: connection, retryPolicy: fastRetries)

    await #expect(throws: ModemError.rejected(.ledOff)) {

      try await modem.send(.ledOff)

    }

    #expect(connection.written.count == 3)

  }

  @Test func sendTimesOutWithoutAnEcho() async {

    let connection = ScriptedConnection { _, _ in [] }
    let modem = Modem(connection: connection, retryPolicy: Modem.RetryPolicy(echoTimeout: .milliseconds(50)))

    await #expect(throws: ModemError.timedOut(.getModemInfo)) {

      try await modem.send(.getModemInfo)

    }

  }

  @Test func sendFailsWhenTheConnectionCloses() async {

    let connection = ScriptedConnection { _, _ in [] }
    let modem = Modem(connection: connection, retryPolicy: Modem.RetryPolicy(echoTimeout: .seconds(10)))

    await #expect(throws: ModemError.connectionClosed) {

      async let sent: Void = modem.send(.getModemInfo)
      try await Task.sleep(for: .milliseconds(50))
      connection.incoming.finish()
      try await sent

    }

  }

  @Test func repliesIncludeEchoesAndMessagesFromDevices() async throws {

    let deviceMessage: [UInt8] = [0x02, 0x50, 0xAA, 0xBB, 0xCC, 0x11, 0x22, 0x33, 0x2B, 0x11, 0xFF]
    let connection = ScriptedConnection { written, _ in written + [0x06] + deviceMessage }
    let modem = Modem(connection: connection, retryPolicy: fastRetries)

    let replies = await modem.replies()
    try await modem.send(.beep)

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

  @Test func sendsCommandsOneAtATime() async throws {

    let connection = ScriptedConnection()
    let modem = Modem(connection: connection, retryPolicy: fastRetries)

    async let first: Void = modem.send(.ledOn)
    async let second: Void = modem.send(.ledOff)
    async let third: Void = modem.send(.beep)
    _ = try await (first, second, third)

    #expect(Set(connection.written) == [[0x02, 0x6D], [0x02, 0x6E], [0x02, 0x77]])
    #expect(connection.written.count == 3)

  }

}
