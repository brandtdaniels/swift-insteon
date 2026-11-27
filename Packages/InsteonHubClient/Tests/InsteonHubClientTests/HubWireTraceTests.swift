import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import InsteonHubClient
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// What a Hub traces: each request it sends and each read of its buffer.
@Suite(.timeLimit(.minutes(1)))
struct HubWireTraceTests {

  let clock = TestClock()

  let endpoint = HubEndpoint(host: "hub.local")

  let trace = RecordingWireTrace()

  func makeConnection(_ fake: FakeHub) -> HubConnection {

    HubConnection(hub: Hub(endpoint: endpoint, httpClient: fake).tracing(trace), clock: clock)

  }

  /// The buffer reads traced so far.
  var reads: [RecordingWireTrace.Event] {

    trace.events.filter { if case .hubBuffer = $0.direction { true } else { false } }

  }

  @Test func eachRequestIsTracedWithItsPathAndItsPayload() async throws {

    let fake = FakeHub()
    let hub = Hub(endpoint: endpoint, httpClient: fake).tracing(trace)

    try await hub.clearBuffer()
    try await hub.write([0x02, 0x62, 0x1A, 0x2B, 0x3C, 0x0F, 0x11, 0xFF])
    try await hub.send(.groupCommand(command1: 0x11, group: 5))
    _ = try await hub.readBuffer()

    #expect(trace.events.map(\.direction) == [
      .hubRequest(path: "/1"), .hubRequest(path: "/3"), .hubRequest(path: "/0"), .hubRequest(path: "/buffstatus.xml"),
    ])
    #expect(trace.events.map(\.bytes) == [[], [0x02, 0x62, 0x1A, 0x2B, 0x3C, 0x0F, 0x11, 0xFF], [0x11, 0x05], []])

  }

  @Test func theUserTheSecretAndTheAuthorizationHeaderAreNeverTraced() async throws {

    let fake = FakeHub()
    let hub = Hub(endpoint: endpoint, user: "hubuser", password: "hunter2-secret", httpClient: fake).tracing(trace)
    let encoded = Data("hubuser:hunter2-secret".utf8).base64EncodedString()

    try await hub.clearBuffer()
    try await hub.write([0x02, 0x60])
    try await hub.send(.cancelLinking)
    _ = try await hub.readBuffer()

    let text = trace.events.map { "\($0.direction) \($0.bytes)" }.joined(separator: "\n")
    for forbidden in ["hubuser", "hunter2", encoded, "Authorization", "Basic"] {
      #expect(!text.contains(forbidden))
    }
    #expect(!trace.events.isEmpty)

  }

  @Test func aBufferReadInTwoPartsTracesTheNewBytesOfEachReadWithTheEndPosition() async throws {

    let fake = FakeHub { _ in [] }
    let connection = makeConnection(fake)
    try await connection.write([0x02, 0x60])

    await fake.deliver([0x02, 0x50, 0x1A, 0x2B])
    #expect(try await HubConnectionTests.firstChunk(of: connection.receive()) == [0x02, 0x50, 0x1A, 0x2B])
    await fake.deliver([0x3C, 0x0F])
    #expect(try await HubConnectionTests.firstChunk(of: connection.receive()) == [0x3C, 0x0F])

    let nonEmpty = reads.filter { !$0.bytes.isEmpty }
    #expect(nonEmpty == [
      .init(direction: .hubBuffer(endIndex: 4, step: .advanced), bytes: [0x02, 0x50, 0x1A, 0x2B]),
      .init(direction: .hubBuffer(endIndex: 6, step: .advanced), bytes: [0x3C, 0x0F]),
    ])

  }

  @Test func aReadThatWrappedTheBufferIsTracedAsWrappedWithTheBytesInTheOrderTheyWereWritten() async throws {

    let fake = FakeHub { _ in [] }
    let connection = makeConnection(fake)
    try await connection.write([0x02, 0x60])

    await fake.deliver([UInt8](repeating: 0x11, count: 90))
    _ = try await HubConnectionTests.firstChunk(of: connection.receive())
    await fake.deliver([UInt8](repeating: 0x22, count: 10) + [UInt8](repeating: 0x33, count: 10))
    let chunk = try await HubConnectionTests.firstChunk(of: connection.receive())

    let expected = [UInt8](repeating: 0x22, count: 10) + [UInt8](repeating: 0x33, count: 10)
    #expect(chunk == expected)
    #expect(reads.last == .init(direction: .hubBuffer(endIndex: 10, step: .wrapped), bytes: expected))

  }

  @Test func aBufferTheHubClearedIsTracedAsClearedAndOneRefilledAfterwardAsRefilled() async throws {

    let fake = FakeHub { _ in [] }
    let hub = Hub(endpoint: endpoint, httpClient: fake)
    let connection = HubConnection(hub: hub.tracing(trace), clock: clock)
    try await connection.write([0x02, 0x60])
    // The write read the empty buffer, which the cursor treats as cleared.
    #expect(reads.first == .init(direction: .hubBuffer(endIndex: 0, step: .cleared), bytes: []))

    await fake.deliver([1, 2, 3, 4, 5])
    _ = try await HubConnectionTests.firstChunk(of: connection.receive())
    try await hub.clearBuffer()
    await fake.deliver([6, 7, 8])
    let chunk = try await HubConnectionTests.firstChunk(of: connection.receive())

    #expect(chunk == [6, 7, 8])
    #expect(reads.last == .init(direction: .hubBuffer(endIndex: 3, step: .refilled), bytes: [6, 7, 8]))

  }

  @Test func aReadThatBroughtNothingNewIsTracedWithNoBytes() async throws {

    let fake = FakeHub { _ in [] }
    let connection = makeConnection(fake)
    try await connection.write([0x02, 0x60])
    await fake.deliver([0x06])
    _ = try await HubConnectionTests.firstChunk(of: connection.receive())

    async let next = HubConnectionTests.firstChunk(of: connection.receive())
    await clock.waitForSleeper(until: HubConnection.defaultPollInterval)
    await fake.deliver([0x07])
    clock.advance(by: HubConnection.defaultPollInterval)
    _ = try await next

    #expect(reads.map(\.bytes).contains([]))

  }

  @Test func withoutATracerTheRequestsAreTheSame() async throws {

    let fake = FakeHub()
    let connection = HubConnection(hub: Hub(endpoint: endpoint, httpClient: fake), clock: clock)

    try await connection.write([0x02, 0x77])

    #expect(await fake.requests == ["GET /1", "GET /buffstatus.xml", "GET /3"])
    #expect(trace.events.isEmpty)

  }

}
