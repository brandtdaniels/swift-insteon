import Testing
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// The bytes written come from the worked examples in the INSTEON Developer's Guide, chapter 9.
/// Like ``ModemTests``, every test runs on a ``TestClock``.
struct PowerLincControllerTests {

  let clock = TestClock()

  let policy = Modem.RetryPolicy(attempts: 3, delay: .zero, echoTimeout: .seconds(2))

  func makeController(_ connection: ScriptedConnection) -> PowerLincController {

    PowerLincController(connection: connection, retryPolicy: policy, clock: clock)

  }

  /// Runs `body` while `controller` reads from its connection, then stops the controller.
  func run(_ controller: PowerLincController, _ body: () async throws -> Void) async throws {

    try await withThrowingTaskGroup(of: Void.self) { group in

      group.addTask { try await controller.run() }
      defer { group.cancelAll() }

      try await body()

      group.cancelAll()

      // The group would otherwise discard an error from run().
      try await group.waitForAll()

    }

  }

  /// Answers a command the way IBIOS does.
  static func answer(_ frame: [UInt8]) -> [UInt8] {

    SimulatedIBIOS().answer(frame)

  }

  @Test func sendsAStandardMessageAsTheGuideDoes() async throws {

    let ibios = SimulatedIBIOS()
    let connection = ScriptedConnection { frame, _ in ibios.answer(frame) }
    let controller = makeController(connection)
    let lamp = InsteonAddress(0x00, 0x02, 0xAC)

    try await run(controller) {

      try await controller.send(.sendStandardMessage(StandardMessage(to: lamp, command: StandardDirectCommand.on(level: 0xFF))))

    }

    #expect(connection.written == [
      Self.bytes("024001A40006FD880002AC0F11FF"),
      Self.bytes("024401A40006"),
      Self.bytes("0246014210FF")
    ])

  }

  @Test func sendsX10AsTheGuideDoes() async throws {

    let ibios = SimulatedIBIOS()
    let connection = ScriptedConnection { frame, _ in ibios.answer(frame) }
    let controller = makeController(connection)

    try await run(controller) {

      try await controller.send(.sendX10(.unit(.a, .one)))
      try await controller.send(.sendX10(.command(.a, .on)))

    }

    #expect(connection.written == [
      Self.bytes("024001650001FF3366"),
      Self.bytes("024401650001"),
      Self.bytes("0246016680F7"),
      Self.bytes("024001650001FF3762"),
      Self.bytes("024401650001"),
      Self.bytes("0246016688FF")
    ])

  }

  @Test func answersGetModemInfoWithItsVersion() async throws {

    let ibios = SimulatedIBIOS()
    let connection = ScriptedConnection { frame, _ in ibios.answer(frame) }
    let controller = makeController(connection)
    var replies = await controller.replies().makeAsyncIterator()

    try await run(controller) {

      try await controller.send(.getModemInfo)

    }

    #expect(connection.written == [[0x02, 0x48]])
    #expect(await replies.next() == .version(ModemInfo(
      address: InsteonAddress(0x1A, 0x2B, 0x3C),
      category: 0x03,
      subcategory: 0x02,
      firmwareVersion: 0xFF
    )))

  }

  @Test(arguments: [
    SerialCommand.beep,
    .getFirstAllLinkRecord,
    .sendExtendedMessage(ExtendedMessage(to: InsteonAddress(0x00, 0x02, 0xAC), command: ExtendedDirectCommand.getSet))
  ])
  func rejectsCommandsItCantCarry(_ command: SerialCommand) async throws {

    let ibios = SimulatedIBIOS()
    let connection = ScriptedConnection { frame, _ in ibios.answer(frame) }
    let controller = makeController(connection)

    await #expect(throws: PowerLincControllerError.unsupported(command)) {

      try await controller.send(command)

    }

    #expect(connection.written.isEmpty)

  }

  @Test func retriesAfterANak() async throws {

    let ibios = SimulatedIBIOS()
    let connection = ScriptedConnection { frame, index in index == 0 ? [0x15] : ibios.answer(frame) }
    let controller = makeController(connection)

    try await run(controller) {

      try await controller.send(.sendX10(.unit(.a, .one)))

    }

    #expect(connection.written == [
      Self.bytes("024001650001FF3366"),
      Self.bytes("024001650001FF3366"),
      Self.bytes("024401650001"),
      Self.bytes("0246016680F7")
    ])

  }

  @Test func throwsWhenEveryAttemptIsRejected() async throws {

    let connection = ScriptedConnection { frame, _ in Array(frame.prefix(6)) + [0x15] }
    let controller = makeController(connection)
    let command = IBIOSCommand.download(address: 0x0165, data: [0x66])

    try await run(controller) {

      await #expect(throws: PowerLincControllerError.rejected(command)) {

        try await controller.send(command)

      }

    }

    #expect(connection.written.count == 3)

  }

  @Test func doesntSendADownloadThatDoesntReadBack() async throws {

    // The controller acknowledges the download, but its memory reads back with the wrong checksum.
    let connection = ScriptedConnection { frame, _ in

      frame[1] == 0x44 ? frame + [0x00, 0x00, 0x06] : SimulatedIBIOS().answer(frame)

    }
    let controller = makeController(connection)

    try await run(controller) {

      await #expect(throws: PowerLincControllerError.unconfirmedDownload(address: 0x0165)) {

        try await controller.send(.sendX10(.unit(.a, .one)))

      }

    }

    // The checksum is read once per attempt, and the flag that would send the byte is never set.
    #expect(connection.written == [Self.bytes("024001650001FF3366")] + Array(repeating: Self.bytes("024401650001"), count: 3))

  }

  @Test func readsDamagedMemoryAgain() async throws {

    let ibios = SimulatedIBIOS()
    let connection = ScriptedConnection { frame, index in

      // The first upload arrives with a checksum that doesn't match its data.
      index == 0 ? Self.bytes("02420300000400000000" + "0000" + "06") : ibios.answer(frame)

    }
    let controller = makeController(connection)
    let command = IBIOSCommand.upload(address: 0x0300, length: 4)

    try await run(controller) {

      try await controller.send(command)

    }

    #expect(connection.written == [command.bytes, command.bytes])

  }

  @Test func timesOutWithoutAnAnswer() async throws {

    let connection = ScriptedConnection { _, _ in [] }
    let controller = makeController(connection)

    try await run(controller) {

      await #expect(throws: PowerLincControllerError.timedOut(.getVersion)) {

        async let sent: Void = controller.send(IBIOSCommand.getVersion)
        await clock.waitForSleeper(until: .seconds(2))
        clock.advance(by: .seconds(2))
        try await sent

      }

    }

  }

  @Test func theNextSendWaitsForACanceledCommandsAnswer() async throws {

    let connection = ScriptedConnection { _, _ in [] }
    let controller = makeController(connection)

    try await run(controller) {

      var writes = connection.writeLog.makeAsyncIterator()

      await withThrowingTaskGroup(of: Void.self) { group in

        group.addTask { try await controller.send(IBIOSCommand.getVersion) }
        _ = await writes.next()
        group.cancelAll()
        _ = try? await group.next()

      }

      // The canceled command was written, so the next one waits for the controller to answer it.
      async let next: Void = controller.send(IBIOSCommand.mask(address: 0x0142, or: 0x10, and: 0xFF))
      await clock.waitForSleeper(until: .seconds(2))
      #expect(connection.written == [Self.bytes("0248")])

      connection.incoming.yield(Self.answer(Self.bytes("0248")))
      let frame = try #require(await writes.next())
      connection.incoming.yield(Self.answer(frame))
      try await next

    }

    #expect(connection.written == [Self.bytes("0248"), Self.bytes("0246014210FF")])

  }

  @Test func publishesMessagesItsProgramReports() async throws {

    let report = Self.bytes("024F01" + "0002AC" + "1A2B3C" + "2B" + "11FF")
    let connection = ScriptedConnection { frame, _ in Self.answer(frame) + report }
    let controller = makeController(connection)
    var replies = await controller.replies().makeAsyncIterator()

    try await run(controller) {

      try await controller.send(.getModemInfo)

    }

    _ = await replies.next()
    #expect(await replies.next() == .messageReceived(.messageForMe, message: ReceivedMessage(
      sender: InsteonAddress(0x00, 0x02, 0xAC),
      destination: InsteonAddress(0x1A, 0x2B, 0x3C),
      flags: MessageFlags(rawValue: 0x2B),
      command: Command(command1: 0x11, command2: 0xFF)
    )))

  }

  static func bytes(_ hex: String) -> [UInt8] {

    let digits = Array(hex)

    return stride(from: 0, to: digits.count, by: 2).map { UInt8(String(digits[$0..<$0 + 2]), radix: 16)! }

  }

}

/// A PowerLinc Controller's memory, answering commands the way IBIOS does.
///
/// `ScriptedConnection` calls it under its lock, one frame at a time.
final class SimulatedIBIOS {

  private var memory = [UInt8](repeating: 0, count: 0x1_0000)

  /// Answers a command frame.
  func answer(_ frame: [UInt8]) -> [UInt8] {

    switch frame[1] {
    case 0x40:
      let address = Self.word(frame, at: 2)
      let data = Array(frame.dropFirst(8))
      memory.replaceSubrange(address..<address + data.count, with: data)

      // A download's echo repeats only its address and length.
      return Array(frame.prefix(6)) + [0x06]
    case 0x42:
      let address = Self.word(frame, at: 2)
      let data = Array(memory[address..<address + Self.word(frame, at: 4)])
      let checksum = IBIOSCommand.checksum(of: Array(frame[2..<6]) + data)

      return frame + data + [UInt8(checksum >> 8), UInt8(checksum & 0xFF), 0x06]
    case 0x44:
      let address = Self.word(frame, at: 2)
      let checksum = IBIOSCommand.checksum(of: memory[address..<address + Self.word(frame, at: 4)])

      return frame + [UInt8(checksum >> 8), UInt8(checksum & 0xFF), 0x06]
    case 0x48:
      return PowerLincControllerTests.bytes("0248" + "1A2B3C" + "0302" + "FF" + "06")
    default:
      return frame + [0x06]
    }

  }

  private static func word(_ frame: [UInt8], at index: Int) -> Int {

    Int(frame[index]) << 8 | Int(frame[index + 1])

  }

}
