import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import InsteonNetworking
import InsteonTestSupport

/// The client for the local network: its session's settings, the proxies it refuses, and the
/// limits on a request's time. Nothing here is sent over a network.
struct LocalNetworkClientTests {

  // MARK: The session's settings

  @Test func theSessionUsesNoProxyAndKeepsNothing() throws {

    let configuration: URLSessionConfiguration = URLSessionHTTPClient.localNetwork().sessionConfiguration
    let proxies: [AnyHashable: Any] = try #require(configuration.connectionProxyDictionary)

    // Every kind of proxy is turned off, and none is named.
    for key in ["HTTPEnable", "HTTPSEnable", "SOCKSEnable", "ProxyAutoConfigEnable", "ProxyAutoDiscoveryEnable"] {

      #expect((proxies[key] as? Int) == 0)

    }

    for key in ["HTTPProxy", "HTTPSProxy", "SOCKSProxy", "ProxyAutoConfigURLString"] {

      #expect(!proxies.keys.contains(AnyHashable(key)))

    }

    #expect(configuration.urlCredentialStorage == nil)
    #expect(configuration.httpCookieStorage == nil)
    #expect(configuration.httpShouldSetCookies == false)
    #expect(configuration.httpCookieAcceptPolicy == .never)
    #expect(configuration.urlCache == nil)
    #expect((configuration.httpAdditionalHeaders ?? [:]).isEmpty)

  }

  @Test func theSessionLimitsARequestsTotalTime() {

    let configuration: URLSessionConfiguration = URLSessionHTTPClient.localNetwork(resourceTimeout: .seconds(7)).sessionConfiguration

    #expect(configuration.timeoutIntervalForResource == 7)

  }

  @Test func theClientFollowsNoRedirectsAndReadsALimitedAnswer() {

    let client: URLSessionHTTPClient = URLSessionHTTPClient.localNetwork()

    #expect(client.redirectPolicy == .refuseAll)
    #expect(client.maximumResponseSize == 64 * 1024)
    #expect(URLSessionHTTPClient.localNetwork(maximumResponseSize: 10).maximumResponseSize == 10)

  }

  // It's for HTTPS to the internet without credentials, so it uses the system's proxy.
  @Test func anEphemeralClientKeepsNothingAndKeepsItsPolicy() {

    let client: URLSessionHTTPClient = URLSessionHTTPClient.ephemeral(
      redirectPolicy: .sameOriginHTTPSOnly,
      maximumResponseSize: 1_024,
      resourceTimeout: .seconds(30)
    )
    let configuration: URLSessionConfiguration = client.sessionConfiguration

    #expect(client.redirectPolicy == .sameOriginHTTPSOnly)
    #expect(client.maximumResponseSize == 1_024)
    #expect(configuration.urlCredentialStorage == nil)
    #expect(configuration.httpCookieStorage == nil)
    #expect(configuration.urlCache == nil)
    #expect(configuration.connectionProxyDictionary?.isEmpty ?? true)
    #expect(configuration.timeoutIntervalForResource == 30)
    #expect(!client.sessionStoresCredentials)
    #expect(!client.sessionAddsCredentials)

  }

  @Test func aClientWithoutALimitReadsAnyAnswer() {

    #expect(URLSessionHTTPClient().maximumResponseSize == nil)

  }

  // MARK: Proxies in the environment

  static let hubURL: URL = URL(string: "http://192.168.1.20:25105/buffstatus.xml")!

  @Test(arguments: [
    ["http_proxy": "http://127.0.0.1:9"],
    ["HTTP_PROXY": "http://127.0.0.1:9"],
    ["all_proxy": "socks5://127.0.0.1:9"],
    ["ALL_PROXY": "http://127.0.0.1:9"],
    // An address range in no_proxy doesn't count, since older libcurl doesn't read ranges.
    ["http_proxy": "http://127.0.0.1:9", "no_proxy": "192.168.0.0/16"],
    ["http_proxy": "http://127.0.0.1:9", "no_proxy": "192.168.1.2, .example.com"],
    // A wildcard counts only as the whole of no_proxy, exactly as written.
    ["http_proxy": "http://127.0.0.1:9", "no_proxy": "localhost,*"],
    ["http_proxy": "http://127.0.0.1:9", "no_proxy": " *"],
    ["http_proxy": "http://127.0.0.1:9", "no_proxy": "*,"],
    // A no_proxy that's only spaces names nothing, and NO_PROXY isn't read in its place.
    ["http_proxy": "http://127.0.0.1:9", "no_proxy": "   "],
    ["http_proxy": "http://127.0.0.1:9", "no_proxy": " ", "NO_PROXY": "192.168.1.20"],
    // An address counts only as written, without a dot in front.
    ["http_proxy": "http://127.0.0.1:9", "no_proxy": ".192.168.1.20"],
    ["http_proxy": "http://127.0.0.1:9", "no_proxy": "1.20"],
    // A proxy of only spaces is still set.
    ["http_proxy": " "],
  ])
  func findsAProxyForTheHub(_ environment: [String: String]) {

    #expect(ProxyEnvironment(environment).proxies(Self.hubURL))

  }

  @Test(arguments: [
    [:],
    ["http_proxy": ""],
    ["https_proxy": "http://127.0.0.1:9"],
    ["http_proxy": "http://127.0.0.1:9", "no_proxy": "*"],
    ["http_proxy": "http://127.0.0.1:9", "no_proxy": "localhost, 192.168.1.20"],
    ["ALL_PROXY": "http://127.0.0.1:9", "NO_PROXY": "192.168.1.20"],
    ["http_proxy": "http://127.0.0.1:9", "no_proxy": "", "NO_PROXY": "192.168.1.20"],
  ])
  func findsNoProxyForTheHub(_ environment: [String: String]) {

    #expect(!ProxyEnvironment(environment).proxies(Self.hubURL))

  }

  @Test func aDomainInNoProxyCoversTheNamesInIt() throws {

    let environment: ProxyEnvironment = ProxyEnvironment(["https_proxy": "http://127.0.0.1:9", "no_proxy": ".example.com"])

    let hub: URL? = URL(string: "https://hub.example.com/")
    let elsewhere: URL? = URL(string: "https://example.org/")

    #expect(!environment.proxies(try #require(hub)))
    #expect(environment.proxies(try #require(elsewhere)))

  }

  #if canImport(FoundationNetworking)
  // Linux reads its proxy from the environment, so the client refuses the request before it's
  // sent.
  @Test(.timeLimit(.minutes(1))) func refusesARequestAProxyWouldCarry() async {

    let client: URLSessionHTTPClient = URLSessionHTTPClient.localNetwork(
      maximumResponseSize: 1_024,
      resourceTimeout: .seconds(5),
      environment: ["http_proxy": "http://127.0.0.1:9"]
    )

    await #expect(throws: HTTPClientError.proxyConfigured) {

      try await client.send(URLRequest(url: Self.hubURL))

    }

  }
  #endif

  // MARK: Deadlines

  @Test(.timeLimit(.minutes(1))) func aDeadlineEndsAnOperationThatNeverFinishes() async {

    let clock: TestClock = TestClock()

    let operation: Task<Int, any Error> = Task {

      try await withDeadline(.seconds(5), clock: clock) { () async throws -> Int in

        // Stops only when it's canceled.
        try await Task.sleep(for: .seconds(86_400))

        return 1

      }

    }

    await clock.waitForSleeper(until: .seconds(5))
    clock.advance(by: .seconds(5))

    let error = await #expect(throws: URLError.self) {

      _ = try await operation.value

    }

    #expect(error?.code == .timedOut)

  }

  @Test(.timeLimit(.minutes(1))) func aDeadlineKeepsTheResultOfAnOperationThatFinishes() async throws {

    let clock: TestClock = TestClock()

    let value: Int = try await withDeadline(.seconds(5), clock: clock) { 42 }

    #expect(value == 42)

  }

  @Test(.timeLimit(.minutes(1))) func aDeadlinePassesOnTheOperationsError() async {

    await #expect(throws: HTTPClientError.redirectRefused) {

      _ = try await withDeadline(.seconds(5), clock: TestClock()) { () async throws -> Int in

        throw HTTPClientError.redirectRefused

      }

    }

  }

}

/// A client that can't carry credentials refuses any request that does, before it's sent.
struct UnauthenticatedHTTPClientTests {

  @Test(.timeLimit(.minutes(1))) func sendsARequestWithoutCredentials() async throws {

    let stub: StubHTTPClient = StubHTTPClient(response: HTTPResponse(statusCode: 401))
    let client: UnauthenticatedHTTPClient = UnauthenticatedHTTPClient(transport: stub)

    let response: HTTPResponse = try await client.send(URLRequest(url: try #require(URL(string: "http://192.168.1.20:25105/buffstatus.xml"))))

    #expect(response.statusCode == 401)
    #expect(await stub.requests.count == 1)

  }

  @Test(.timeLimit(.minutes(1))) func refusesARequestWithAnAuthorizationHeader() async throws {

    let stub: StubHTTPClient = StubHTTPClient()
    let client: UnauthenticatedHTTPClient = UnauthenticatedHTTPClient(transport: stub)
    var request: URLRequest = URLRequest(url: try #require(URL(string: "http://192.168.1.20:25105/buffstatus.xml")))
    // Made-up credentials.
    request.setValue("Basic ZXhhbXBsZS11c2VyOmV4YW1wbGUtcGFzc3dvcmQ=", forHTTPHeaderField: "Authorization")

    await #expect(throws: HTTPClientError.credentialsRefused) {

      try await client.send(request)

    }

    #expect(await stub.requests.isEmpty)

  }

  @Test(.timeLimit(.minutes(1))) func refusesARequestWithCredentialsInItsAddress() async throws {

    let stub: StubHTTPClient = StubHTTPClient()
    let client: UnauthenticatedHTTPClient = UnauthenticatedHTTPClient(transport: stub)
    let request: URLRequest = URLRequest(url: try #require(URL(string: "http://user:password@192.168.1.20:25105/")))

    await #expect(throws: HTTPClientError.credentialsRefused) {

      try await client.send(request)

    }

    #expect(await stub.requests.isEmpty)

  }

  // The session would add the header to every request, so nothing is sent through it.
  @Test(.timeLimit(.minutes(1))) func refusesEveryRequestWhenTheSessionAddsCredentials() async throws {

    let configuration: URLSessionConfiguration = URLSessionConfiguration.ephemeral
    configuration.urlCredentialStorage = nil
    configuration.httpAdditionalHeaders = ["authorization": "Basic ZXhhbXBsZS11c2VyOmV4YW1wbGUtcGFzc3dvcmQ="]
    let client: UnauthenticatedHTTPClient = UnauthenticatedHTTPClient(URLSessionHTTPClient(session: URLSession(configuration: configuration)))
    let request: URLRequest = URLRequest(url: try #require(URL(string: "http://192.168.1.20:25105/buffstatus.xml")))

    await #expect(throws: HTTPClientError.credentialsRefused) {

      try await client.send(request)

    }

  }

  // A session with a credential storage could answer a server's challenge with credentials
  // saved for it, so nothing is sent through it.
  @Test(.timeLimit(.minutes(1))) func refusesEveryRequestWhenTheSessionStoresCredentials() async throws {

    let configuration: URLSessionConfiguration = URLSessionConfiguration.ephemeral
    configuration.urlCredentialStorage = URLCredentialStorage.shared
    let client: UnauthenticatedHTTPClient = UnauthenticatedHTTPClient(URLSessionHTTPClient(session: URLSession(configuration: configuration)))
    let request: URLRequest = URLRequest(url: try #require(URL(string: "http://192.168.1.20:25105/buffstatus.xml")))

    await #expect(throws: HTTPClientError.credentialsRefused) {

      try await client.send(request)

    }

  }

  @Test func theLocalNetworkClientsSessionAddsAndStoresNoCredentials() {

    let client: URLSessionHTTPClient = URLSessionHTTPClient.localNetwork()

    #expect(!client.sessionAddsCredentials)
    #expect(!client.sessionStoresCredentials)

  }

}
