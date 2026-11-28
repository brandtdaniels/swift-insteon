import Testing
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// Requests to devices, run on a ``TestClock`` so timeouts never depend on the machine's speed.
@Suite(.timeLimit(.minutes(1)))
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

  /// An ALL-Link Record Response from `device` for the record at `address`, as `0x51` bytes.
  func recordResponse(at address: UInt16, _ record: [UInt8]) -> [UInt8] {

    let flags = MessageFlags(messageType: .direct, isExtended: true, maxHops: .three, hopsLeft: .two)
    let header: [UInt8] = [0x02, 0x51] + device.bytes + modemAddress.bytes
    let command: [UInt8] = [flags.rawValue, 0x2F, 0x00]
    let userData: [UInt8] = [0x00, 0x01, UInt8(address >> 8), UInt8(address & 0xFF), 0x00] + record + [0x00]

    return header + command + userData

  }

  @Test func returnsTheDevicesAcknowledgment() async throws {

    let acknowledgment = received(from: device, .directAcknowledgment, command1: 0x0D, command2: 0x02)
    let connection = ScriptedConnection { written, _ in written + [0x06] + acknowledgment }
    let modem = makeModem(connection)

    try await run(modem) {

      let answer = try await modem.request(engineVersionRequest)

      #expect(answer.sender == device)
      #expect(answer.flags.messageType == .directAcknowledgment)
      #expect(answer.command == Command(command1: 0x0D, command2: 0x02))

    }

    #expect(connection.written == [[0x02, 0x62] + engineVersionRequest.bytes])

  }

  @Test func throwsTheReasonADeviceGivesForRejectingAMessage() async throws {

    let rejection = received(from: device, .directNegativeAcknowledgment, command1: 0x0D, command2: 0xFF)
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

    let pending = received(from: device, .directNegativeAcknowledgment, command1: 0x0D, command2: 0xFC)
    let acknowledgment = received(from: device, .directAcknowledgment, command1: 0x0D, command2: 0x02)
    let connection = ScriptedConnection { written, _ in written + [0x06] + pending + acknowledgment }
    let modem = makeModem(connection)

    try await run(modem) {

      let answer = try await modem.request(engineVersionRequest)

      #expect(answer.flags.messageType == .directAcknowledgment)

    }

  }

  @Test func ignoresAcknowledgmentsBeforeTheEchoAndFromOtherDevices() async throws {

    let stale = received(from: device, .directAcknowledgment, command1: 0x0D, command2: 0x00)
    let other = received(from: InsteonAddress(0x44, 0x55, 0x66), .directAcknowledgment, command1: 0x0D, command2: 0x01)
    let current = received(from: device, .directAcknowledgment, command1: 0x0D, command2: 0x02)
    let connection = ScriptedConnection { written, _ in stale + written + [0x06] + other + current }
    let modem = makeModem(connection)

    try await run(modem) {

      let answer = try await modem.request(engineVersionRequest)

      #expect(answer.command.command2 == 0x02)

    }

  }

  @Test func ignoresAnAcknowledgmentOfAnotherCommand() async throws {

    let late = received(from: device, .directAcknowledgment, command1: 0x11, command2: 0xFF)
    let current = received(from: device, .directAcknowledgment, command1: 0x0D, command2: 0x02)
    let connection = ScriptedConnection { written, _ in written + [0x06] + late + current }
    let modem = makeModem(connection)

    try await run(modem) {

      let answer = try await modem.request(engineVersionRequest)

      #expect(answer.command == Command(command1: 0x0D, command2: 0x02))

    }

  }

  // A status request's acknowledgment carries the ALL-Link database delta in cmd1.
  @Test func acceptsAStatusRequestsAcknowledgmentWhateverItsCommand1() async throws {

    let request = StandardMessage(to: device, command: StandardDirectCommand.statusRequest())
    let acknowledgment = received(from: device, .directAcknowledgment, command1: 0x05, command2: 0xFF)
    let connection = ScriptedConnection { written, _ in written + [0x06] + acknowledgment }
    let modem = makeModem(connection)

    try await run(modem) {

      let answer = try await modem.request(request)

      #expect(answer.command == Command(command1: 0x05, command2: 0xFF))

    }

  }

  @Test func sendsTheMessageAgainWhileTheModemIsBusy() async throws {

    let acknowledgment = received(from: device, .directAcknowledgment, command1: 0x0D, command2: 0x02)
    let connection = ScriptedConnection { written, index in

      index == 0 ? written + [0x15] : written + [0x06] + acknowledgment

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

  @Test func reportsADeviceThatDoesntAnswerAfterTheModemRejectedTheFirstAttempt() async throws {

    // The modem NAKs the first attempt and echoes the retry, but the device never answers.
    let connection = ScriptedConnection { (written: [UInt8], index: Int) -> [UInt8] in

      index == 0 ? written + [0x15] : written + [0x06]

    }
    let modem = Modem(
      connection: connection,
      retryPolicy: RetryPolicy(attempts: 3, delay: .milliseconds(500), answerTimeout: .seconds(2)),
      clock: clock
    )

    try await run(modem) {

      await #expect(throws: ModemError.deviceTimedOut(device)) {

        async let answer = modem.request(engineVersionRequest, timeout: .seconds(5))
        // The retry delay, then the retry's timeout, which starts once the delay has passed.
        await clock.waitForSleeper(until: .milliseconds(500))
        clock.advance(by: .milliseconds(500))
        await clock.waitForSleeper(until: .milliseconds(5_500))
        clock.advance(by: .seconds(5))
        _ = try await answer

      }

    }

    #expect(connection.written.count == 2)

  }

  // The Insteon Developer's Guide's time for five retries of an extended message, 3.17 seconds,
  // plus a second for the modem's echo.
  @Test func waitsLongerForAnExtendedMessage() async throws {

    let connection = ScriptedConnection { written, _ in written + [0x06] }
    let modem = makeModem(connection)
    let message = AllLinkDatabaseRequest.read(address: 0x0FFF).message(to: device)

    try await run(modem) {

      await #expect(throws: ModemError.deviceTimedOut(device)) {

        async let answer = modem.request(message)
        await clock.waitForSleeper(until: .milliseconds(4_170))
        clock.advance(by: .milliseconds(4_170))
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

  @Test(.timeLimit(.minutes(1))) func reportsAModemThatStopsEchoingAfterAnsweringAsBusyWithTheDevice() async throws {

    // The modem echoes the first request and the device acknowledges it; then the modem goes
    // quiet, as a Hub's modem does while it's still retrying a message to a device.
    let acknowledgment: [UInt8] = received(
      from: device,
      .directAcknowledgment,
      command1: engineVersionRequest.command.command1,
      command2: 0x02
    )
    let connection = ScriptedConnection { (written: [UInt8], index: Int) -> [UInt8] in

      index == 0 ? written + [0x06] + acknowledgment : []

    }
    let modem = makeModem(connection)

    try await run(modem) {

      try await modem.request(engineVersionRequest)

      await #expect(throws: ModemStoppedEchoing(device: device, command: .sendMessage)) {

        // An earlier exchange's timeout may have had the same deadline, so wait for a sleep
        // that starts after this exchange does.
        let mark = clock.mark()
        async let answer = modem.request(engineVersionRequest)
        await clock.waitForSleeper(until: .seconds(3), after: mark)
        clock.advance(by: .seconds(3))
        _ = try await answer

      }

    }

    // The message isn't sent again, since the modem may still send it once it's free.
    #expect(connection.written.count == 2)

  }

  @Test(.timeLimit(.minutes(1))) func reportsAModemThatMissesTwoEchoesInARowAsNotAnswering() async throws {

    // The modem echoes the first request and the device acknowledges it; then the modem sends
    // nothing more, so the second missed echo blames the modem rather than a busy device.
    let acknowledgment: [UInt8] = received(
      from: device,
      .directAcknowledgment,
      command1: engineVersionRequest.command.command1,
      command2: 0x02
    )
    let connection = ScriptedConnection { (written: [UInt8], index: Int) -> [UInt8] in

      index == 0 ? written + [0x06] + acknowledgment : []

    }
    let modem = makeModem(connection)

    try await run(modem) {

      try await modem.request(engineVersionRequest)

      await #expect(throws: ModemStoppedEchoing(device: device, command: .sendMessage)) {

        // An earlier exchange's timeout may have had the same deadline, so wait for a sleep
        // that starts after this exchange does.
        let mark = clock.mark()
        async let answer = modem.request(engineVersionRequest)
        await clock.waitForSleeper(until: .seconds(3), after: mark)
        clock.advance(by: .seconds(3))
        _ = try await answer

      }

      // The second missed echo in a row is the modem's, not a busy device's.
      await #expect(throws: ModemError.timedOut(.sendMessage)) {

        // An earlier exchange's timeout may have had the same deadline, so wait for a sleep
        // that starts after this exchange does.
        let mark = clock.mark()
        async let answer = modem.request(engineVersionRequest)
        await clock.waitForSleeper(until: .seconds(6), after: mark)
        clock.advance(by: .seconds(3))
        _ = try await answer

      }

    }

    #expect(connection.written.count == 3)

  }

  @Test(.timeLimit(.minutes(1))) func reportsAModemThatStopsEchoingPartwayThroughADatabaseReadAsBusyWithTheDevice() async throws {

    let acknowledgment: [UInt8] = received(from: device, .directAcknowledgment, command1: 0x2F, command2: 0x00)
    let first: [UInt8] = recordResponse(at: 0x0FFF, [0xE2, 0x04, 0x00, 0x5E, 0x5D, 0x00, 0x00, 0x04])
    let connection = ScriptedConnection { (written: [UInt8], index: Int) -> [UInt8] in

      index == 0 ? written + [0x06] + acknowledgment + first : []

    }
    let modem = makeModem(connection)

    try await run(modem) {

      await #expect(throws: ModemStoppedEchoing(device: device, command: .sendMessage)) {

        async let records = modem.readAllLinkDatabase(of: device)
        // The first record's exchange had a timeout with the same deadline, so wait for the
        // second's message, which is written only once the first exchange is over.
        var writes = connection.writeLog.makeAsyncIterator()
        _ = await writes.next()
        _ = await writes.next()
        await clock.waitForSleeper(until: .milliseconds(4_170))
        clock.advance(by: .milliseconds(4_170))
        _ = try await records

      }

    }

    #expect(connection.written.count == 2)

  }

  @Test func returnsTheAcknowledgmentOfAnExtendedMessage() async throws {

    let message = ExtendedMessage(to: device, command: ExtendedDirectCommand.getSet())
    let acknowledgment = received(from: device, .directAcknowledgment, command1: 0x2E, command2: 0x00)
    let connection = ScriptedConnection { written, _ in written + [0x06] + acknowledgment }
    let modem = makeModem(connection)

    try await run(modem) {

      let answer = try await modem.request(message)

      #expect(answer.command == Command(command1: 0x2E, command2: 0x00))

    }

    #expect(connection.written == [[0x02, 0x62] + message.bytes])

  }

  @Test func readsEveryRecordUntilTheEndOfTheDatabase() async throws {

    let acknowledgment = received(from: device, .directAcknowledgment, command1: 0x2F, command2: 0x00)
    let records: [[UInt8]] = [
      recordResponse(at: 0x0FFF, [0xE2, 0x04, 0x00, 0x5E, 0x5D, 0x00, 0x00, 0x04]),
      recordResponse(at: 0x0FF7, [0xA2, 0x05, 0x00, 0x5E, 0x5D, 0xFE, 0x1F, 0x01]),
      recordResponse(at: 0x0FEF, [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
    ]
    let connection = ScriptedConnection { written, index in written + [0x06] + acknowledgment + records[index] }
    let modem = makeModem(connection)

    try await run(modem) {

      let responses = try await modem.readAllLinkDatabase(of: device)

      #expect(responses.map(\.address) == [0x0FFF, 0x0FF7, 0x0FEF])
      #expect(responses.map(\.record.flags.rawValue) == [0xE2, 0xA2, 0x00])
      #expect(responses[1].record.data1 == 0xFE)
      #expect(responses.last?.isEndOfDatabase == true)

    }

    let requested: [UInt16] = [0x0000, 0x0FF7, 0x0FEF]
    #expect(connection.written == requested.map {
      [0x02, 0x62] + AllLinkDatabaseRequest.read(address: $0).message(to: device).bytes
    })

  }

  @Test func waitsForTheReplyAfterTheAcknowledgment() async throws {

    let acknowledgment = received(from: device, .directAcknowledgment, command1: 0x2F, command2: 0x00)
    // A record response before the acknowledgment belongs to an earlier request.
    let early = recordResponse(at: 0x0FF7, [0xA2, 0x05, 0x00, 0x5E, 0x5D, 0xFE, 0x1F, 0x01])
    let current = recordResponse(at: 0x0FFF, [0xE2, 0x04, 0x00, 0x5E, 0x5D, 0x00, 0x00, 0x04])
    let connection = ScriptedConnection { written, _ in written + [0x06] + early + acknowledgment + current }
    let modem = makeModem(connection)

    try await run(modem) {

      let response = try await modem.request(
        AllLinkDatabaseRequest.read(address: 0x0000).message(to: device),
        awaitingReply: { AllLinkRecordResponse($0) }
      )

      #expect(response.address == 0x0FFF)

    }

  }

  @Test func asksForARecordAgainWhenItDoesntArrive() async throws {

    let acknowledgment = received(from: device, .directAcknowledgment, command1: 0x2F, command2: 0x00)
    let end = recordResponse(at: 0x0FFF, [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    // The first record response is lost.
    let connection = ScriptedConnection { written, index in

      let record: [UInt8] = index == 0 ? [] : end

      return written + [0x06] + acknowledgment + record

    }
    let modem = makeModem(connection)

    try await run(modem) {

      async let responses = modem.readAllLinkDatabase(of: device)
      await clock.waitForSleeper(until: Modem.defaultExtendedRequestTimeout)
      clock.advance(by: Modem.defaultExtendedRequestTimeout)

      let read = try await responses

      #expect(read.map(\.address) == [0x0FFF])

    }

    #expect(connection.written.count == 2)

  }

  @Test(.timeLimit(.minutes(1))) func waitsTheRetryDelayBeforeAskingForARecordAgain() async throws {

    let acknowledgment: [UInt8] = received(from: device, .directAcknowledgment, command1: 0x2F, command2: 0x00)
    let end: [UInt8] = recordResponse(at: 0x0FFF, [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    // The first record response is lost.
    let connection = ScriptedConnection { (written: [UInt8], index: Int) -> [UInt8] in

      let record: [UInt8] = index == 0 ? [] : end

      return written + [0x06] + acknowledgment + record

    }
    let modem = Modem(
      connection: connection,
      retryPolicy: RetryPolicy(attempts: 3, delay: .milliseconds(500), answerTimeout: .seconds(2)),
      clock: clock
    )

    try await run(modem) {

      async let responses = modem.readAllLinkDatabase(of: device)
      await clock.waitForSleeper(until: Modem.defaultExtendedRequestTimeout)
      clock.advance(by: Modem.defaultExtendedRequestTimeout)

      // The request is asked for again only once the retry delay has passed.
      await clock.waitForSleeper(until: Modem.defaultExtendedRequestTimeout + .milliseconds(500))
      #expect(connection.written.count == 1)
      clock.advance(by: .milliseconds(500))

      let read: [AllLinkRecordResponse] = try await responses

      #expect(read.map(\.address) == [0x0FFF])

    }

    #expect(connection.written.count == 2)

  }

  @Test func stopsAtTheBottomOfTheDatabasesMemory() async throws {

    let acknowledgment = received(from: device, .directAcknowledgment, command1: 0x2F, command2: 0x00)
    let last = recordResponse(at: 0x0008, [0xA2, 0x01, 0x00, 0x5E, 0x5D, 0xFE, 0x1F, 0x01])
    let connection = ScriptedConnection { written, _ in written + [0x06] + acknowledgment + last }
    let modem = makeModem(connection)

    try await run(modem) {

      let responses = try await modem.readAllLinkDatabase(of: device)

      #expect(responses.map(\.address) == [0x0008])

    }

    // Address 0x0000 would ask for the first record again.
    #expect(connection.written.count == 1)

  }

  @Test func findsEveryModemRecordForAGroupAndDevice() async throws {

    let controller: [UInt8] = [0x02, 0x57, 0xE2, 0x05] + device.bytes + [0x01, 0x20, 0x41]
    let responder: [UInt8] = [0x02, 0x57, 0xA2, 0x05] + device.bytes + [0x00, 0x00, 0x00]
    // The modem NAKs the search once there are no more records, and isn't asked again.
    let connection = ScriptedConnection { written, index in

      switch index {
      case 0: written + [0x06] + controller
      case 1: written + [0x06] + responder
      default: written + [0x15]
      }

    }
    let modem = makeModem(connection)

    try await run(modem) {

      let records = try await modem.allLinkRecords(group: 0x05, device: device)

      #expect(records.map(\.flags.rawValue) == [0xE2, 0xA2])
      #expect(records.first?.data2 == 0x20)

    }

    #expect(connection.written.map { $0[2] } == [0x00, 0x01, 0x01])

  }

  @Test func readsEveryRecordInTheModemsDatabase() async throws {

    let controller: [UInt8] = [0x02, 0x57, 0xE2, 0x05] + device.bytes + [0x01, 0x20, 0x41]
    let responder: [UInt8] = [0x02, 0x57, 0xA2, 0x01] + device.bytes + [0x00, 0x00, 0x00]
    // Get First, then Get Next until the modem NAKs because there are no more records.
    let connection = ScriptedConnection { written, index in

      switch index {
      case 0: written + [0x06] + controller
      case 1: written + [0x06] + responder
      default: written + [0x15]
      }

    }
    let modem = makeModem(connection)

    try await run(modem) {

      let records = try await modem.allLinkRecords()

      #expect(records.map(\.group) == [0x05, 0x01])
      #expect(records.map(\.flags.rawValue) == [0xE2, 0xA2])

    }

    #expect(connection.written == [[0x02, 0x69], [0x02, 0x6A], [0x02, 0x6A]])

  }

  // A NAK without the echo means the modem is busy, so Get Next is sent again rather than
  // ending the scan.
  @Test func asksAgainForTheNextRecordWhileTheModemIsBusy() async throws {

    let record: [UInt8] = [0x02, 0x57, 0xE2, 0x05] + device.bytes + [0x01, 0x20, 0x41]
    let connection = ScriptedConnection { written, index in

      switch index {
      case 0, 2: written + [0x06] + record
      case 1: [0x15]
      default: written + [0x15]
      }

    }
    let modem = makeModem(connection)

    try await run(modem) {

      let records = try await modem.allLinkRecords()

      #expect(records.count == 2)

    }

    #expect(connection.written == [[0x02, 0x69], [0x02, 0x6A], [0x02, 0x6A], [0x02, 0x6A]])

  }

  // The Insteon Developer's Guide: the modem NAKs Get First when its database is empty.
  @Test func readsAnEmptyModemDatabase() async throws {

    let connection = ScriptedConnection { written, _ in written + [0x15] }
    let modem = makeModem(connection)

    try await run(modem) {

      let records = try await modem.allLinkRecords()

      #expect(records.isEmpty)

    }

    #expect(connection.written == [[0x02, 0x69]])

  }


  // MARK: - Group commands

  /// A group member that doesn't acknowledge its cleanup.
  var keypad: InsteonAddress { InsteonAddress(0x00, 0x5E, 0x5D) }

  @Test func reportsEachMembersCleanup() async throws {

    let lamp = device
    let keypad = self.keypad
    let ack = received(from: lamp, .allLinkCleanupAcknowledgment, command1: 0x11, command2: 0x01)
    let failure: [UInt8] = [0x02, 0x56, 0x01, 0x01] + keypad.bytes
    let connection = ScriptedConnection { written, _ in written + [0x06] + ack + failure + [0x02, 0x58, 0x06] }
    let modem = makeModem(connection)

    try await run(modem) {

      let report = try await sendAfterGrace(modem, group: 0x01, command: Command(command1: 0x11, command2: 0xFF))

      #expect(report == AllLinkCleanupReport(acknowledged: [lamp], unacknowledged: [keypad], isComplete: true))

    }

    #expect(connection.written == [[0x02, 0x61, 0x01, 0x11, 0xFF]])

  }

  // The Insteon Developer's Guide: other Insteon traffic stops the cleanups, and the status report
  // says so.
  @Test func reportsCleanupsCutShort() async throws {

    let connection = ScriptedConnection { written, _ in written + [0x06, 0x02, 0x58, 0x15] }
    let modem = makeModem(connection)

    try await run(modem) {

      let report = try await sendAfterGrace(modem, group: 0x01, command: Command(command1: 0x13, command2: 0x00))

      #expect(report == AllLinkCleanupReport(acknowledged: [], unacknowledged: [], isComplete: false))

    }

  }

  // A status report from an earlier group command arrives before this one's echo.
  @Test func ignoresAnEarlierCommandsCleanups() async throws {

    let lamp = device
    let ack = received(from: lamp, .allLinkCleanupAcknowledgment, command1: 0x11, command2: 0x01)
    let connection = ScriptedConnection { written, _ in [0x02, 0x58, 0x15] + written + [0x06] + ack + [0x02, 0x58, 0x06] }
    let modem = makeModem(connection)

    try await run(modem) {

      let report = try await sendAfterGrace(modem, group: 0x01, command: Command(command1: 0x11, command2: 0xFF))

      #expect(report == AllLinkCleanupReport(acknowledged: [lamp], unacknowledged: [], isComplete: true))

    }

  }

  // An i2CS member still searching its database NAKs, then acknowledges once it's done.
  @Test func countsAMemberThatAnswersAfterSearchingItsDatabase() async throws {

    let lamp = device
    let pending = received(from: lamp, .allLinkCleanupNegativeAcknowledgment, command1: 0x11, command2: 0xFC)
    let ack = received(from: lamp, .allLinkCleanupAcknowledgment, command1: 0x11, command2: 0x01)
    let connection = ScriptedConnection { written, _ in written + [0x06] + pending + ack + [0x02, 0x58, 0x06] }
    let modem = makeModem(connection)

    try await run(modem) {

      let report = try await sendAfterGrace(modem, group: 0x01, command: Command(command1: 0x11, command2: 0xFF))

      #expect(report == AllLinkCleanupReport(acknowledged: [lamp], unacknowledged: [], isComplete: true))

    }

  }

  // A cleanup carries its group in cmd2, so an acknowledgment for another group, such as a
  // keypad's own scene heard in monitor mode, isn't counted.
  @Test func countsOnlyThisGroupsCleanups() async throws {

    let lamp = device
    let keypad = self.keypad
    let otherGroup = received(from: keypad, .allLinkCleanupAcknowledgment, command1: 0x11, command2: 0x03)
    let ack = received(from: lamp, .allLinkCleanupAcknowledgment, command1: 0x11, command2: 0x01)
    let failure: [UInt8] = [0x02, 0x56, 0x01, 0x01] + lamp.bytes
    let connection = ScriptedConnection { written, _ in written + [0x06] + otherGroup + ack + failure + [0x02, 0x58, 0x06] }
    let modem = makeModem(connection)

    try await run(modem) {

      let report = try await sendAfterGrace(modem, group: 0x01, command: Command(command1: 0x11, command2: 0xFF))

      // The lamp acknowledged, so a later failure report for it doesn't list it twice.
      #expect(report == AllLinkCleanupReport(acknowledged: [lamp], unacknowledged: [], isComplete: true))

    }

  }

  // A Hub's buffer was seen to hold a frame the parser doesn't know (`02 5C`, its layout inferred
  // from one bench trace as a standard message) between the echo and the cleanup reports.
  @Test func hearsCleanupReportsBehindAFrameItDoesNotKnow() async throws {

    let echo: [UInt8] = [0x02, 0x61, 0x05, 0x13, 0x00, 0x06]
    let unknown: [UInt8] = [0x02, 0x5C, 0xA1, 0xA2, 0xA3, 0xB1, 0xB2, 0xB3, 0x23, 0x13, 0x05]
    let failure: [UInt8] = [0x02, 0x56, 0x05, 0xC1, 0xC2, 0xC3]
    let status: [UInt8] = [0x02, 0x58, 0x06]
    let standard: [UInt8] = [0x02, 0x50, 0xD1, 0xD2, 0xD3, 0xE1, 0xE2, 0xE3, 0x60, 0x13, 0x05]
    let connection = ScriptedConnection { _, _ in echo + unknown + failure + status + standard }
    let modem = makeModem(connection)

    try await run(modem) {

      let report = try await sendAfterGrace(modem, group: 0x05, command: Command(command1: 0x13, command2: 0x00))

      #expect(report.unacknowledged == [InsteonAddress(0xC1, 0xC2, 0xC3)])
      #expect(report.isComplete)
      #expect(report.statusReportAfter != nil)
      #expect(report.failureReportedAfter != nil)

    }

  }

  // The bench Hub 2 sends the failure report as `02 56 <group> <address>`, with no reserved byte, so
  // a parser reading seven bytes took the start byte of the status report that follows.
  @Test func hearsACleanupFailureOfSixBytesAndTheStatusReportAfterIt() async throws {

    let echo: [UInt8] = [0x02, 0x61, 0x05, 0x13, 0x00, 0x06]
    let failure: [UInt8] = [0x02, 0x56, 0x05, 0xC1, 0xC2, 0xC3]
    let status: [UInt8] = [0x02, 0x58, 0x06]
    let connection = ScriptedConnection { _, _ in echo + failure + status }
    let modem = makeModem(connection)

    try await run(modem) {

      let report = try await sendAfterGrace(modem, group: 0x05, command: Command(command1: 0x13, command2: 0x00))

      #expect(report.unacknowledged == [InsteonAddress(0xC1, 0xC2, 0xC3)])
      #expect(report.isComplete)
      #expect(report.statusReportAfter != nil)

    }

  }

  /// Sends an ALL-Link command whose status report comes at once, and lets the grace after the report pass.
  func sendAfterGrace(
    _ modem: Modem,
    group: AllLinkGroupNumber,
    command: Command,
    wait: AllLinkCleanupWait = .standard
  ) async throws -> AllLinkCleanupReport {

    async let report = modem.sendAllLinkCommand(group: group, command: command, wait: wait)
    await clock.waitForSleeper(until: clock.now.offset + wait.grace)
    clock.advance(by: wait.grace)

    return try await report

  }

  // The bench trace (REQ-7) has the status report before the answering member's acknowledgment, all
  // in one buffer read.
  @Test func hearsACleanupAcknowledgmentBehindTheStatusReport() async throws {

    let plug = InsteonAddress(0xD1, 0xD2, 0xD3)
    let silent = InsteonAddress(0xC1, 0xC2, 0xC3)
    let echo: [UInt8] = [0x02, 0x61, 0x05, 0x13, 0x00, 0x06]
    let unknown: [UInt8] = [0x02, 0x5C, 0xA1, 0xA2, 0xA3, 0xB1, 0xB2, 0xB3, 0x23, 0x13, 0x05]
    let failure: [UInt8] = [0x02, 0x56, 0x05] + silent.bytes
    let status: [UInt8] = [0x02, 0x58, 0x06]
    let ack = received(from: plug, .allLinkCleanupAcknowledgment, command1: 0x13, command2: 0x05)
    let connection = ScriptedConnection { _, _ in echo + unknown + failure + status + ack }
    let modem = makeModem(connection)

    try await run(modem) {

      let report = try await sendAfterGrace(modem, group: 0x05, command: Command(command1: 0x13, command2: 0x00))

      #expect(report.acknowledged == [plug])
      #expect(report.unacknowledged == [silent])
      #expect(report.isComplete)

    }

  }

  // The grace is how the wait ends after the status report, whatever else is or isn't coming: the
  // quiet period (10 seconds here) and the cap (40) are far later.
  @Test(arguments: [[], [0x02, 0x50, 0xD1]] as [[UInt8]])
  func endsAtTheGraceAfterAStatusReportWithNothingBehindIt(_ behind: [UInt8]) async throws {

    let silent = InsteonAddress(0xC1, 0xC2, 0xC3)
    let echo: [UInt8] = [0x02, 0x61, 0x05, 0x13, 0x00, 0x06]
    let failure: [UInt8] = [0x02, 0x56, 0x05] + silent.bytes
    let status: [UInt8] = [0x02, 0x58, 0x06]
    let connection = ScriptedConnection { _, _ in echo + failure + status + behind }
    let modem = makeModem(connection)
    let wait = AllLinkCleanupWait(echo: .seconds(5), quietPeriod: .seconds(10), cap: .seconds(40), grace: .milliseconds(500))

    try await run(modem) {

      let result = try await sendAfterGrace(modem, group: 0x05, command: Command(command1: 0x13, command2: 0x00), wait: wait)

      #expect(result.unacknowledged == [silent])
      #expect(result.isComplete)

    }

  }

  // An acknowledgment that comes in a later read, inside the grace, is collected; the grace isn't
  // extended by it, so the run still ends 500 milliseconds after the report.
  @Test func collectsAnAcknowledgmentThatComesInALaterReadInsideTheGrace() async throws {

    let plug = InsteonAddress(0xD1, 0xD2, 0xD3)
    let echo: [UInt8] = [0x02, 0x61, 0x05, 0x13, 0x00, 0x06]
    let status: [UInt8] = [0x02, 0x58, 0x06]
    let ack = received(from: plug, .allLinkCleanupAcknowledgment, command1: 0x13, command2: 0x05)
    let connection = ScriptedConnection { _, _ in echo + status }
    let modem = makeModem(connection)
    let wait = AllLinkCleanupWait(echo: .seconds(5), quietPeriod: .seconds(10), cap: .seconds(40), grace: .milliseconds(500))

    try await run(modem) {

      async let report = modem.sendAllLinkCommand(group: 0x05, command: Command(command1: 0x13, command2: 0x00), wait: wait)
      await clock.waitForSleeper(until: .milliseconds(500))
      clock.advance(by: .milliseconds(400))
      connection.incoming.yield(ack)
      // Lets the acknowledgment reach the wait before the grace ends.
      for _ in 0..<200 { await Task.yield() }
      clock.advance(by: .milliseconds(100))

      let result = try await report

      #expect(result.acknowledged == [plug])
      #expect(result.isComplete)

    }

  }

  // The quiet period started by earlier traffic runs out during the grace, but it is no longer the
  // timer that counts: the report started the grace's own.
  @Test func aQuietPeriodStartedBeforeTheStatusReportDoesNotEndTheGrace() async throws {

    let early = InsteonAddress(0xD1, 0xD2, 0xD3)
    let late = InsteonAddress(0xE1, 0xE2, 0xE3)
    let echo: [UInt8] = [0x02, 0x61, 0x05, 0x13, 0x00, 0x06]
    let earlyAck = received(from: early, .allLinkCleanupAcknowledgment, command1: 0x13, command2: 0x05)
    let lateAck = received(from: late, .allLinkCleanupAcknowledgment, command1: 0x13, command2: 0x05)
    let connection = ScriptedConnection { _, _ in echo + earlyAck }
    let modem = makeModem(connection)
    let wait = AllLinkCleanupWait(echo: .seconds(5), quietPeriod: .seconds(15), cap: .seconds(60), grace: .milliseconds(500))

    try await run(modem) {

      async let report = modem.sendAllLinkCommand(group: 0x05, command: Command(command1: 0x13, command2: 0x00), wait: wait)
      // The traffic at time zero started a quiet period that ends at 15 seconds.
      await clock.waitForSleeper(until: .seconds(15))
      clock.advance(by: .milliseconds(14900))
      connection.incoming.yield([0x02, 0x58, 0x06])
      await clock.waitForSleeper(until: .milliseconds(15400))
      // Past the 15 seconds, inside the grace.
      clock.advance(by: .milliseconds(400))
      connection.incoming.yield(lateAck)
      // Lets the acknowledgment reach the wait before the grace ends.
      for _ in 0..<200 { await Task.yield() }
      clock.advance(by: .milliseconds(100))

      let result = try await report

      #expect(result.acknowledged == [early, late])
      #expect(result.statusReportAfter == .milliseconds(14900))
      #expect(result.isComplete)

    }

  }

  // Once the grace has passed the run is over, so a later acknowledgment isn't in its report.
  @Test func doesNotCollectAnAcknowledgmentAfterTheGrace() async throws {

    let plug = InsteonAddress(0xD1, 0xD2, 0xD3)
    let echo: [UInt8] = [0x02, 0x61, 0x05, 0x13, 0x00, 0x06]
    let status: [UInt8] = [0x02, 0x58, 0x06]
    let ack = received(from: plug, .allLinkCleanupAcknowledgment, command1: 0x13, command2: 0x05)
    let connection = ScriptedConnection { _, _ in echo + status }
    let modem = makeModem(connection)
    let wait = AllLinkCleanupWait(echo: .seconds(5), quietPeriod: .seconds(10), cap: .seconds(40), grace: .milliseconds(500))

    try await run(modem) {

      let result = try await sendAfterGrace(modem, group: 0x05, command: Command(command1: 0x13, command2: 0x00), wait: wait)
      connection.incoming.yield(ack)

      #expect(result.acknowledged.isEmpty)
      #expect(result.isComplete)

    }

  }

  // The modem accepted the command, so it was sent; only the report of the cleanups is missing.
  @Test func givesUpAfterAQuietPeriodWithNoCleanupTrafficAndAnswersWhatItHeard() async throws {

    let connection = ScriptedConnection { written, _ in written + [0x06] }
    let modem = makeModem(connection)

    try await run(modem) {

      async let report = modem.sendAllLinkCommand(group: 0x01, command: Command(command1: 0x11, command2: 0xFF))
      await clock.waitForSleeper(until: AllLinkCleanupWait.standard.quietPeriod)
      clock.advance(by: AllLinkCleanupWait.standard.quietPeriod)

      let result = try await report

      #expect(result == AllLinkCleanupReport(acknowledged: [], unacknowledged: [], isComplete: false))
      #expect(result.statusReportAfter == nil)

    }

  }

  @Test func keepsTheCleanupsThatArrivedWhenTheStatusReportDoesNot() async throws {

    let lamp = device
    let keypad = self.keypad
    let ack = received(from: lamp, .allLinkCleanupAcknowledgment, command1: 0x11, command2: 0x01)
    let failure: [UInt8] = [0x02, 0x56, 0x01, 0x01] + keypad.bytes
    let connection = ScriptedConnection { written, _ in written + [0x06] + ack + failure }
    let modem = makeModem(connection)

    try await run(modem) {

      async let report = modem.sendAllLinkCommand(group: 0x01, command: Command(command1: 0x11, command2: 0xFF))
      // One timer for the start and one for each of the two messages, all ending at the quiet period.
      await clock.waitForSleepers(3, until: AllLinkCleanupWait.standard.quietPeriod)
      clock.advance(by: AllLinkCleanupWait.standard.quietPeriod)

      let result = try await report

      #expect(result == AllLinkCleanupReport(acknowledged: [lamp], unacknowledged: [keypad], isComplete: false))
      #expect(result.failureReportedAfter == .zero)
      #expect(result.statusReportAfter == nil)

    }

  }

  // Cleanup traffic means the modem is still working through its members, so each message starts the quiet period again.
  @Test func eachCleanupMessageStartsTheQuietPeriodAgain() async throws {

    let lamp = device
    let ack = received(from: lamp, .allLinkCleanupAcknowledgment, command1: 0x11, command2: 0x01)
    let connection = ScriptedConnection { written, _ in written + [0x06] }
    let modem = makeModem(connection)
    let wait = AllLinkCleanupWait(echo: .seconds(5), quietPeriod: .seconds(10), cap: .seconds(40))

    try await run(modem) {

      async let report = modem.sendAllLinkCommand(group: 0x01, command: Command(command1: 0x11, command2: 0xFF), wait: wait)
      await clock.waitForSleeper(until: .seconds(10))
      clock.advance(by: .seconds(8))
      connection.incoming.yield(ack)
      // Without the message the wait would have ended at 10 seconds.
      await clock.waitForSleeper(until: .seconds(18))
      clock.advance(by: .seconds(10))

      let result = try await report

      #expect(result == AllLinkCleanupReport(acknowledged: [lamp], unacknowledged: [], isComplete: false))

    }

  }

  // A frame the modem layer can't name is neither cleanup traffic nor device traffic, so it doesn't
  // start the quiet period again; only the cleanup frames do.
  @Test func anUnrecognizedFrameDoesNotStartTheQuietPeriodAgain() async throws {

    let unknown: [UInt8] = [0x02, 0x5C, 0xA1, 0xA2, 0xA3, 0xB1, 0xB2, 0xB3, 0x23, 0x13, 0x05]
    let connection = ScriptedConnection { written, _ in written + [0x06] }
    let modem = makeModem(connection)
    let wait = AllLinkCleanupWait(echo: .seconds(5), quietPeriod: .seconds(10), cap: .seconds(40))

    try await run(modem) {

      async let report = modem.sendAllLinkCommand(group: 0x01, command: Command(command1: 0x11, command2: 0xFF), wait: wait)
      await clock.waitForSleeper(until: .seconds(10))
      clock.advance(by: .seconds(8))
      connection.incoming.yield(unknown)
      // Had the frame started the quiet period again, the wait would end at 18 seconds, not 10.
      clock.advance(by: .seconds(2))

      let result = try await report

      #expect(result == AllLinkCleanupReport(acknowledged: [], unacknowledged: [], isComplete: false))

    }

  }

  @Test func trafficExtendsTheWaitOnlyUpToTheCap() async throws {

    let lamp = device
    let ack = received(from: lamp, .allLinkCleanupAcknowledgment, command1: 0x11, command2: 0x01)
    let connection = ScriptedConnection { written, _ in written + [0x06] }
    let modem = makeModem(connection)
    let wait = AllLinkCleanupWait(echo: .seconds(5), quietPeriod: .seconds(10), cap: .seconds(22))

    try await run(modem) {

      async let report = modem.sendAllLinkCommand(group: 0x01, command: Command(command1: 0x11, command2: 0xFF), wait: wait)
      await clock.waitForSleeper(until: .seconds(10))
      clock.advance(by: .seconds(8))
      connection.incoming.yield(ack)
      await clock.waitForSleeper(until: .seconds(18))
      clock.advance(by: .seconds(8))
      connection.incoming.yield(ack)
      // A third quiet period would end at 26 seconds; the cap ends it at 22.
      await clock.waitForSleeper(until: .seconds(22))
      clock.advance(by: .seconds(6))

      let result = try await report

      #expect(result == AllLinkCleanupReport(acknowledged: [lamp], unacknowledged: [], isComplete: false))

    }

  }

  // A Hub brings the modem's reports over polling, so the status report can come well after the echo.
  @Test func aStatusReportThatComesLongAfterTheEchoIsCompleteAndSaysHowLongItTook() async throws {

    let lamp = device
    let ack = received(from: lamp, .allLinkCleanupAcknowledgment, command1: 0x11, command2: 0x01)
    let connection = ScriptedConnection { written, _ in written + [0x06] }
    let modem = makeModem(connection)

    try await run(modem) {

      async let report = modem.sendAllLinkCommand(group: 0x01, command: Command(command1: 0x11, command2: 0xFF))
      await clock.waitForSleeper(until: .seconds(15))
      clock.advance(by: .seconds(10))
      connection.incoming.yield(ack)
      await clock.waitForSleeper(until: .seconds(25))
      clock.advance(by: .seconds(10))
      connection.incoming.yield(ack)
      // Each message made the wait longer, so it is still open at 25 seconds.
      await clock.waitForSleeper(until: .seconds(35))
      clock.advance(by: .seconds(5))
      connection.incoming.yield([0x02, 0x58, 0x06])
      await clock.waitForSleeper(until: .milliseconds(25500))
      clock.advance(by: .milliseconds(500))

      let result = try await report

      #expect(result == AllLinkCleanupReport(acknowledged: [lamp], unacknowledged: [], isComplete: true))
      #expect(result.statusReportAfter == .seconds(25))

    }

  }

  // Without the echo the command may not have reached the modem, and what happened is unknown.
  @Test func throwsTimedOutWhenTheModemNeverEchoesTheCommand() async throws {

    let connection = ScriptedConnection { _, _ in [] }
    let modem = makeModem(connection)

    try await run(modem) {

      await #expect(throws: ModemError.timedOut(.sendAllLinkCommand)) {

        async let report = modem.sendAllLinkCommand(group: 0x01, command: Command(command1: 0x11, command2: 0xFF))
        await clock.waitForSleeper(until: AllLinkCleanupWait.standard.echo)
        clock.advance(by: AllLinkCleanupWait.standard.echo)
        _ = try await report

      }

    }

  }

  @Test func theEchoWaitIsTheOneTheCallerChose() async throws {

    let connection = ScriptedConnection { _, _ in [] }
    let modem = makeModem(connection)
    let wait = AllLinkCleanupWait(echo: .seconds(9), quietPeriod: .seconds(10), cap: .seconds(40))

    try await run(modem) {

      await #expect(throws: ModemError.timedOut(.sendAllLinkCommand)) {

        async let report = modem.sendAllLinkCommand(group: 0x01, command: Command(command1: 0x11, command2: 0xFF), wait: wait)
        await clock.waitForSleeper(until: .seconds(9))
        clock.advance(by: .seconds(9))
        _ = try await report

      }

    }

  }

  // A message makes the earlier quiet-period timer pointless, so it is canceled before the next one starts.
  @Test func aCleanupMessageCancelsTheTimerItReplaces() async throws {

    let lamp = device
    let ack = received(from: lamp, .allLinkCleanupAcknowledgment, command1: 0x11, command2: 0x01)
    let connection = ScriptedConnection { written, _ in written + [0x06] }
    let modem = makeModem(connection)
    let wait = AllLinkCleanupWait(echo: .seconds(5), quietPeriod: .seconds(10), cap: .seconds(40))

    try await run(modem) {

      async let report = modem.sendAllLinkCommand(group: 0x01, command: Command(command1: 0x11, command2: 0xFF), wait: wait)
      await clock.waitForSleeper(until: .seconds(10))
      clock.advance(by: .seconds(8))
      connection.incoming.yield(ack)
      await clock.waitForSleeper(until: .seconds(18))

      // The 10 second timer is canceled by the message, which takes a few turns of the executor.
      var turns = 0

      while clock.sleeperCount(until: .seconds(10)) > 0 && turns < 10_000 {

        await Task.yield()
        turns += 1

      }

      #expect(clock.sleeperCount(until: .seconds(10)) == 0)
      #expect(clock.sleeperCount(until: .seconds(18)) == 1)

      clock.advance(by: .seconds(10))
      _ = try await report

    }

  }

  // The times come from the clock read when the modem accepted the command, not from the time before it.
  @Test func theReportTimesStartWhenTheModemAcceptedTheCommand() async throws {

    let lamp = device
    let ack = received(from: lamp, .allLinkCleanupAcknowledgment, command1: 0x11, command2: 0x01)
    let connection = ScriptedConnection { _, _ in [] }
    let modem = makeModem(connection)

    try await run(modem) {

      // Forty seconds pass before the command is sent at all, and three more before the modem echoes it.
      clock.advance(by: .seconds(40))
      async let report = modem.sendAllLinkCommand(group: 0x01, command: Command(command1: 0x11, command2: 0xFF))
      await clock.waitForSleeper(until: .seconds(45))
      clock.advance(by: .seconds(3))
      connection.incoming.yield([0x02, 0x61, 0x01, 0x11, 0xFF, 0x06])
      await clock.waitForSleeper(until: .seconds(58))
      clock.advance(by: .seconds(4))
      connection.incoming.yield(ack + [0x02, 0x58, 0x06])
      await clock.waitForSleeper(until: .milliseconds(47500))
      clock.advance(by: .milliseconds(500))

      let result = try await report

      #expect(result.statusReportAfter == .seconds(4))
      #expect(result.isComplete)

    }

  }

}
