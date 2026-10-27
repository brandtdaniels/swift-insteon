import Testing
import InsteonHubClient
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// Polling runs on a ``TestClock`` that only moves when a test advances it, and each test waits
/// on a write or a sleeping poll rather than on elapsed time, so results never depend on speed.
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

  @Test func firstRequestClearsTheBuffer() async throws {

    let fake = FakeHub()

    try await makeConnection(fake).write([0x02, 0x77])

    // The buffer is read before the write, since writing starts it over.
    #expect(await fake.requests == ["GET /1", "GET /buffstatus.xml", "GET /3"])

  }

  @Test func receivesTheReplyToAWrite() async throws {

    let fake = FakeHub()
    let connection = makeConnection(fake)
    var received = connection.receive().makeAsyncIterator()

    try await connection.write([0x02, 0x60])
    await pollAgain()

    #expect(try await received.next() == [0x02, 0x60, 0x06])

  }

  @Test func ignoresRepliesFromBeforeTheConnection() async throws {

    let fake = FakeHub()
    await fake.deliver([0x02, 0x77, 0x06])
    let connection = makeConnection(fake)
    var received = connection.receive().makeAsyncIterator()

    let message: [UInt8] = [0x02, 0x50, 0xAA, 0xBB, 0xCC, 0x11, 0x22, 0x33, 0x2B, 0x11, 0xFF]
    await clock.waitForSleeper(until: HubConnection.defaultPollInterval)
    await fake.deliver(message)
    clock.advance(by: HubConnection.defaultPollInterval)

    #expect(try await received.next() == message)

  }

  @Test func collapsesARunOfNaksToOne() async throws {

    let fake = FakeHub { _ in [UInt8](repeating: 0x15, count: 20) }
    let connection = makeConnection(fake)
    var received = connection.receive().makeAsyncIterator()

    try await connection.write([0x02, 0x6D])
    await pollAgain()

    #expect(try await received.next() == [0x15])

  }

  @Test func keepsBytesThatArriveBeforeAWrite() async throws {

    let fake = FakeHub()
    let connection = makeConnection(fake)
    var received = connection.receive().makeAsyncIterator()
    let message: [UInt8] = [0x02, 0x50, 0xAA, 0xBB, 0xCC, 0x11, 0x22, 0x33, 0x2B, 0x11, 0xFF]

    // A device's message arrives between polls, just before a command starts the buffer over.
    await clock.waitForSleeper(until: HubConnection.defaultPollInterval)
    await fake.deliver(message)
    try await connection.write([0x02, 0x6D])
    clock.advance(by: HubConnection.defaultPollInterval)

    #expect(try await received.next() == message + [0x02, 0x6D, 0x06])

  }

  @Test func retriesAFailedPoll() async throws {

    let fake = FakeHub(failingReads: 1)
    let connection = makeConnection(fake)
    var received = connection.receive().makeAsyncIterator()
    let message: [UInt8] = [0x02, 0x50, 0xAA, 0xBB, 0xCC, 0x11, 0x22, 0x33, 0x2B, 0x11, 0xFF]

    await clock.waitForSleeper(until: HubConnection.defaultPollInterval)
    await fake.deliver(message)
    clock.advance(by: HubConnection.defaultPollInterval)

    #expect(try await received.next() == message)

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

  @Test func modemSendsCommandsThroughTheHub() async throws {

    let modemInfo: [UInt8] = [0x02, 0x60, 0x1A, 0x2B, 0x3C, 0x03, 0x37, 0x9C, 0x06]
    let fake = FakeHub { _ in modemInfo }
    let modem = Modem(connection: makeConnection(fake), clock: clock)
    let replies = await modem.replies()

    async let sent: Void = modem.send(.getModemInfo)

    var writes = fake.writes.makeAsyncIterator()
    #expect(await writes.next() == [0x02, 0x60])
    await pollAgain()
    try await sent

    var iterator = replies.makeAsyncIterator()
    guard case let .modemInfo(info)? = await iterator.next() else {

      Issue.record("Expected the modem's info")

      return

    }

    #expect(info.address == InsteonAddress(0x1A, 0x2B, 0x3C))

  }

}
