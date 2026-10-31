import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import InsteonNetworking

@Suite(.serialized, .timeLimit(.minutes(1)))
struct URLSessionHTTPClientTests {

  let client: URLSessionHTTPClient

  let sameOriginClient: URLSessionHTTPClient

  /// Reads at most 8 bytes of an answer.
  let limitedClient: URLSessionHTTPClient

  init() {

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]

    let session: URLSession = URLSession(configuration: configuration)

    client = URLSessionHTTPClient(session: session)
    sameOriginClient = URLSessionHTTPClient(session: session, redirectPolicy: .sameOriginHTTPSOnly)
    limitedClient = URLSessionHTTPClient(session: session, maximumResponseSize: 8)

  }

  // MARK: The size of an answer

  @Test(.timeLimit(.minutes(1))) func refusesABodyLargerThanTheLimit() async {

    StubURLProtocol.stub = .success(statusCode: 200, headers: [:], body: Data(repeating: 0x41, count: 9))

    await #expect(throws: HTTPClientError.responseTooLarge(limit: 8)) {

      try await limitedClient.send(URLRequest(url: URL(string: "http://192.168.1.20:25105/buffstatus.xml")!))

    }

  }

  @Test(.timeLimit(.minutes(1))) func readsABodyAsLargeAsTheLimit() async throws {

    StubURLProtocol.stub = .success(statusCode: 200, headers: [:], body: Data(repeating: 0x41, count: 8))

    let response: HTTPResponse = try await limitedClient.send(URLRequest(url: URL(string: "http://192.168.1.20:25105/buffstatus.xml")!))

    #expect(response.body == Data(repeating: 0x41, count: 8))

  }

  @Test(.timeLimit(.minutes(1))) func readsALargeBodyWithoutALimit() async throws {

    StubURLProtocol.stub = .success(statusCode: 200, headers: [:], body: Data(repeating: 0x41, count: 100_000))

    let response: HTTPResponse = try await client.send(URLRequest(url: URL(string: "http://192.168.1.20:25105/buffstatus.xml")!))

    #expect(response.body.count == 100_000)

  }

  @Test func returnsStatusHeadersAndBody() async throws {

    StubURLProtocol.stub = .success(statusCode: 404, headers: ["X-Test": "yes"], body: Data("missing".utf8))

    let response = try await client.send(URLRequest(url: URL(string: "http://hub.local/missing")!))

    #expect(response.statusCode == 404)
    #expect(response.value(forHeader: "X-Test") == "yes")
    #expect(response.body == Data("missing".utf8))

  }

  @Test func returnsTheResponseToARequestWithCredentials() async throws {

    StubURLProtocol.stub = .success(statusCode: 200, headers: ["X-Test": "yes"], body: Data("<response/>".utf8))
    // Made-up credentials for a Hub on a private network.
    var request: URLRequest = URLRequest(url: URL(string: "http://10.0.0.20:25105/buffstatus.xml")!)
    request.setValue("Basic ZXhhbXBsZS11c2VyOmV4YW1wbGUtcGFzc3dvcmQ=", forHTTPHeaderField: "Authorization")

    let response: HTTPResponse = try await client.send(request)

    #expect(response.statusCode == 200)
    #expect(response.value(forHeader: "X-Test") == "yes")
    #expect(response.body == Data("<response/>".utf8))

  }

  @Test func throwsTransportErrors() async {

    StubURLProtocol.stub = .failure(URLError(.notConnectedToInternet))

    let error = await #expect(throws: URLError.self) {

      try await client.send(URLRequest(url: URL(string: "http://hub.local/")!))

    }

    #expect(error?.code == .notConnectedToInternet)

  }

  @Test func rejectsResponsesThatArentHTTP() async {

    StubURLProtocol.stub = .nonHTTP

    await #expect(throws: HTTPClientError.nonHTTPResponse) {

      try await client.send(URLRequest(url: URL(string: "http://hub.local/")!))

    }

  }

  @Test func rejectsAnHTTPSRequestAnsweredFromAnAddressThatIsntHTTPS() async {

    StubURLProtocol.stub = .answeredFrom(URL(string: "http://example.com/manifest.json")!)

    await #expect(throws: HTTPClientError.insecureRedirect) {

      try await client.send(URLRequest(url: URL(string: "https://example.com/manifest.json")!))

    }

  }

  // MARK: Same-origin HTTPS, checked again after the response

  @Test func sameOriginRejectsAnAnswerFromAnotherHTTPSHost() async {

    // As if the session followed a redirect without asking the delegate.
    StubURLProtocol.stub = .answeredFrom(URL(string: "https://192.0.2.80/v0/manifest.json")!)

    await #expect(throws: HTTPClientError.redirectRefused) {

      try await sameOriginClient.send(URLRequest(url: URL(string: "https://catalog.example/v0/manifest.json")!))

    }

  }

  @Test func sameOriginRejectsAnAnswerFromAnotherPort() async {

    StubURLProtocol.stub = .answeredFrom(URL(string: "https://catalog.example:8443/v0/manifest.json")!)

    await #expect(throws: HTTPClientError.redirectRefused) {

      try await sameOriginClient.send(URLRequest(url: URL(string: "https://catalog.example/v0/manifest.json")!))

    }

  }

  @Test func sameOriginRejectsAnAnswerThatIsntHTTPS() async {

    StubURLProtocol.stub = .answeredFrom(URL(string: "http://catalog.example/v0/manifest.json")!)

    await #expect(throws: HTTPClientError.insecureRedirect) {

      try await sameOriginClient.send(URLRequest(url: URL(string: "https://catalog.example/v0/manifest.json")!))

    }

  }

  @Test func sameOriginAcceptsAnAnswerFromTheSameHost() async throws {

    StubURLProtocol.stub = .answeredFrom(URL(string: "https://catalog.example/v0/")!)

    let response: HTTPResponse = try await sameOriginClient.send(URLRequest(url: URL(string: "https://catalog.example/v0")!))

    #expect(response.statusCode == 200)

  }

}

final class StubURLProtocol: URLProtocol {

  enum Stub {

    case success(statusCode: Int, headers: [String: String], body: Data)

    case failure(URLError)

    case nonHTTP

    /// An HTTP response whose URL is another address, as after a redirect.
    case answeredFrom(URL)

  }

  // Tests in this suite run serially, so this is never accessed concurrently.
  nonisolated(unsafe) static var stub: Stub?

  override class func canInit(with request: URLRequest) -> Bool {

    true

  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {

    request

  }

  override func startLoading() {

    switch Self.stub {
    case let .success(statusCode, headers, body)?:
      let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: body)
      client?.urlProtocolDidFinishLoading(self)
    case let .failure(error)?:
      client?.urlProtocol(self, didFailWithError: error)
    case .nonHTTP?:
      let response = URLResponse(url: request.url!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocolDidFinishLoading(self)
    case let .answeredFrom(url)?:
      let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: Data())
      client?.urlProtocolDidFinishLoading(self)
    case nil:
      client?.urlProtocol(self, didFailWithError: URLError(.unknown))
    }

  }

  override func stopLoading() {}

}
