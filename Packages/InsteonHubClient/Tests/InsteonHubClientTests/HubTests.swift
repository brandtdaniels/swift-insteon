import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import InsteonHubClient
import InsteonMessage
import InsteonNetworking
import InsteonSerialCommand

struct HubTests {

  let endpoint = HubEndpoint(host: "hub.local")

  let lamp = InsteonAddress(0xAA, 0xBB, 0xCC)

  @Test func sendsSerialCommandsAsHexInTheQuery() async throws {

    let stub = StubHTTPClient()
    let hub = Hub(endpoint: endpoint, httpClient: stub)

    try await hub.send(.sendStandardMessage(StandardMessage(to: lamp, command: StandardDirectCommand.on(level: 0xFF))))

    let request = try #require(await stub.requests.first)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.absoluteString == "http://hub.local:25105/3?0262AABBCC0F11FF=I=3")

  }

  @Test func sendsLinkingCommandsLikeAnyOther() async throws {

    let stub = StubHTTPClient()
    let hub = Hub(endpoint: endpoint, httpClient: stub)

    try await hub.send(.startAllLinking(mode: .controller, group: 0x01))
    try await hub.send(.cancelAllLinking)

    let urls = await stub.requests.map { $0.url?.absoluteString }
    #expect(urls == ["http://hub.local:25105/3?02640101=I=3", "http://hub.local:25105/3?0265=I=3"])

  }

  @Test func clearsTheBuffer() async throws {

    let stub = StubHTTPClient()

    try await Hub(endpoint: endpoint, httpClient: stub).clearBuffer()

    let request = try #require(await stub.requests.first)
    #expect(request.httpMethod == "POST")
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

      try await hub.send(.getModemInfo)

    }

  }

  @Test func credentialsAddBasicAuthentication() async throws {

    let stub = StubHTTPClient()
    let hub = Hub(endpoint: endpoint, user: "user", password: "password", httpClient: stub)

    try await hub.send(.getModemInfo)

    let request = try #require(await stub.requests.first)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic dXNlcjpwYXNzd29yZA==")

  }

  @Test func usesCustomPort() async throws {

    let stub = StubHTTPClient()

    try await Hub(endpoint: HubEndpoint(host: "10.0.0.5", port: 9761), httpClient: stub).send(.beep)

    #expect(await stub.requests.first?.url?.absoluteString == "http://10.0.0.5:9761/3?0277=I=3")

  }

}
