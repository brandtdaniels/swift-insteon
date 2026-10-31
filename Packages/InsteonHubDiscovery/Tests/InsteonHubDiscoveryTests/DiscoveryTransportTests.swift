import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import InsteonHubClient
import InsteonHubDiscovery
import InsteonNetworking
import InsteonProtocol

/// What discovery, the Insteon Connect lookup and identification send, and the limits on
/// them. The clients are stubs, or sessions that refuse before sending, so nothing reaches a
/// network.
@Suite(.timeLimit(.minutes(1)))
struct DiscoveryTransportTests {

  func subnet(_ address: String, _ prefixLength: Int) throws -> IPv4Subnet {

    try #require(IPv4Subnet(address: address, prefixLength: prefixLength))

  }

  /// A client whose session would add an `Authorization` header to every request.
  static func credentialedSessionClient() -> UnauthenticatedHTTPClient {

    let configuration: URLSessionConfiguration = URLSessionConfiguration.ephemeral
    configuration.urlCredentialStorage = nil
    // Made-up credentials.
    configuration.httpAdditionalHeaders = ["Authorization": "Basic ZXhhbXBsZS11c2VyOmV4YW1wbGUtcGFzc3dvcmQ="]

    return UnauthenticatedHTTPClient(URLSessionHTTPClient(session: URLSession(configuration: configuration)))

  }

  // MARK: Discovery

  // A client that would send credentials to every address is refused before any probe.
  @Test func discoveryRefusesASessionThatAddsCredentials() async throws {

    let discovery = HubDiscovery(
      httpClient: Self.credentialedSessionClient(),
      network: FixedNetwork(fixed: [try subnet("192.168.1.5", 30)])
    )

    await #expect(throws: HTTPClientError.credentialsRefused) {

      try await discovery.discover()

    }

  }

  // An address that never answers costs at most the probe timeout, however it answers.
  @Test func discoveryGivesUpOnAnAddressAfterTheProbeTimeout() async throws {

    let discovery = HubDiscovery(
      httpClient: UnauthenticatedHTTPClient(transport: SilentHTTPClient()),
      network: FixedNetwork(fixed: [try subnet("192.168.1.5", 30)]),
      probeTimeout: .milliseconds(20)
    )

    #expect(try await discovery.discover().isEmpty)

  }

  #if canImport(FoundationNetworking)
  // Linux reads its proxy from the environment, so discovery says why it found nothing
  // rather than finding nothing.
  @Test func discoveryReportsAProxyItWontUse() async throws {

    let client = URLSessionHTTPClient.localNetwork(
      maximumResponseSize: 1_024,
      resourceTimeout: .seconds(5),
      environment: ["http_proxy": "http://127.0.0.1:9"]
    )
    let discovery = HubDiscovery(httpClient: UnauthenticatedHTTPClient(client), network: FixedNetwork(fixed: [try subnet("192.168.1.5", 30)]))

    await #expect(throws: HTTPClientError.proxyConfigured) {

      try await discovery.discover()

    }

  }
  #endif

  // MARK: The Insteon Connect lookup

  @Test func theLookupSendsNoCredentialsCookiesOrIdentity() async throws {

    let page = GetInfoPage.page(GetInfoPage.hubBlock(link: "http://10.0.1.10:25105", insteonID: "A0.B1.C2"))
    let client = ScriptedHTTPClient { _ in HTTPResponse(statusCode: 200, body: Data(page.utf8)) }

    _ = try await InsteonConnectLookup(httpClient: UnauthenticatedHTTPClient(transport: client)).hubs()

    let request = try #require(await client.requests.first)

    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
    #expect(request.httpShouldHandleCookies == false)
    #expect(request.value(forHTTPHeaderField: "User-Agent") == InsteonConnectLookup.userAgent)
    #expect(request.value(forHTTPHeaderField: "Accept-Language") == "en")

  }

  @Test func theLookupRefusesASessionThatAddsCredentials() async {

    await #expect(throws: HTTPClientError.credentialsRefused) {

      try await InsteonConnectLookup(httpClient: Self.credentialedSessionClient()).hubs()

    }

  }

  @Test func theLookupRefusesAPageLargerThanItReads() async {

    let body = Data(repeating: 0x20, count: InsteonConnectLookup.maximumResponseSize + 1)
    let client = ScriptedHTTPClient { _ in HTTPResponse(statusCode: 200, body: body) }

    await #expect(throws: HTTPClientError.responseTooLarge(limit: InsteonConnectLookup.maximumResponseSize)) {

      try await InsteonConnectLookup(httpClient: UnauthenticatedHTTPClient(transport: client)).hubs()

    }

  }

  @Test func theLookupGivesUpAfterItsTimeoutInAll() async {

    let lookup = InsteonConnectLookup(httpClient: UnauthenticatedHTTPClient(transport: SilentHTTPClient()), timeout: .milliseconds(20))

    let error = await #expect(throws: URLError.self) {

      try await lookup.hubs()

    }

    #expect(error?.code == .timedOut)

  }

  // MARK: Identification

  // The candidate rejects the credentials, so they go to it once: the connection stops at the
  // first rejection rather than clearing the buffer again for the command.
  @Test func identificationSendsTheCredentialsToARejectingCandidateOnce() async throws {

    let client = RecordingHTTPClient(status: 401)
    let identifier = HubIdentifier(httpClient: client, timeout: .seconds(30))

    let outcome = try await identifier.identify(
      DiscoveredHub(endpoint: HubEndpoint(host: "10.0.0.5")),
      credentials: HubIdentifier.Credentials(user: "user", password: "secret")
    )

    #expect(outcome.isAuthenticationFailure)
    #expect(await client.hosts == ["10.0.0.5"])

  }

}
