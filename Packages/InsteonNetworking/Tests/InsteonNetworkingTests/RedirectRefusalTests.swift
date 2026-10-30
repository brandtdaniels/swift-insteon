import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import InsteonNetworking
import InsteonTestSupport

/// Requests with credentials refuse redirects, and requests without them follow the
/// client's redirect policy.
///
/// A `URLProtocol` stub can't redirect a request on Linux, where swift-corelibs-foundation
/// doesn't handle a protocol's redirect, so these tests ask the delegate the question the
/// session asks before following a redirect, and check which requests get the delegate.
/// On Apple platforms, `URLSessionRedirectTests` redirects a request through a session.
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

  @Test func theDelegateDeclinesARedirectAndRecordsIt() async throws {

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

  // MARK: Same-origin HTTPS redirects

  // A made-up catalog host. Other hosts are made up too, or in a documentation range.
  static let catalogManifest: URL = URL(string: "https://catalog.example/v0/manifest.json")!

  @Test(arguments: [
    "https://catalog.example/v0/manifest.json?sha256=0",
    "https://catalog.example/v0/",
    "https://catalog.example/v1/manifest.json",
    "https://CATALOG.example/v0/manifest.json",
    "https://catalog.example:443/v0/manifest.json",
  ])
  func sameOriginFollowsHTTPSOnTheSameHostAndPort(_ target: String) async throws {

    let redirect: URL = try #require(URL(string: target))
    let followed: URLRequest? = try await Self.decide(.sameOriginHTTPSOnly, from: Self.catalogManifest, to: redirect)

    #expect(followed?.url == redirect)

  }

  @Test(arguments: [
    "http://catalog.example/v0/manifest.json",
    "https://192.0.2.80/v0/manifest.json",
    "https://catalog.example.evil.example/v0/manifest.json",
    "https://catalog.example:8443/v0/manifest.json",
    "http://catalog.example:443/v0/manifest.json",
    "ftp://catalog.example/v0/manifest.json",
  ])
  func sameOriginRefusesADowngradeAnotherHostOrAnotherPort(_ target: String) async throws {

    let redirect: URL = try #require(URL(string: target))
    let followed: URLRequest? = try await Self.decide(.sameOriginHTTPSOnly, from: Self.catalogManifest, to: redirect)

    #expect(followed == nil)

  }

  @Test func sameOriginRefusesAChainThroughHTTPAtItsFirstStep() async throws {

    let session: URLSession = URLSession(configuration: .ephemeral)
    let task: URLSessionDataTask = session.dataTask(with: URLRequest(url: Self.catalogManifest))
    let refusal: RedirectRefusal = RedirectRefusal(policy: .sameOriginHTTPSOnly, original: Self.catalogManifest)
    let downgrade: URL = try #require(URL(string: "http://catalog.example/v0/manifest.json"))
    let elsewhere: URL = try #require(URL(string: "https://192.0.2.80/v0/manifest.json"))

    let firstResponse: HTTPURLResponse = try #require(
      HTTPURLResponse(url: Self.catalogManifest, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": downgrade.absoluteString])
    )
    let first: URLRequest? = await Self.ask(refusal, session: session, task: task, response: firstResponse, redirect: URLRequest(url: downgrade))

    #expect(first == nil)
    #expect(refusal.refusedRedirect)
    #expect(refusal.refusedTarget == downgrade)

    // Were the HTTP step's answer rewritten to send the request on to another HTTPS host, that
    // step is refused too, and the first refusal is the one recorded.
    let secondResponse: HTTPURLResponse = try #require(
      HTTPURLResponse(url: downgrade, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": elsewhere.absoluteString])
    )
    let second: URLRequest? = await Self.ask(refusal, session: session, task: task, response: secondResponse, redirect: URLRequest(url: elsewhere))

    #expect(second == nil)
    #expect(refusal.refusedTarget == downgrade)
    #expect(URLSessionHTTPClient.error(refusing: refusal.refusedTarget, of: URLRequest(url: Self.catalogManifest), policy: .sameOriginHTTPSOnly) == .insecureRedirect)

  }

  @Test func sameOriginComparesEachStepWithTheFirstAddress() async throws {

    let session: URLSession = URLSession(configuration: .ephemeral)
    let task: URLSessionDataTask = session.dataTask(with: URLRequest(url: Self.catalogManifest))
    let refusal: RedirectRefusal = RedirectRefusal(policy: .sameOriginHTTPSOnly, original: Self.catalogManifest)
    let directory: URL = try #require(URL(string: "https://catalog.example/v0/"))
    let elsewhere: URL = try #require(URL(string: "https://192.0.2.80/v0/manifest.json"))
    let response: HTTPURLResponse = try #require(HTTPURLResponse(url: Self.catalogManifest, statusCode: 301, httpVersion: "HTTP/1.1", headerFields: [:]))

    let first: URLRequest? = await Self.ask(refusal, session: session, task: task, response: response, redirect: URLRequest(url: directory))
    let second: URLRequest? = await Self.ask(refusal, session: session, task: task, response: response, redirect: URLRequest(url: elsewhere))

    #expect(first?.url == directory)
    #expect(second == nil)
    #expect(refusal.refusedTarget == elsewhere)

  }

  @Test func sameOriginFollowsNothingFromARequestThatIsntHTTPS() async throws {

    let original: URL = try #require(URL(string: "http://catalog.example/v0/manifest.json"))
    let followed: URLRequest? = try await Self.decide(.sameOriginHTTPSOnly, from: original, to: Self.catalogManifest)

    #expect(followed == nil)

  }

  @Test func followAllFollowsAnotherHostAndRefuseAllFollowsNothing() async throws {

    let redirect: URL = try #require(URL(string: "http://192.0.2.80/collect"))

    let followed: URLRequest? = try await Self.decide(.followAll, from: Self.catalogManifest, to: redirect)
    let refused: URLRequest? = try await Self.decide(.refuseAll, from: Self.catalogManifest, to: Self.catalogManifest)

    #expect(followed?.url == redirect)
    #expect(refused == nil)

  }

  @Test func aRefusedDowngradeIsInsecureAndAnotherHostIsRefused() throws {

    let request: URLRequest = URLRequest(url: Self.catalogManifest)
    let downgrade: URL = try #require(URL(string: "http://catalog.example/v0/manifest.json"))
    let elsewhere: URL = try #require(URL(string: "https://192.0.2.80/v0/manifest.json"))

    #expect(URLSessionHTTPClient.error(refusing: downgrade, of: request, policy: .sameOriginHTTPSOnly) == .insecureRedirect)
    #expect(URLSessionHTTPClient.error(refusing: elsewhere, of: request, policy: .sameOriginHTTPSOnly) == .redirectRefused)
    // A request with credentials reports every refused redirect the same way.
    #expect(URLSessionHTTPClient.error(refusing: downgrade, of: request, policy: .refuseAll) == .redirectRefused)

  }

  // MARK: Which policy a request gets

  @Test func aRequestWithCredentialsRefusesEveryRedirectWhateverTheClientsPolicy() {

    var request: URLRequest = URLRequest(url: Self.catalogManifest)
    request.setValue("Basic \(Self.encodedCredentials)", forHTTPHeaderField: "Authorization")

    for clientPolicy in [RedirectPolicy.followAll, .sameOriginHTTPSOnly, .refuseAll] {

      #expect(URLSessionHTTPClient.policy(for: request, configuration: .ephemeral, clientPolicy: clientPolicy) == .refuseAll)

    }

  }

  @Test func aRequestWithoutCredentialsGetsTheClientsPolicy() {

    let request: URLRequest = URLRequest(url: Self.catalogManifest)

    for clientPolicy in [RedirectPolicy.followAll, .sameOriginHTTPSOnly, .refuseAll] {

      #expect(URLSessionHTTPClient.policy(for: request, configuration: .ephemeral, clientPolicy: clientPolicy) == clientPolicy)

    }

  }

  @Test func aClientFollowsEveryRedirectByDefault() {

    #expect(URLSessionHTTPClient().redirectPolicy == .followAll)
    #expect(URLSessionHTTPClient(redirectPolicy: .sameOriginHTTPSOnly).redirectPolicy == .sameOriginHTTPSOnly)

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

  /// Asks a new delegate with a policy whether to follow one redirect, as the session does.
  private static func decide(_ policy: RedirectPolicy, from original: URL, to target: URL) async throws -> URLRequest? {

    let refusal: RedirectRefusal = RedirectRefusal(policy: policy, original: original)
    let session: URLSession = URLSession(configuration: .ephemeral)
    // The task is never resumed, so nothing is sent.
    let task: URLSessionDataTask = session.dataTask(with: URLRequest(url: original))
    let response: HTTPURLResponse = try #require(
      HTTPURLResponse(url: original, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": target.absoluteString])
    )

    let followed: URLRequest? = await ask(refusal, session: session, task: task, response: response, redirect: URLRequest(url: target))

    #expect(refusal.refusedRedirect == (followed == nil))

    return followed

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
