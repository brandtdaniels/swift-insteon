import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import InsteonHubClient
import InsteonHubDiscovery
import InsteonHubPro
import InsteonNetworking

/// A made-up network: each host answers as a test scripts it, per port and path, and every
/// request is recorded as `METHOD URL`.
actor ScriptedNetwork: HTTPClient {

  struct Address: Hashable, Sendable {

    var host: String
    var port: Int
    var path: String

  }

  private(set) var requests: [(method: String, url: String, authorization: String?)] = []

  private let answers: [Address: HTTPResponse]

  /// - Parameter answers: The response for each address, or nothing when the address is absent,
  ///   which refuses the connection.
  init(_ answers: [Address: HTTPResponse]) {

    self.answers = answers

  }

  func send(_ request: URLRequest) async throws -> HTTPResponse {

    let url = try #require(request.url)

    requests.append((request.httpMethod ?? "GET", url.absoluteString, request.value(forHTTPHeaderField: "Authorization")))

    guard let host = url.host, let response = answers[Address(host: host, port: url.port ?? 80, path: url.path)] else {

      throw URLError(.cannotConnectToHost)

    }

    return response

  }

  /// The requests sent to one host, in order.
  func requests(to host: String) -> [String] {

    requests.filter { URL(string: $0.url)?.host == host }.map { "\($0.method) \($0.url)" }

  }

}

@Suite(.timeLimit(.minutes(1)))
struct HubProDiscoveryTests {

  static let settings = Data(#"{"network":{"address":"10.0.0.2","dns":"10.0.0.254","gateway":"10.0.0.254","mask":"255.255.255.0","mode":"dhcp","port":0},"time":"11/19/2026 05:18:53 PM","version":{"config":{"rollback":"","update":"","version":"5.0.1"},"server":{"rollback":"","update":"","version":"1.0.2"}}}"#.utf8)

  static let bufferPage = HTTPResponse(statusCode: 401, headers: ["WWW-Authenticate": "Basic realm=\"Hub\""])

  /// A Hub on the Hub's port, a Hub Pro, a printer, a router, a sprinkler controller, a host
  /// that gates like a Hub Pro but isn't one, and silent hosts, each at its own address.
  static func network() -> ScriptedNetwork {

    func address(_ host: String, _ port: Int, _ path: String) -> ScriptedNetwork.Address {

      ScriptedNetwork.Address(host: host, port: port, path: path)

    }

    return ScriptedNetwork([
      address("10.0.0.1", 25105, "/buffstatus.xml"): bufferPage,
      address("10.0.0.2", 80, "/"): HTTPResponse(statusCode: 401),
      address("10.0.0.2", 80, "/settings"): HTTPResponse(statusCode: 200, body: settings),
      address("10.0.0.3", 80, "/"): HTTPResponse(statusCode: 404),
      address("10.0.0.4", 80, "/"): HTTPResponse(statusCode: 401, headers: ["WWW-Authenticate": "Basic realm=\"router\""]),
      address("10.0.0.5", 80, "/"): HTTPResponse(statusCode: 200, body: Data("<html></html>".utf8)),
      address("10.0.0.6", 80, "/"): HTTPResponse(statusCode: 401),
      address("10.0.0.6", 80, "/settings"): HTTPResponse(statusCode: 404),
      address("10.0.0.7", 80, "/"): HTTPResponse(statusCode: 401),
      address("10.0.0.7", 80, "/settings"): HTTPResponse(statusCode: 200, body: Data(#"{"network":"none"}"#.utf8)),
    ])

  }

  func discovery(_ network: ScriptedNetwork, hubProPorts: [Int] = [80]) throws -> HubDiscovery {

    let subnet = try #require(IPv4Subnet(address: "10.0.0.1", prefixLength: 28))

    return HubDiscovery(
      httpClient: UnauthenticatedHTTPClient(transport: network),
      network: FixedNetwork(fixed: [subnet]),
      hubProPorts: hubProPorts,
      probeTimeout: HubDiscoveryTests.noTimeout
    )

  }

  @Test func findsAHubOnItsInterfaceAndAHubProOnItsSettings() async throws {

    let network = Self.network()

    let hubs = try await discovery(network).discover()

    #expect(hubs.map(\.endpoint) == [HubEndpoint(host: "10.0.0.1"), HubEndpoint(host: "10.0.0.2", port: 80)])
    #expect(hubs.map(\.kind) == [.hub, .hubPro])

  }

  @Test func asksAHubOnlyForItsBufferPage() async throws {

    let network = Self.network()

    _ = try await discovery(network).discover()

    #expect(await network.requests(to: "10.0.0.1") == ["GET http://10.0.0.1:25105/buffstatus.xml"])

  }

  @Test func asksAHubProForItsRootThenItsSettings() async throws {

    let network = Self.network()

    _ = try await discovery(network).discover()

    #expect(await network.requests(to: "10.0.0.2") == [
      "GET http://10.0.0.2:25105/buffstatus.xml",
      "GET http://10.0.0.2:80/",
      "GET http://10.0.0.2:80/settings",
    ])

  }

  @Test func sendsNoSettingsRequestToAPrinterARouterOrASprinklerController() async throws {

    let network = Self.network()

    let hubs = try await discovery(network).discover()

    for host in ["10.0.0.3", "10.0.0.4", "10.0.0.5"] {

      #expect(await network.requests(to: host) == ["GET http://\(host):25105/buffstatus.xml", "GET http://\(host):80/"])
      #expect(!hubs.contains { $0.endpoint.host == host })

    }

  }

  @Test func doesNotListAHostWhoseSettingsAreNotAHubProsSettings() async throws {

    let network = Self.network()

    let hubs = try await discovery(network).discover()

    #expect(await network.requests(to: "10.0.0.6").last == "GET http://10.0.0.6:80/settings")
    #expect(await network.requests(to: "10.0.0.7").last == "GET http://10.0.0.7:80/settings")
    #expect(!hubs.contains { ["10.0.0.6", "10.0.0.7"].contains($0.endpoint.host) })

  }

  @Test func asksAHostThatRefusesEverythingOnlyOnEachPort() async throws {

    let network = Self.network()

    _ = try await discovery(network).discover()

    #expect(await network.requests(to: "10.0.0.9") == ["GET http://10.0.0.9:25105/buffstatus.xml", "GET http://10.0.0.9:80/"])

  }

  @Test func sendsOnlyReadsWithoutCredentials() async throws {

    let network = Self.network()

    _ = try await discovery(network).discover()

    let requests = await network.requests

    #expect(requests.allSatisfy { $0.method == "GET" })
    #expect(requests.allSatisfy { $0.authorization == nil })

  }

  @Test func looksForNoHubProWithoutAPortToLookOn() async throws {

    let network = Self.network()

    let hubs = try await discovery(network, hubProPorts: []).discover()

    #expect(hubs.map(\.endpoint.host) == ["10.0.0.1"])
    #expect(await network.requests(to: "10.0.0.2") == ["GET http://10.0.0.2:25105/buffstatus.xml"])

  }

  @Test func recognizesOneHostAsAHubPro() async throws {

    let network = Self.network()
    let probe = HubProProbe(port: 80, httpClient: UnauthenticatedHTTPClient(transport: network))

    let hub = try await probe.probe(host: "10.0.0.2")

    #expect(hub?.endpoint == HubEndpoint(host: "10.0.0.2", port: 80))
    #expect(hub?.kind == .hubPro)
    #expect(hub?.hubProSettings?.network.address == "10.0.0.2")
    #expect(hub?.hubProSettings?.version.config.version == "5.0.1")
    #expect(hub?.hubProSettings?.version.server.version == "1.0.2")
    #expect(try await probe.probe(host: "10.0.0.3") == nil)

  }

  @Test func aHubKeepsItsKindWhenMerged() {

    var local = DiscoveredHub(endpoint: HubEndpoint(host: "10.0.0.2", port: 80), kind: .hubPro)

    local.merge(with: DiscoveredHub(endpoint: HubEndpoint(host: "10.0.0.2", port: 80), unitType: "HubPro"))

    #expect(local.kind == .hubPro)

    var listed = DiscoveredHub(endpoint: HubEndpoint(host: "10.0.0.2", port: 80))

    listed.merge(with: local)

    #expect(listed.kind == .hubPro)

  }

}
