import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import InsteonHubClient
import InsteonHubDiscovery
import InsteonNetworking
import InsteonProtocol

/// Records every request and answers each with a fixed HTTP status, standing in for a Hub that
/// rejects credentials. Made-up addresses only, never a real one.
actor RecordingHTTPClient: HTTPClient {

  private(set) var hosts: [String] = []

  private let status: Int

  /// - Parameter status: The HTTP status to answer every request with.
  init(status: Int) {

    self.status = status

  }

  func send(_ request: URLRequest) async throws -> HTTPResponse {

    if let host = request.url?.host {

      hosts.append(host)

    }

    return HTTPResponse(statusCode: status)

  }

}

struct HubIdentifierTests {

  let credentials = HubIdentifier.Credentials(user: "user", password: "secret")

  func hub(_ host: String, port: Int = HubEndpoint.defaultPort) -> DiscoveredHub {

    DiscoveredHub(endpoint: HubEndpoint(host: host, port: port))

  }

  @Test func stopsAtTheFirstRejection() async throws {

    let client = RecordingHTTPClient(status: 401)
    let identifier = HubIdentifier(httpClient: client, timeout: .seconds(5))

    let credentials: HubIdentifier.Credentials = self.credentials
    let results = try await identifier.identify(
      [hub("10.0.0.5"), hub("10.0.0.9")],
      provideCredentials: { _ in credentials }
    )

    // The first Hub rejects the credentials, so the second is never contacted.
    #expect(results.count == 1)
    #expect(results[0].outcome.isAuthenticationFailure)

    let hosts = await client.hosts

    #expect(hosts.contains("10.0.0.5"))
    #expect(hosts.allSatisfy { $0 == "10.0.0.5" })
    #expect(!hosts.contains("10.0.0.9"))

  }

  @Test func treats403AsARejection() async throws {

    let client = RecordingHTTPClient(status: 403)
    let identifier = HubIdentifier(httpClient: client, timeout: .seconds(5))

    let outcome = try await identifier.identify(hub("10.0.0.5"), credentials: credentials)

    #expect(outcome.isAuthenticationFailure)

  }

  @Test func neverContactsAPublicAddress() async throws {

    let client = RecordingHTTPClient(status: 401)
    let identifier = HubIdentifier(httpClient: client)
    let asked = AskedTracker()

    let credentials: HubIdentifier.Credentials = self.credentials
    let results = try await identifier.identify(
      [hub("203.0.113.5")],
      provideCredentials: { _ in await asked.record(); return credentials }
    )

    #expect(results.count == 1)

    if case .skippedNonPrivateAddress = results[0].outcome {

    } else {

      Issue.record("Expected a public address to be skipped")

    }

    #expect(await client.hosts.isEmpty)
    #expect(await asked.count == 0)

  }

  @Test func neverUsesANonHubPort() async throws {

    let client = RecordingHTTPClient(status: 401)
    let identifier = HubIdentifier(httpClient: client)
    let asked = AskedTracker()

    let credentials: HubIdentifier.Credentials = self.credentials
    let results = try await identifier.identify(
      [hub("10.0.0.5", port: 8080)],
      provideCredentials: { _ in await asked.record(); return credentials }
    )

    #expect(results.count == 1)

    if case .skippedNonHubPort = results[0].outcome {

    } else {

      Issue.record("Expected a non-Hub port to be skipped")

    }

    #expect(await client.hosts.isEmpty)
    #expect(await asked.count == 0)

  }

  @Test func doesNotSendWhenTheCallerDeclines() async throws {

    let client = RecordingHTTPClient(status: 401)
    let identifier = HubIdentifier(httpClient: client)

    let results = try await identifier.identify([hub("10.0.0.5")], provideCredentials: { _ in nil })

    #expect(results.count == 1)

    if case .declined = results[0].outcome {

    } else {

      Issue.record("Expected a declined candidate")

    }

    #expect(await client.hosts.isEmpty)

  }

  // A Hub named deliberately is contacted whatever its port, which is how '--identify HOST:PORT'
  // reaches a Hub on another port; the address must still be private.
  @Test func identifiesANamedHubOnAnotherPort() async throws {

    let client = RecordingHTTPClient(status: 401)
    let identifier = HubIdentifier(httpClient: client, timeout: .seconds(5))

    let outcome = try await identifier.identify(hub("10.0.0.5", port: 8080), credentials: credentials)

    #expect(outcome.isAuthenticationFailure)
    #expect(await client.hosts.contains("10.0.0.5"))

  }

  @Test func skipsANamedPublicHub() async throws {

    let client = RecordingHTTPClient(status: 401)
    let identifier = HubIdentifier(httpClient: client)

    let outcome = try await identifier.identify(hub("203.0.113.5"), credentials: credentials)

    if case .skippedNonPrivateAddress = outcome {

    } else {

      Issue.record("Expected a public address to be skipped")

    }

    #expect(await client.hosts.isEmpty)

  }

  // A host name isn't a private address, so it's skipped before anyone is asked about it, and
  // nothing is sent to it.
  @Test func neverContactsAHostName() async throws {

    let client = RecordingHTTPClient(status: 401)
    let identifier = HubIdentifier(httpClient: client)
    let asked = AskedTracker()
    let reported = Recorded<String>()
    let credentials: HubIdentifier.Credentials = self.credentials

    let results = try await identifier.identify(
      [hub("hub.local")],
      provideCredentials: { _ in await asked.record(); return credentials },
      onResult: { candidate, _ in reported.append(candidate.endpoint.host) }
    )

    #expect(results.count == 1)

    if case .skippedNonPrivateAddress = results[0].outcome {

    } else {

      Issue.record("Expected a host name to be skipped")

    }

    #expect(reported.values == ["hub.local"])
    #expect(await client.hosts.isEmpty)
    #expect(await asked.count == 0)

  }

  // The client never answers, so the identifier gives up after its timeout, which is short
  // here, and reports that the candidate didn't answer.
  @Test func reportsACandidateThatNeverAnswers() async throws {

    let identifier = HubIdentifier(httpClient: SilentHTTPClient(), timeout: .milliseconds(50))

    let outcome = try await identifier.identify(hub("10.0.0.5"), credentials: credentials)

    if case .didNotAnswer = outcome {

    } else {

      Issue.record("Expected a candidate that never answers to be reported as not answering")

    }

  }

  @Test func credentialsRedactThemselves() {

    let credentials = HubIdentifier.Credentials(user: "example-user", password: "example-password")

    var dumped: String = ""
    dump(credentials, to: &dumped)

    let texts: [String] = [
      String(describing: credentials),
      "\(credentials)",
      String(reflecting: credentials),
      dumped
    ]

    for text in texts {

      #expect(!text.contains("example-user"))
      #expect(!text.contains("example-password"))

    }

    #expect(Mirror(reflecting: credentials).children.isEmpty)

  }

}

/// Never answers a request, standing in for a candidate that doesn't respond. The wait ends when
/// the request's task is canceled.
struct SilentHTTPClient: HTTPClient {

  func send(_ request: URLRequest) async throws -> HTTPResponse {

    try await Task.sleep(for: .seconds(60))

    throw URLError(.timedOut)

  }

}

/// Values a `@Sendable` callback reports, kept behind a lock.
final class Recorded<Value: Sendable>: @unchecked Sendable {

  private let lock = NSLock()

  private var recorded: [Value] = []

  /// The values reported so far, oldest first.
  var values: [Value] {

    lock.withLock { recorded }

  }

  /// Records a value.
  func append(_ value: Value) {

    lock.withLock { recorded.append(value) }

  }

}

/// Counts how many times the caller was asked for credentials.
actor AskedTracker {

  private(set) var count = 0

  func record() {

    count += 1

  }

}
