// swift-corelibs-foundation stops the process when a `URLProtocol` redirects a request, so a
// stub can redirect one only on Apple platforms.
#if !canImport(FoundationNetworking)
import Foundation
import Testing
import InsteonNetworking

/// A session redirects a request end to end, through a `URLProtocol` stub.
///
/// A request with credentials gets a delegate that refuses the redirect, so the redirect's
/// target is never asked. The check after the response would also refuse the target's answer,
/// since it comes from another address, but only the delegate keeps the request from reaching
/// the target, so the tests check which addresses the stub was asked to load.
@Suite(.serialized)
struct URLSessionRedirectTests {

  // Made-up credentials and addresses: a Hub on a private network, and a redirect target in a
  // documentation range.
  static let user: String = "example-hub-user"

  static let password: String = "example-hub-password"

  static let hubURL: URL = URL(string: "http://10.0.0.20:25105/buffstatus.xml")!

  static let redirectTarget: URL = URL(string: "http://192.0.2.80/collect")!

  let session: URLSession

  init() {

    let configuration: URLSessionConfiguration = .ephemeral
    configuration.protocolClasses = [RedirectingURLProtocol.self]
    // A request that never finishes fails here instead of stalling the run.
    configuration.timeoutIntervalForRequest = 5

    session = URLSession(configuration: configuration)

    RedirectingURLProtocol.configure(redirecting: Self.hubURL, to: Self.redirectTarget)

  }

  @Test func aRequestWithCredentialsIsntSentToTheRedirectsTarget() async throws {

    let client: BasicAuthenticationHTTPClient = BasicAuthenticationHTTPClient(
      URLSessionHTTPClient(session: session),
      user: Self.user,
      password: Self.password
    )

    await #expect(throws: HTTPClientError.redirectRefused) {

      try await client.send(URLRequest(url: Self.hubURL))

    }

    // Without the delegate, the session would follow the redirect and load the target.
    #expect(RedirectingURLProtocol.loadedURLs == [Self.hubURL])

  }

  @Test func aRequestWithoutCredentialsFollowsTheRedirect() async throws {

    let client: URLSessionHTTPClient = URLSessionHTTPClient(session: session)

    let response: HTTPResponse = try await client.send(URLRequest(url: Self.hubURL))

    #expect(response.statusCode == 200)
    #expect(response.body == RedirectingURLProtocol.targetBody)
    #expect(RedirectingURLProtocol.loadedURLs == [Self.hubURL, Self.redirectTarget])

  }

}

/// A `URLProtocol` that answers one address with a redirect and every other with 200, and
/// records each address it's asked to load.
final class RedirectingURLProtocol: URLProtocol {

  /// The body of every answer that isn't a redirect.
  static let targetBody: Data = Data("<target/>".utf8)

  // `lock` guards `redirect` and `loaded`.
  private static let lock: NSLock = NSLock()

  nonisolated(unsafe) private static var redirect: (from: URL, to: URL)?

  nonisolated(unsafe) private static var loaded: [URL] = []

  /// The addresses the stub was asked to load, in order.
  static var loadedURLs: [URL] {

    lock.withLock { loaded }

  }

  /// Sets the address to redirect and its target, and forgets the addresses already loaded.
  ///
  /// - Parameters:
  ///   - source: The address answered with a redirect.
  ///   - target: The address the redirect names.
  static func configure(redirecting source: URL, to target: URL) {

    lock.withLock {

      redirect = (from: source, to: target)
      loaded = []

    }

  }

  override class func canInit(with request: URLRequest) -> Bool {

    true

  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {

    request

  }

  override func startLoading() {

    guard let url: URL = request.url else {

      client?.urlProtocol(self, didFailWithError: URLError(.badURL))
      return

    }

    let redirect: (from: URL, to: URL)? = Self.lock.withLock { () -> (from: URL, to: URL)? in

      Self.loaded.append(url)
      return Self.redirect

    }

    if let redirect, url == redirect.from {

      let response: HTTPURLResponse = HTTPURLResponse(
        url: url,
        statusCode: 302,
        httpVersion: "HTTP/1.1",
        headerFields: ["Location": redirect.to.absoluteString]
      )!
      var newRequest: URLRequest = request
      newRequest.url = redirect.to

      client?.urlProtocol(self, wasRedirectedTo: newRequest, redirectResponse: response)

      // When the session follows the redirect, it stops this load and ignores the rest. When
      // its delegate refuses, the redirect itself is the answer, so finish it.
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: Data())
      client?.urlProtocolDidFinishLoading(self)

      return

    }

    let response: HTTPURLResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!

    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Self.targetBody)
    client?.urlProtocolDidFinishLoading(self)

  }

  override func stopLoading() {}

}
#endif
