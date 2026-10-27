import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import InsteonNetworking

struct BasicAuthenticationHTTPClientTests {

  let request = URLRequest(url: URL(string: "http://hub.local:25105/buffstatus.xml")!)

  @Test func addsBasicAuthorizationHeader() async throws {

    let stub = StubHTTPClient()
    let client = BasicAuthenticationHTTPClient(stub, user: "user", password: "password")

    _ = try await client.send(request)

    let sent = await stub.requests
    #expect(sent.first?.value(forHTTPHeaderField: "Authorization") == "Basic dXNlcjpwYXNzd29yZA==")
    #expect(sent.first?.url == request.url)

  }

  @Test func returnsWrappedClientsResponse() async throws {

    let expected = HTTPResponse(statusCode: 401, body: Data("denied".utf8))
    let client = BasicAuthenticationHTTPClient(StubHTTPClient(response: expected), user: "user", password: "password")

    #expect(try await client.send(request) == expected)

  }

}
