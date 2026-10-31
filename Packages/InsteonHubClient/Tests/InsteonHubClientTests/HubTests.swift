import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import InsteonHubClient
import InsteonNetworking
import InsteonProtocol
import InsteonTestSupport

@Suite(.timeLimit(.minutes(1)))
struct HubTests {

  let endpoint = HubEndpoint(host: "hub.local")

  let lamp = InsteonAddress(0xAA, 0xBB, 0xCC)

  @Test func writesBytesAsHexInTheQuery() async throws {

    let stub = StubHTTPClient()
    let hub = Hub(endpoint: endpoint, httpClient: stub)

    try await hub.write(SerialCommand.sendStandardMessage(StandardMessage(to: lamp, command: StandardDirectCommand.on(level: 0xFF))).bytes)

    let request = try #require(await stub.requests.first)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.absoluteString == "http://hub.local:25105/3?0262AABBCC0F11FF=I=3")

  }

  @Test func writesLinkingCommandsLikeAnyOther() async throws {

    let stub = StubHTTPClient()
    let hub = Hub(endpoint: endpoint, httpClient: stub)

    try await hub.write(SerialCommand.startAllLinking(mode: .controller, group: 0x01).bytes)
    try await hub.write(SerialCommand.cancelAllLinking.bytes)

    let urls = await stub.requests.map { $0.url?.absoluteString }
    #expect(urls == ["http://hub.local:25105/3?02640101=I=3", "http://hub.local:25105/3?0265=I=3"])

  }

  // The Insteon Hub Developer's Guide's examples: the command in hex, the group in decimal.
  @Test func sendsShortCommandsWithTheGroupInDecimal() async throws {

    let stub = StubHTTPClient()
    let hub = Hub(endpoint: endpoint, httpClient: stub)

    try await hub.send(.groupCommand(command1: 0x11, group: 0x01))
    try await hub.send(.groupCommand(command1: 0x13, group: 182))
    try await hub.send(.startLinking(group: 0x01))
    try await hub.send(.startUnlinking(group: 239))
    try await hub.send(.cancelLinking)

    #expect(await stub.requests.map { $0.url?.absoluteString } == [
      "http://hub.local:25105/0?1101=I=0",
      "http://hub.local:25105/0?13182=I=0",
      "http://hub.local:25105/0?0901=I=0",
      "http://hub.local:25105/0?0A239=I=0",
      "http://hub.local:25105/0?08=I=0",
    ])

  }

  @Test func clearsTheBuffer() async throws {

    let stub = StubHTTPClient()

    try await Hub(endpoint: endpoint, httpClient: stub).clearBuffer()

    let request = try #require(await stub.requests.first)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.absoluteString == "http://hub.local:25105/1?XB=M=1")

  }

  @Test func readsAndParsesTheBuffer() async throws {

    let body = "<response><BS>" + "0260" + String(repeating: "0", count: 196) + "04" + "</BS></response>"
    let stub = StubHTTPClient(response: HTTPResponse(statusCode: 200, body: Data(body.utf8)))

    let buffer = try await Hub(endpoint: endpoint, httpClient: stub).readBuffer()

    let request = try #require(await stub.requests.first)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.absoluteString == "http://hub.local:25105/buffstatus.xml")
    #expect(buffer.bytes.count == 100)
    #expect(Array(buffer.bytes.prefix(2)) == [0x02, 0x60])
    #expect(buffer.endIndex == 2)

  }

  @Test func throwsOnNonSuccessStatus() async {

    let hub = Hub(endpoint: endpoint, httpClient: StubHTTPClient(response: HTTPResponse(statusCode: 401)))

    await #expect(throws: HubError.unexpectedStatus(401)) {

      try await hub.write([0x02, 0x60])

    }

  }

  @Test func credentialsAddBasicAuthentication() async throws {

    let stub = StubHTTPClient()
    let hub = Hub(endpoint: endpoint, user: "user", password: "password", httpClient: stub)

    try await hub.write([0x02, 0x60])

    let request = try #require(await stub.requests.first)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic dXNlcjpwYXNzd29yZA==")

  }

  // A Hub that doesn't answer fails in seconds, not after URLRequest's default of a minute.
  @Test func givesEachRequestTheRequestTimeout() async throws {

    let stub = StubHTTPClient()

    try await Hub(endpoint: endpoint, httpClient: stub).clearBuffer()
    _ = try? await Hub(endpoint: endpoint, user: "user", password: "password", httpClient: stub, requestTimeout: .milliseconds(2_500)).readBuffer()

    let requests: [URLRequest] = await stub.requests
    try #require(requests.count == 2)

    #expect(Hub.defaultRequestTimeout == .seconds(5))
    #expect(requests[0].timeoutInterval == 5)
    #expect(requests[1].timeoutInterval == 2.5)
    #expect(requests[1].url?.absoluteString == "http://hub.local:25105/buffstatus.xml")

  }

  @Test func usesCustomPort() async throws {

    let stub = StubHTTPClient()

    try await Hub(endpoint: HubEndpoint(host: "10.0.0.5", port: 8080), httpClient: stub).write([0x02, 0x77])

    #expect(await stub.requests.first?.url?.absoluteString == "http://10.0.0.5:8080/3?0277=I=3")

  }

  @Test(arguments: [-1, 65_536])
  func rejectsAPortOutOfRange(_ port: Int) async {

    let stub = StubHTTPClient()
    let endpoint = HubEndpoint(host: "hub.local", port: port)

    await #expect(throws: HubError.invalidEndpoint(endpoint)) {

      try await Hub(endpoint: endpoint, httpClient: stub).readBuffer()

    }

    #expect(await stub.requests.isEmpty)

  }

  @Test func aHostCantChangeWhereTheRequestGoes() async throws {

    let stub = StubHTTPClient()
    let hub = Hub(endpoint: HubEndpoint(host: "hub.local/steal?x="), httpClient: stub)

    do {

      _ = try await hub.readBuffer()

    } catch HubError.invalidEndpoint {

      return

    } catch {}

    let url = try #require(await stub.requests.first?.url)
    #expect(url.path == "/buffstatus.xml")
    #expect(url.query == nil)

  }

}
