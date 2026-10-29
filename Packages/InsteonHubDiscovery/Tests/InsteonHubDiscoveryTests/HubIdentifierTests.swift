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

    let results = try await identifier.identify(
      [hub("10.0.0.5"), hub("10.0.0.9")],
      provideCredentials: { _ in credentials }
    )

    // The first Hub rejects the credentials, so the second is never contacted.
    #expect(results.count == 1)
    #expect(results[0].outcome.isAuthenticationFailure)

    let hosts = await client.hosts

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

}

/// Counts how many times the caller was asked for credentials.
actor AskedTracker {

  private(set) var count = 0

  func record() {

    count += 1

  }

}
