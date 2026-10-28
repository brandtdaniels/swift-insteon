import Testing
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// Requests to devices, run on a ``TestClock`` so timeouts never depend on the machine's speed.
struct RequestTests {

  let clock = TestClock()

  let device = InsteonAddress(0x1A, 0x2B, 0x3C)

  let modemAddress = InsteonAddress(0x11, 0x22, 0x33)

  let engineVersionRequest = StandardMessage(
    to: InsteonAddress(0x1A, 0x2B, 0x3C),
    command: StandardDirectCommand.getEngineVersion
  )

  func makeModem(_ connection: ScriptedConnection) -> Modem {

    Modem(
      connection: connection,
      retryPolicy: RetryPolicy(attempts: 3, delay: .zero, answerTimeout: .seconds(2)),
      clock: clock
    )

  }

  func run(_ modem: Modem, _ body: () async throws -> Void) async throws {

    try await withRunning({ try await modem.run() }, body)

  }

  /// A standard message the modem received from `sender`, as `0x50` bytes.
  func received(
    from sender: InsteonAddress,
    _ type: MessageFlags.MessageType,
    command1: UInt8,
    command2: UInt8
  ) -> [UInt8] {

    [0x02, 0x50] + sender.bytes + modemAddress.bytes
      + [MessageFlags(messageType: type, maxHops: .three, hopsLeft: .two).rawValue, command1, command2]

  }

  @Test func returnsTheDevicesAcknowledgement() async throws {

    let acknowledgement = received(from: device, .directAcknowledgement, command1: 0x0D, command2: 0x02)
    let connection = ScriptedConnection { written, _ in written + [0x06] + acknowledgement }
    let modem = makeModem(connection)

    try await run(modem) {

      let answer = try await modem.request(engineVersionRequest)

      #expect(answer.sender == device)
      #expect(answer.flags.messageType == .directAcknowledgement)
      #expect(answer.command == Command(command1: 0x0D, command2: 0x02))

    }

    #expect(connection.written == [[0x02, 0x62] + engineVersionRequest.bytes])

  }

  @Test func throwsTheReasonADeviceGivesForRejectingAMessage() async throws {

    let rejection = received(from: device, .directNegativeAcknowledgement, command1: 0x0D, command2: 0xFF)
    let connection = ScriptedConnection { written, _ in written + [0x06] + rejection }
    let modem = makeModem(connection)

    try await run(modem) {

      await #expect(throws: ModemError.deviceRejected(device, .notLinked)) {

        try await modem.request(engineVersionRequest)

      }

    }

    // A device's rejection isn't the modem being busy, so the message isn't sent again.
    #expect(connection.written.count == 1)

  }

  @Test func keepsWaitingWhileADeviceSearchesItsDatabase() async throws {

    let pending = received(from: device, .directNegativeAcknowledgement, command1: 0x0D, command2: 0xFC)
    let acknowledgement = received(from: device, .directAcknowledgement, command1: 0x0D, command2: 0x02)
    let connection = ScriptedConnection { written, _ in written + [0x06] + pending + acknowledgement }
    let modem = makeModem(connection)

    try await run(modem) {

      let answer = try await modem.request(engineVersionRequest)

      #expect(answer.flags.messageType == .directAcknowledgement)

    }

  }

  @Test func ignoresAcknowledgementsBeforeTheEchoAndFromOtherDevices() async throws {

    let stale = received(from: device, .directAcknowledgement, command1: 0x0D, command2: 0x00)
    let other = received(from: InsteonAddress(0x44, 0x55, 0x66), .directAcknowledgement, command1: 0x0D, command2: 0x01)
    let current = received(from: device, .directAcknowledgement, command1: 0x0D, command2: 0x02)
    let connection = ScriptedConnection { written, _ in stale + written + [0x06] + other + current }
    let modem = makeModem(connection)

    try await run(modem) {

      let answer = try await modem.request(engineVersionRequest)

      #expect(answer.command.command2 == 0x02)

    }

  }

  @Test func ignoresAnAcknowledgementOfAnotherCommand() async throws {

    let late = received(from: device, .directAcknowledgement, command1: 0x11, command2: 0xFF)
    let current = received(from: device, .directAcknowledgement, command1: 0x0D, command2: 0x02)
    let connection = ScriptedConnection { written, _ in written + [0x06] + late + current }
    let modem = makeModem(connection)

    try await run(modem) {

      let answer = try await modem.request(engineVersionRequest)

      #expect(answer.command == Command(command1: 0x0D, command2: 0x02))

    }

  }

  // A status request's acknowledgement carries the ALL-Link database delta in cmd1.
  @Test func acceptsAStatusRequestsAcknowledgementWhateverItsCommand1() async throws {

    let request = StandardMessage(to: device, command: StandardDirectCommand.statusRequest())
    let acknowledgement = received(from: device, .directAcknowledgement, command1: 0x05, command2: 0xFF)
    let connection = ScriptedConnection { written, _ in written + [0x06] + acknowledgement }
    let modem = makeModem(connection)

    try await run(modem) {

      let answer = try await modem.request(request)

      #expect(answer.command == Command(command1: 0x05, command2: 0xFF))

    }

  }

  @Test func sendsTheMessageAgainWhileTheModemIsBusy() async throws {

    let acknowledgement = received(from: device, .directAcknowledgement, command1: 0x0D, command2: 0x02)
    let connection = ScriptedConnection { written, index in

      index == 0 ? written + [0x15] : written + [0x06] + acknowledgement

    }
    let modem = makeModem(connection)

    try await run(modem) { _ = try await modem.request(engineVersionRequest) }

    #expect(connection.written.count == 2)

  }

  @Test func timesOutWhenTheDeviceDoesntAnswer() async throws {

    let connection = ScriptedConnection { written, _ in written + [0x06] }
    let modem = makeModem(connection)

    try await run(modem) {

      await #expect(throws: ModemError.deviceTimedOut(device)) {

        async let answer = modem.request(engineVersionRequest, timeout: .seconds(5))
        await clock.waitForSleeper(until: .seconds(5))
        clock.advance(by: .seconds(5))
        _ = try await answer

      }

    }

  }

  @Test func blamesTheModemWhenItDoesntEchoTheMessage() async throws {

    let connection = ScriptedConnection { _, _ in [] }
    let modem = makeModem(connection)

    try await run(modem) {

      await #expect(throws: ModemError.timedOut(.sendMessage)) {

        async let answer = modem.request(engineVersionRequest)
        await clock.waitForSleeper(until: .seconds(3))
        clock.advance(by: .seconds(3))
        _ = try await answer

      }

    }

  }

  @Test func returnsTheAcknowledgementOfAnExtendedMessage() async throws {

    let message = ExtendedMessage(to: device, command: ExtendedDirectCommand.getSet())
    let acknowledgement = received(from: device, .directAcknowledgement, command1: 0x2E, command2: 0x00)
    let connection = ScriptedConnection { written, _ in written + [0x06] + acknowledgement }
    let modem = makeModem(connection)

    try await run(modem) {

      let answer = try await modem.request(message)

      #expect(answer.command == Command(command1: 0x2E, command2: 0x00))

    }

    #expect(connection.written == [[0x02, 0x62] + message.bytes])

  }

}
