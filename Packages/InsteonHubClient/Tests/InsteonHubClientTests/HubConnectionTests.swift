import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import InsteonHubClient
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// Polling runs on a ``TestClock`` that only moves when a test advances it, and each test waits
/// on a write, a reply or a sleeping poll rather than on elapsed time, so results never depend
/// on speed. Polling happens only while a stream is read, so each test reads the stream it
/// expects bytes from.
@Suite(.timeLimit(.minutes(1)))
struct HubConnectionTests {

  let clock = TestClock()

  let endpoint = HubEndpoint(host: "hub.local")

  func makeConnection(_ fake: FakeHub) -> HubConnection {

    HubConnection(hub: Hub(endpoint: endpoint, httpClient: fake), clock: clock)

  }

  /// Waits for the first poll to finish, then lets one more happen.
  func pollAgain() async {

    await clock.waitForSleeper(until: HubConnection.defaultPollInterval)
    clock.advance(by: HubConnection.defaultPollInterval)

  }

  /// Reads the first chunk of a stream.
  static func firstChunk(of stream: AsyncThrowingStream<[UInt8], any Error>) async throws -> [UInt8]? {

    try await stream.first { _ in true }

  }

  @Test func firstRequestClearsTheBuffer() async throws {

    let fake = FakeHub()

    try await makeConnection(fake).write([0x02, 0x77])

    // The buffer is read before the write, since writing starts it over.
    #expect(await fake.requests == ["GET /1", "GET /buffstatus.xml", "GET /3"])

  }

  @Test func receivesTheReplyToAWrite() async throws {

    let fake = FakeHub()
    let connection = makeConnection(fake)

    try await connection.write([0x02, 0x60])

    #expect(try await Self.firstChunk(of: connection.receive()) == [0x02, 0x60, 0x06])

  }

  @Test func ignoresRepliesFromBeforeTheConnection() async throws {

    let fake = FakeHub()
    await fake.deliver([0x02, 0x77, 0x06])
    let connection = makeConnection(fake)
    let message: [UInt8] = [0x02, 0x50, 0xAA, 0xBB, 0xCC, 0x11, 0x22, 0x33, 0x2B, 0x11, 0xFF]

    // The first poll clears the buffer and finds nothing, then waits for the next one.
    async let received = Self.firstChunk(of: connection.receive())
    await clock.waitForSleeper(until: HubConnection.defaultPollInterval)
    await fake.deliver(message)
    clock.advance(by: HubConnection.defaultPollInterval)

    #expect(try await received == message)

  }

  @Test func collapsesARunOfNaksToOne() async throws {

    let fake = FakeHub { _ in [UInt8](repeating: 0x15, count: 20) }
    let connection = makeConnection(fake)

    try await connection.write([0x02, 0x6D])

    #expect(try await Self.firstChunk(of: connection.receive()) == [0x15])

  }

  @Test func keepsBytesThatArriveBeforeAWrite() async throws {

    let fake = FakeHub()
    let connection = makeConnection(fake)
    let message: [UInt8] = [0x02, 0x50, 0xAA, 0xBB, 0xCC, 0x11, 0x22, 0x33, 0x2B, 0x11, 0xFF]

    // A device's message arrives after one command's echo and before the next command starts
    // the buffer over.
    try await connection.write([0x02, 0x77])
    await fake.deliver(message)
    try await connection.write([0x02, 0x6D])

    #expect(try await Self.firstChunk(of: connection.receive()) == [0x02, 0x77, 0x06] + message + [0x02, 0x6D, 0x06])

  }

  @Test func deliversBytesAWriteReadsWhileTheStreamWaits() async throws {

    let fake = FakeHub()
    let connection = makeConnection(fake)
    let message: [UInt8] = [0x02, 0x50, 0xAA, 0xBB, 0xCC, 0x11, 0x22, 0x33, 0x2B, 0x11, 0xFF]

    // A device's message arrives while the stream waits between polls, and a write starts the
    // buffer over before the next poll.
    async let received = Self.firstChunk(of: connection.receive())
    await clock.waitForSleeper(until: HubConnection.defaultPollInterval)
    await fake.deliver(message)
    try await connection.write([0x02, 0x6D])
    clock.advance(by: HubConnection.defaultPollInterval)

    #expect(try await received == message + [0x02, 0x6D, 0x06])

  }

  @Test func retriesAFailedPoll() async throws {

    let fake = FakeHub(failingReads: 1)
    let connection = makeConnection(fake)
    let message: [UInt8] = [0x02, 0x50, 0xAA, 0xBB, 0xCC, 0x11, 0x22, 0x33, 0x2B, 0x11, 0xFF]

    async let received = Self.firstChunk(of: connection.receive())
    await clock.waitForSleeper(until: HubConnection.defaultPollInterval)
    await fake.deliver(message)
    clock.advance(by: HubConnection.defaultPollInterval)

    #expect(try await received == message)

  }

  @Test func failsAfterTooManyFailedPolls() async {

    let connection = makeConnection(FakeHub(failingReads: HubConnection.defaultFailureLimit))
    let received = connection.receive()

    await #expect(throws: (any Error).self) {

      async let drained: Void = Self.drain(received)

      for poll in 1..<HubConnection.defaultFailureLimit {

        await clock.waitForSleeper(until: HubConnection.defaultPollInterval * poll)
        clock.advance(by: HubConnection.defaultPollInterval)

      }

      try await drained

    }

  }

  static func drain(_ stream: AsyncThrowingStream<[UInt8], any Error>) async throws {

    for try await _ in stream {}

  }

  @Test func aHubThatNeverAnswersFailsWithTheClientsError() async {

    let connection = makeConnection(FakeHub(isUnreachable: true))

    let error = await #expect(throws: URLError.self) {

      try await connection.write([0x02, 0x60])

    }

    #expect(error?.code == .timedOut)

  }

  @Test func aWriteTheHubDoesntAnswerAfterAnEarlierExchangeFailsWithHubStoppedAnswering() async throws {

    let fake = FakeHub()
    let connection = makeConnection(fake)

    try await connection.write([0x02, 0x60])
    await fake.failNextWrites(1)

    let error = await #expect(throws: HubStoppedAnswering.self) {

      try await connection.write([0x02, 0x62, 0x4D, 0x5E, 0x6F, 0x0F, 0x0D, 0x00])

    }

    #expect((error?.underlyingError as? URLError)?.code == .timedOut)

  }

  @Test func pollsTheHubDoesntAnswerAfterAnEarlierExchangeFailWithHubStoppedAnswering() async throws {

    let fake = FakeHub()
    let connection = makeConnection(fake)

    try await connection.write([0x02, 0x60])
    await fake.failNextReads(HubConnection.defaultFailureLimit)
    let received = connection.receive()

    let error = await #expect(throws: HubStoppedAnswering.self) {

      async let drained: Void = Self.drain(received)

      for poll in 1..<HubConnection.defaultFailureLimit {

        await clock.waitForSleeper(until: HubConnection.defaultPollInterval * poll)
        clock.advance(by: HubConnection.defaultPollInterval)

      }

      try await drained

    }

    #expect((error?.underlyingError as? URLError)?.code == .timedOut)

  }

  /// The Hub answers one exchange, then times out every poll while the modem waits for a
  /// device's acknowledgment, so the request fails with the Hub's error before its own timeout.
  @Test func aDeviceRequestTheHubStopsPollingForFailsWithHubStoppedAnswering() async throws {

    let modemInfo: [UInt8] = [0x02, 0x60, 0x1A, 0x2B, 0x3C, 0x03, 0x37, 0x9C, 0x06]
    let fake = FakeHub { (command: [UInt8]) -> [UInt8] in command == [0x02, 0x60] ? modemInfo : command + [0x06] }
    let modem = Modem(connection: makeConnection(fake), clock: clock)
    let device = InsteonAddress(0x4D, 0x5E, 0x6F)
    let pollInterval: Duration = HubConnection.defaultPollInterval

    try await withThrowingTaskGroup(of: Void.self) { group in

      group.addTask { try await modem.run() }

      var writes = fake.writes.makeAsyncIterator()

      async let sent: Void = modem.send(.getModemInfo)
      #expect(await writes.next() == [0x02, 0x60])
      await pollAgain()
      try await sent

      // Once the stream waits for the poll after the one that read the reply, every read
      // times out.
      await clock.waitForSleeper(until: pollInterval * 2)
      await fake.failNextReads(100)

      let request = Task { () async throws -> ReceivedMessage in

        try await modem.request(StandardMessage(to: device, command: Command(command1: 0x0D, command2: 0x00)))

      }

      #expect(await writes.next() == [0x02, 0x62, 0x4D, 0x5E, 0x6F, 0x0F, 0x0D, 0x00])

      // The clock stops short of the request's 3-second timeout.
      for poll in 0..<HubConnection.defaultFailureLimit {

        await clock.waitForSleeper(until: pollInterval * (2 + poll))
        clock.advance(by: pollInterval)

      }

      let error = await #expect(throws: HubStoppedAnswering.self) {

        try await request.value

      }

      #expect((error?.underlyingError as? URLError)?.code == .timedOut)

      group.cancelAll()

    }

  }

  @Test func streamFailsWhenTheHubRejectsARequest() async {

    let connection = makeConnection(FakeHub(status: 401))

    await #expect(throws: HubError.unexpectedStatus(401)) {

      for try await _ in connection.receive() {}

    }

  }

  @Test func aNewStreamFinishesThePreviousOne() async throws {

    let connection = makeConnection(FakeHub())
    let first = connection.receive()
    _ = connection.receive()

    for try await _ in first {}

  }

  @Test func cancelingTheReaderFinishesTheStream() async throws {

    let connection = makeConnection(FakeHub())

    try await withThrowingTaskGroup(of: Void.self) { group in

      group.addTask { for try await _ in connection.receive() {} }

      // Cancel once the stream is waiting between polls.
      await clock.waitForSleeper(until: HubConnection.defaultPollInterval)
      group.cancelAll()

      try await group.waitForAll()

    }

  }

  @Test func modemSendsCommandsThroughTheHub() async throws {

    let modemInfo: [UInt8] = [0x02, 0x60, 0x1A, 0x2B, 0x3C, 0x03, 0x37, 0x9C, 0x06]
    let fake = FakeHub { _ in modemInfo }
    let modem = Modem(connection: makeConnection(fake), clock: clock)
    let replies = await modem.replies()

    try await withThrowingTaskGroup(of: Void.self) { group in

      group.addTask { try await modem.run() }

      async let sent: Void = modem.send(.getModemInfo)

      var writes = fake.writes.makeAsyncIterator()
      #expect(await writes.next() == [0x02, 0x60])
      await pollAgain()
      try await sent

      group.cancelAll()

    }

    var iterator = replies.makeAsyncIterator()
    guard case let .modemInfo(info)? = await iterator.next() else {

      Issue.record("Expected the modem's info")

      return

    }

    #expect(info.address == InsteonAddress(0x1A, 0x2B, 0x3C))

  }

}
