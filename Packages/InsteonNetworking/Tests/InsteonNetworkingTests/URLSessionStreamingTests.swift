import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonNetworking
import Testing

/// A client hands over a response's body as it arrives, through a `URLProtocol` stub.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct URLSessionStreamingTests {

  static let address = URL(string: "http://192.0.2.20:8080/api/v1/events")!

  let client: URLSessionHTTPClient

  init() {
    let configuration: URLSessionConfiguration = .ephemeral
    configuration.protocolClasses = [ChunkedURLProtocol.self]
    configuration.timeoutIntervalForRequest = 5
    client = URLSessionHTTPClient(session: URLSession(configuration: configuration))
  }

  private func collect(_ body: AsyncThrowingStream<Data, any Error>) async throws -> [Data] {
    var chunks: [Data] = []
    for try await chunk in body { chunks.append(chunk) }
    return chunks
  }

  @Test func theStatusArrivesWithTheBodyInTheOrderItWasSent() async throws {
    ChunkedURLProtocol.script = .init(statusCode: 200, headers: ["Content-Type": "text/event-stream"], chunks: [Data("id: a-1\n".utf8), Data("data: {}\n\n".utf8)], failure: nil)

    let response = try await client.stream(URLRequest(url: Self.address))

    #expect(response.statusCode == 200)
    #expect(response.headers["content-type"] == "text/event-stream")
    // The session may join chunks that arrive together, so only the bytes and their order count.
    #expect(try await collect(response.body).reduce(Data(), +) == Data("id: a-1\ndata: {}\n\n".utf8))
  }

  @Test func aRefusalIsAStatusNotAnError() async throws {
    ChunkedURLProtocol.script = .init(statusCode: 401, headers: [:], chunks: [], failure: nil)

    let response = try await client.stream(URLRequest(url: Self.address))

    #expect(response.statusCode == 401)
    #expect(try await collect(response.body).isEmpty)
  }

  @Test func aRequestThatNeverAnswersThrows() async throws {
    ChunkedURLProtocol.script = .init(statusCode: nil, headers: [:], chunks: [], failure: URLError(.cannotConnectToHost))

    await #expect(throws: (any Error).self) { try await client.stream(URLRequest(url: Self.address)) }
  }

  @Test func aResponseThatIsNotHTTPThrowsAndStopsTheRequest() async throws {
    let (stops, stopped) = AsyncStream<Void>.makeStream()
    ChunkedURLProtocol.onStop = { stopped.yield() }
    ChunkedURLProtocol.script = .init(statusCode: nil, headers: [:], chunks: [], failure: nil, nonHTTP: true, finishes: false)
    defer { ChunkedURLProtocol.onStop = nil }

    await #expect(throws: HTTPClientError.nonHTTPResponse) { try await client.stream(URLRequest(url: Self.address)) }
    for await _ in stops { break }
  }

  @Test func aClientThatDoesNotStreamSaysSo() async throws {
    struct Plain: HTTPClient {
      func send(_ request: URLRequest) async throws -> HTTPResponse { HTTPResponse(statusCode: 200) }
    }

    await #expect(throws: HTTPClientError.streamingUnsupported) { try await Plain().stream(URLRequest(url: Self.address)) }
  }
}

final class ChunkedURLProtocol: URLProtocol {

  struct Script {
    let statusCode: Int?
    let headers: [String: String]
    let chunks: [Data]
    let failure: URLError?
    var nonHTTP = false
    var finishes = true
  }

  // The suite runs serially, so this is never accessed concurrently.
  nonisolated(unsafe) static var script: Script?
  nonisolated(unsafe) static var onStop: (@Sendable () -> Void)?

  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let script = Self.script else { return }
    if script.nonHTTP, let url = request.url {
      client?.urlProtocol(self, didReceive: URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil), cacheStoragePolicy: .notAllowed)
    }
    guard script.finishes else { return }
    if let statusCode = script.statusCode, let url = request.url,
      let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: script.headers) {
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }
    for chunk in script.chunks { client?.urlProtocol(self, didLoad: chunk) }
    if let failure = script.failure {
      client?.urlProtocol(self, didFailWithError: failure)
    } else {
      client?.urlProtocolDidFinishLoading(self)
    }
  }

  override func stopLoading() { Self.onStop?() }
}
