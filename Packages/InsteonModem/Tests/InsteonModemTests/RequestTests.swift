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

  /// An ALL-Link Record Response from `device` for the record at `address`, as `0x51` bytes.
  func recordResponse(at address: UInt16, _ record: [UInt8]) -> [UInt8] {

    let flags = MessageFlags(messageType: .direct, isExtended: true, maxHops: .three, hopsLeft: .two)
    let header: [UInt8] = [0x02, 0x51] + device.bytes + modemAddress.bytes
    let command: [UInt8] = [flags.rawValue, 0x2F, 0x00]
    let userData: [UInt8] = [0x00, 0x01, UInt8(address >> 8), UInt8(address & 0xFF), 0x00] + record + [0x00]

    return header + command + userData

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

  // The guide's time for five retries of an extended message, 3.17 seconds, plus a second for
  // the modem's echo.
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

  @Test func readsEveryRecordUntilTheEndOfTheDatabase() async throws {

    let acknowledgement = received(from: device, .directAcknowledgement, command1: 0x2F, command2: 0x00)
    let records: [[UInt8]] = [
      recordResponse(at: 0x0FFF, [0xE2, 0x04, 0x00, 0x5E, 0x5D, 0x00, 0x00, 0x04]),
      recordResponse(at: 0x0FF7, [0xA2, 0x05, 0x00, 0x5E, 0x5D, 0xFE, 0x1F, 0x01]),
      recordResponse(at: 0x0FEF, [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
    ]
    let connection = ScriptedConnection { written, index in written + [0x06] + acknowledgement + records[index] }
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

  @Test func waitsForTheReplyAfterTheAcknowledgement() async throws {

    let acknowledgement = received(from: device, .directAcknowledgement, command1: 0x2F, command2: 0x00)
    // A record response before the acknowledgement belongs to an earlier request.
    let early = recordResponse(at: 0x0FF7, [0xA2, 0x05, 0x00, 0x5E, 0x5D, 0xFE, 0x1F, 0x01])
    let current = recordResponse(at: 0x0FFF, [0xE2, 0x04, 0x00, 0x5E, 0x5D, 0x00, 0x00, 0x04])
    let connection = ScriptedConnection { written, _ in written + [0x06] + early + acknowledgement + current }
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

    let acknowledgement = received(from: device, .directAcknowledgement, command1: 0x2F, command2: 0x00)
    let end = recordResponse(at: 0x0FFF, [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    // The first record response is lost.
    let connection = ScriptedConnection { written, index in

      let record: [UInt8] = index == 0 ? [] : end

      return written + [0x06] + acknowledgement + record

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

  @Test func stopsAtTheBottomOfTheDatabasesMemory() async throws {

    let acknowledgement = received(from: device, .directAcknowledgement, command1: 0x2F, command2: 0x00)
    let last = recordResponse(at: 0x0008, [0xA2, 0x01, 0x00, 0x5E, 0x5D, 0xFE, 0x1F, 0x01])
    let connection = ScriptedConnection { written, _ in written + [0x06] + acknowledgement + last }
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

  // The guide: the modem NAKs Get First when its database is empty.
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
    let ack = received(from: lamp, .allLinkCleanupAcknowledgement, command1: 0x11, command2: 0x01)
    let failure: [UInt8] = [0x02, 0x56, 0x01, 0x01] + keypad.bytes
    let connection = ScriptedConnection { written, _ in written + [0x06] + ack + failure + [0x02, 0x58, 0x06] }
    let modem = makeModem(connection)

    try await run(modem) {

      let report = try await modem.sendAllLinkCommand(group: 0x01, command: Command(command1: 0x11, command2: 0xFF))

      #expect(report == AllLinkCleanupReport(acknowledged: [lamp], unacknowledged: [keypad], isComplete: true))

    }

    #expect(connection.written == [[0x02, 0x61, 0x01, 0x11, 0xFF]])

  }

  // The guide: other INSTEON traffic stops the cleanups, and the status report says so.
  @Test func reportsCleanupsCutShort() async throws {

    let connection = ScriptedConnection { written, _ in written + [0x06, 0x02, 0x58, 0x15] }
    let modem = makeModem(connection)

    try await run(modem) {

      let report = try await modem.sendAllLinkCommand(group: 0x01, command: Command(command1: 0x13, command2: 0x00))

      #expect(report == AllLinkCleanupReport(acknowledged: [], unacknowledged: [], isComplete: false))

    }

  }

  // A status report from an earlier group command arrives before this one's echo.
  @Test func ignoresAnEarlierCommandsCleanups() async throws {

    let lamp = device
    let ack = received(from: lamp, .allLinkCleanupAcknowledgement, command1: 0x11, command2: 0x01)
    let connection = ScriptedConnection { written, _ in [0x02, 0x58, 0x15] + written + [0x06] + ack + [0x02, 0x58, 0x06] }
    let modem = makeModem(connection)

    try await run(modem) {

      let report = try await modem.sendAllLinkCommand(group: 0x01, command: Command(command1: 0x11, command2: 0xFF))

      #expect(report == AllLinkCleanupReport(acknowledged: [lamp], unacknowledged: [], isComplete: true))

    }

  }

  // An i2cs member still searching its database NAKs, then acknowledges once it's done.
  @Test func countsAMemberThatAnswersAfterSearchingItsDatabase() async throws {

    let lamp = device
    let pending = received(from: lamp, .allLinkCleanupNegativeAcknowledgement, command1: 0x11, command2: 0xFC)
    let ack = received(from: lamp, .allLinkCleanupAcknowledgement, command1: 0x11, command2: 0x01)
    let connection = ScriptedConnection { written, _ in written + [0x06] + pending + ack + [0x02, 0x58, 0x06] }
    let modem = makeModem(connection)

    try await run(modem) {

      let report = try await modem.sendAllLinkCommand(group: 0x01, command: Command(command1: 0x11, command2: 0xFF))

      #expect(report == AllLinkCleanupReport(acknowledged: [lamp], unacknowledged: [], isComplete: true))

    }

  }

  // A cleanup carries its group in cmd2, so an acknowledgement for another group, such as a
  // keypad's own scene heard in monitor mode, isn't counted.
  @Test func countsOnlyThisGroupsCleanups() async throws {

    let lamp = device
    let keypad = self.keypad
    let otherGroup = received(from: keypad, .allLinkCleanupAcknowledgement, command1: 0x11, command2: 0x03)
    let ack = received(from: lamp, .allLinkCleanupAcknowledgement, command1: 0x11, command2: 0x01)
    let failure: [UInt8] = [0x02, 0x56, 0x01, 0x01] + lamp.bytes
    let connection = ScriptedConnection { written, _ in written + [0x06] + otherGroup + ack + failure + [0x02, 0x58, 0x06] }
    let modem = makeModem(connection)

    try await run(modem) {

      let report = try await modem.sendAllLinkCommand(group: 0x01, command: Command(command1: 0x11, command2: 0xFF))

      // The lamp acknowledged, so a later failure report for it doesn't list it twice.
      #expect(report == AllLinkCleanupReport(acknowledged: [lamp], unacknowledged: [], isComplete: true))

    }

  }

  @Test func waitsForTheCleanupsUpToTheTimeout() async throws {

    let connection = ScriptedConnection { written, _ in written + [0x06] }
    let modem = makeModem(connection)

    try await run(modem) {

      await #expect(throws: ModemError.timedOut(.sendAllLinkCommand)) {

        async let report = modem.sendAllLinkCommand(group: 0x01, command: Command(command1: 0x11, command2: 0xFF))
        await clock.waitForSleeper(until: Modem.defaultAllLinkCommandTimeout)
        clock.advance(by: Modem.defaultAllLinkCommandTimeout)
        _ = try await report

      }

    }

  }

}
