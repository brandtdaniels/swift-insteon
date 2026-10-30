import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import InsteonNetworking
import InsteonTestSupport

/// Requests with credentials refuse redirects, and requests without them don't.
///
/// A `URLProtocol` stub can't redirect a request on Linux, where swift-corelibs-foundation
/// doesn't handle a protocol's redirect, so these tests ask the delegate the question the
/// session asks before following a redirect, and check which requests get the delegate.
struct RedirectRefusalTests {

  // Made-up credentials and addresses: a Hub on a private network, and a redirect target in a
  // documentation range.
  static let user: String = "example-hub-user"

  static let password: String = "example-hub-password"

  static let encodedCredentials: String = Data("\(RedirectRefusalTests.user):\(RedirectRefusalTests.password)".utf8).base64EncodedString()

  let hubURL: URL = URL(string: "http://10.0.0.20:25105/buffstatus.xml")!

  let redirectTarget: URL = URL(string: "http://192.0.2.80/collect")!

  // MARK: Which requests refuse redirects

  @Test func aRequestFromBasicAuthenticationCarriesCredentials() async throws {

    let stub: StubHTTPClient = StubHTTPClient()
    let client: BasicAuthenticationHTTPClient = BasicAuthenticationHTTPClient(stub, user: Self.user, password: Self.password)

    _ = try await client.send(URLRequest(url: hubURL))

    let requests: [URLRequest] = await stub.requests
    let sent: URLRequest = try #require(requests.first)

    #expect(URLSessionHTTPClient.carriesCredentials(sent, configuration: .ephemeral))

  }

  @Test func aRequestWithAnAuthorizationHeaderCarriesCredentials() {

    var request: URLRequest = URLRequest(url: hubURL)
    request.setValue("Bearer example-token", forHTTPHeaderField: "authorization")

    #expect(URLSessionHTTPClient.carriesCredentials(request, configuration: .ephemeral))

  }

  @Test func aRequestToAURLWithAUserNameCarriesCredentials() throws {

    let url: URL = try #require(URL(string: "http://\(Self.user):\(Self.password)@10.0.0.20:25105/buffstatus.xml"))

    #expect(URLSessionHTTPClient.carriesCredentials(URLRequest(url: url), configuration: .ephemeral))

  }

  @Test func aSessionThatAddsAnAuthorizationHeaderCarriesCredentials() {

    let configuration: URLSessionConfiguration = .ephemeral
    configuration.httpAdditionalHeaders = ["Authorization": "Basic \(Self.encodedCredentials)"]

    #expect(URLSessionHTTPClient.carriesCredentials(URLRequest(url: hubURL), configuration: configuration))

  }

  @Test func aRequestWithoutCredentialsDoesntRefuseRedirects() {

    let configuration: URLSessionConfiguration = .ephemeral
    configuration.httpAdditionalHeaders = ["Accept": "text/xml"]

    var request: URLRequest = URLRequest(url: URL(string: "https://catalog.example/manifest.json")!)
    request.setValue("text/xml", forHTTPHeaderField: "Accept")

    #expect(!URLSessionHTTPClient.carriesCredentials(request, configuration: configuration))

  }

  // MARK: The refusal

  @Test func refusesARedirectSoItsTargetIsNeverAsked() async throws {

    let refusal: RedirectRefusal = RedirectRefusal()
    // The task is never resumed, so nothing is sent.
    let session: URLSession = URLSession(configuration: .ephemeral)
    var original: URLRequest = URLRequest(url: hubURL)
    original.setValue("Basic \(Self.encodedCredentials)", forHTTPHeaderField: "Authorization")
    let task: URLSessionDataTask = session.dataTask(with: original)
    let response: HTTPURLResponse = try #require(
      HTTPURLResponse(url: hubURL, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": redirectTarget.absoluteString])
    )
    var redirect: URLRequest = URLRequest(url: redirectTarget)
    redirect.setValue("Basic \(Self.encodedCredentials)", forHTTPHeaderField: "Authorization")

    #expect(!refusal.refusedRedirect)

    let followed: URLRequest? = await Self.ask(refusal, session: session, task: task, response: response, redirect: redirect)

    // `nil` tells the session not to send the request to the redirect's target.
    #expect(followed == nil)
    #expect(refusal.refusedRedirect)

  }

  @Test(arguments: [301, 302, 303, 307, 308])
  func refusesEveryKindOfRedirect(_ statusCode: Int) async throws {

    let refusal: RedirectRefusal = RedirectRefusal()
    let session: URLSession = URLSession(configuration: .ephemeral)
    let task: URLSessionDataTask = session.dataTask(with: URLRequest(url: hubURL))
    let response: HTTPURLResponse = try #require(
      HTTPURLResponse(url: hubURL, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: ["Location": redirectTarget.absoluteString])
    )

    let followed: URLRequest? = await Self.ask(refusal, session: session, task: task, response: response, redirect: URLRequest(url: redirectTarget))

    #expect(followed == nil)
    #expect(refusal.refusedRedirect)

  }

  // MARK: The backstop after a response

  @Test func aRedirectStatusCountsAsARedirect() throws {

    let request: URLRequest = URLRequest(url: hubURL)
    let response: HTTPURLResponse = try #require(HTTPURLResponse(url: hubURL, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": redirectTarget.absoluteString]))

    #expect(URLSessionHTTPClient.isRedirect(response, for: request))

  }

  @Test func aResponseFromAnotherOriginCountsAsARedirect() throws {

    let request: URLRequest = URLRequest(url: hubURL)
    let response: HTTPURLResponse = try #require(HTTPURLResponse(url: redirectTarget, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:]))

    #expect(URLSessionHTTPClient.isRedirect(response, for: request))

  }

  @Test func aResponseFromTheSameOriginIsNotARedirect() throws {

    let request: URLRequest = URLRequest(url: hubURL)
    let answered: URL = try #require(URL(string: "http://10.0.0.20:25105/other.xml"))
    let response: HTTPURLResponse = try #require(HTTPURLResponse(url: answered, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:]))

    #expect(!URLSessionHTTPClient.isRedirect(response, for: request))

  }

  @Test func anotherPortCountsAsARedirect() throws {

    let request: URLRequest = URLRequest(url: hubURL)
    let answered: URL = try #require(URL(string: "http://10.0.0.20:8080/buffstatus.xml"))
    let response: HTTPURLResponse = try #require(HTTPURLResponse(url: answered, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:]))

    #expect(URLSessionHTTPClient.isRedirect(response, for: request))

  }

  // MARK: The error

  @Test func theErrorLeavesOutTheCredentials() {

    let error: HTTPClientError = .redirectRefused
    var dumped: String = ""
    dump(error, to: &dumped)

    for text in [String(describing: error), String(reflecting: error), error.localizedDescription, dumped] {

      #expect(!text.contains(Self.user))
      #expect(!text.contains(Self.password))
      #expect(!text.contains(Self.encodedCredentials))
      #expect(!text.contains("Authorization"))

    }

    #expect(error.description.contains("redirect"))
    #expect(error.errorDescription == error.description)

  }

  @Test func everyErrorHasADescription() {

    for error in [HTTPClientError.nonHTTPResponse, .insecureRedirect, .redirectRefused] {

      #expect(!error.description.isEmpty)

    }

  }

  /// Asks the delegate whether to follow a redirect, as the session does.
  private static func ask(
    _ refusal: RedirectRefusal,
    session: URLSession,
    task: URLSessionTask,
    response: HTTPURLResponse,
    redirect: URLRequest
  ) async -> URLRequest? {

    #if canImport(FoundationNetworking)
    return await withCheckedContinuation { (continuation: CheckedContinuation<URLRequest?, Never>) in

      refusal.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: redirect) { (request: URLRequest?) in

        continuation.resume(returning: request)

      }

    }
    #else
    return await refusal.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: redirect)
    #endif

  }

}
