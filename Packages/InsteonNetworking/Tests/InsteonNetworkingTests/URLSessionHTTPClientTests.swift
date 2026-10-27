import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import InsteonNetworking

@Suite(.serialized)
struct URLSessionHTTPClientTests {

  let client: URLSessionHTTPClient

  init() {

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]

    client = URLSessionHTTPClient(session: URLSession(configuration: configuration))

  }

  @Test func returnsStatusHeadersAndBody() async throws {

    StubURLProtocol.stub = .success(statusCode: 404, headers: ["X-Test": "yes"], body: Data("missing".utf8))

    let response = try await client.send(URLRequest(url: URL(string: "http://hub.local/missing")!))

    #expect(response.statusCode == 404)
    #expect(response.value(forHeader: "X-Test") == "yes")
    #expect(response.body == Data("missing".utf8))

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

}

final class StubURLProtocol: URLProtocol {

  enum Stub {

    case success(statusCode: Int, headers: [String: String], body: Data)

    case failure(URLError)

    case nonHTTP

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
    case nil:
      client?.urlProtocol(self, didFailWithError: URLError(.unknown))
    }

  }

  override func stopLoading() {}

}
