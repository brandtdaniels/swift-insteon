import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import InsteonHubClient
import InsteonNetworking
import InsteonTestSupport

/// A client whose requests never get an answer: each waits until its task is canceled.
struct SilentHubClient: HTTPClient {

  func send(_ request: URLRequest) async throws -> HTTPResponse {

    try await Task.sleep(for: .seconds(86_400))

    return HTTPResponse(statusCode: 200)

  }

}

/// The limits on a Hub's requests, and a connection that stops at the Hub's first rejection.
@Suite(.timeLimit(.minutes(1)))
struct HubTransportTests {

  let endpoint = HubEndpoint(host: "192.168.1.20")

  // A request's own timeout limits only the wait between bytes, so the whole request has a
  // limit too.
  @Test func aRequestFailsOnceTheRequestTimeoutHasPassedInAll() async {

    let clock: TestClock = TestClock()
    let hub: Hub = Hub(endpoint: endpoint, httpClient: SilentHubClient(), requestTimeout: .seconds(5), clock: clock)

    let read: Task<HubBuffer, any Error> = Task {

      try await hub.readBuffer()

    }

    await clock.waitForSleeper(until: .seconds(5))
    clock.advance(by: .seconds(5))

    let error = await #expect(throws: URLError.self) {

      _ = try await read.value

    }

    #expect(error?.code == .timedOut)
    #expect(HubStoppedAnswering.isUnanswered(error ?? URLError(.unknown)))

  }

  @Test func refusesAPageLargerThanAHubs() async {

    let body: Data = Data(repeating: 0x30, count: Hub.maximumResponseSize + 1)
    let hub: Hub = Hub(endpoint: endpoint, httpClient: StubHTTPClient(response: HTTPResponse(statusCode: 200, body: body)))

    await #expect(throws: HTTPClientError.responseTooLarge(limit: Hub.maximumResponseSize)) {

      _ = try await hub.readBuffer()

    }

  }

  @Test func theDefaultClientIsForTheLocalNetwork() {

    #expect(Hub.maximumResponseSize == 64 * 1024)
    #expect(URLSessionHTTPClient.localNetwork().redirectPolicy == .refuseAll)

  }

  // MARK: The Hub's rejection

  @Test func aWriteTheHubRejectsSendsNoFurtherRequest() async throws {

    let clock: TestClock = TestClock()
    let fake: FakeHub = FakeHub(status: 401)
    let connection: HubConnection = HubConnection(hub: Hub(endpoint: endpoint, httpClient: fake), clock: clock)

    await #expect(throws: HubError.unexpectedStatus(401)) {

      try await connection.write([0x02, 0x60])

    }

    // The connection remembers the rejection, so neither a write nor a poll asks again.
    await #expect(throws: HubError.unexpectedStatus(401)) {

      try await connection.write([0x02, 0x60])

    }

    await #expect(throws: HubError.unexpectedStatus(401)) {

      for try await _ in connection.receive() {}

    }

    #expect(await fake.requests == ["GET /1"])

  }

  @Test func aPollTheHubForbidsSendsNoFurtherRequest() async throws {

    let clock: TestClock = TestClock()
    let fake: FakeHub = FakeHub(status: 403)
    let connection: HubConnection = HubConnection(hub: Hub(endpoint: endpoint, httpClient: fake), clock: clock)

    await #expect(throws: HubError.unexpectedStatus(403)) {

      for try await _ in connection.receive() {}

    }

    await #expect(throws: HubError.unexpectedStatus(403)) {

      try await connection.write([0x02, 0x60])

    }

    #expect(await fake.requests == ["GET /1"])

  }

  // A rejection of the buffer read before a write stops the write too, rather than sending the
  // credentials again.
  @Test func aRejectedReadBeforeAWriteStopsTheWrite() async throws {

    let clock: TestClock = TestClock()
    let fake: RejectingBufferReads = RejectingBufferReads()
    let connection: HubConnection = HubConnection(hub: Hub(endpoint: endpoint, httpClient: fake), clock: clock)

    await #expect(throws: HubError.unexpectedStatus(401)) {

      try await connection.write([0x02, 0x60])

    }

    #expect(await fake.paths == ["/1", "/buffstatus.xml"])

  }

}

/// Clears the buffer, then rejects every other request with `401`.
actor RejectingBufferReads: HTTPClient {

  private(set) var paths: [String] = []

  func send(_ request: URLRequest) async throws -> HTTPResponse {

    let path: String = request.url?.path ?? ""
    paths.append(path)

    return HTTPResponse(statusCode: path == "/1" ? 200 : 401)

  }

}
