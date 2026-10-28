import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import InsteonHubClient
import InsteonHubDiscovery
import InsteonNetworking

/// A network with fixed subnets.
struct FixedNetwork: LocalNetwork {

  let fixed: [IPv4Subnet]

  func subnets() throws -> [IPv4Subnet] {

    fixed

  }

}

/// Answers each host as a test says, and records every request.
actor ScriptedHTTPClient: HTTPClient {

  private(set) var requests: [URLRequest] = []

  private let answer: @Sendable (String) -> HTTPResponse?

  /// - Parameter answer: The response for a host, or `nil` if nothing answers there.
  init(answer: @escaping @Sendable (String) -> HTTPResponse?) {

    self.answer = answer

  }

  func send(_ request: URLRequest) async throws -> HTTPResponse {

    requests.append(request)

    guard let host = request.url?.host, let response = answer(host) else {

      throw URLError(.cannotConnectToHost)

    }

    return response

  }

}

struct HubDiscoveryTests {

  let hubChallenge = HTTPResponse(statusCode: 401, headers: ["WWW-Authenticate": "Basic realm=\"Insteon Hub\""])

  func subnet(_ address: String, _ prefixLength: Int) throws -> IPv4Subnet {

    try #require(IPv4Subnet(address: address, prefixLength: prefixLength))

  }

  @Test func findsTheAddressesThatAnswerAsAHub() async throws {

    let hubChallenge = hubChallenge
    let client = ScriptedHTTPClient { host in

      switch host {
      case "192.168.1.20", "192.168.1.200": hubChallenge
      // A web server that isn't a Hub.
      case "192.168.1.30": HTTPResponse(statusCode: 200)
      default: nil
      }

    }
    let discovery = HubDiscovery(httpClient: client, network: FixedNetwork(fixed: [try subnet("192.168.1.5", 24)]))

    let hubs = try await discovery.discover()

    #expect(hubs.map(\.endpoint) == [
      HubEndpoint(host: "192.168.1.20"),
      HubEndpoint(host: "192.168.1.200"),
    ])
    #expect(await client.requests.count == 254)

  }

  @Test func asksForTheBufferPageWithoutCredentials() async throws {

    let hubChallenge = hubChallenge
    let client = ScriptedHTTPClient { _ in hubChallenge }
    let discovery = HubDiscovery(
      httpClient: client,
      network: FixedNetwork(fixed: [try subnet("10.0.0.1", 30)]),
      probeTimeout: .milliseconds(1_500)
    )

    _ = try await discovery.discover()

    let requests = await client.requests

    #expect(requests.compactMap(\.url?.absoluteString).sorted() == [
      "http://10.0.0.1:25105/buffstatus.xml",
      "http://10.0.0.2:25105/buffstatus.xml",
    ])
    #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
    #expect(requests.allSatisfy { $0.timeoutInterval == 1.5 })

  }

  @Test func reportsEachHubAsItsFound() async throws {

    let hubChallenge = hubChallenge
    let client = ScriptedHTTPClient { $0 == "10.0.0.2" ? hubChallenge : nil }
    let discovery = HubDiscovery(httpClient: client, network: FixedNetwork(fixed: [try subnet("10.0.0.1", 29)]))
    let found = Found()

    _ = try await discovery.discover { await found.append($0) }

    #expect(await found.hubs == [DiscoveredHub(endpoint: HubEndpoint(host: "10.0.0.2"))])

  }

  @Test func skipsSubnetsLargerThanTheLimit() async throws {

    let client = ScriptedHTTPClient { _ in nil }
    let discovery = HubDiscovery(httpClient: client, network: FixedNetwork(fixed: [try subnet("10.0.0.1", 16)]))

    let hubs = try await discovery.discover()

    #expect(hubs.isEmpty)
    #expect(await client.requests.isEmpty)

  }

  // A cellular or public network belongs to other people, so it's never searched.
  @Test func searchesOnlyPrivateNetworks() async throws {

    let client = ScriptedHTTPClient { _ in nil }
    let network = FixedNetwork(fixed: [try subnet("100.64.12.7", 24), try subnet("203.0.113.9", 24)])

    _ = try await HubDiscovery(httpClient: client, network: network).discover()

    #expect(await client.requests.isEmpty)

  }

  @Test func returnsHubsInAddressOrder() async throws {

    let hubChallenge = hubChallenge
    let client = ScriptedHTTPClient { ["10.0.0.5", "10.0.1.9"].contains($0) ? hubChallenge : nil }
    // The second subnet starts at a lower address than the first.
    let network = FixedNetwork(fixed: [try subnet("10.0.1.50", 24), try subnet("10.0.0.10", 23)])

    let hubs = try await HubDiscovery(httpClient: client, network: network).discover()

    #expect(hubs.map(\.endpoint.host) == ["10.0.0.5", "10.0.1.9"])

  }

  @Test func asksEachAddressOnceWhenSubnetsOverlap() async throws {

    let client = ScriptedHTTPClient { _ in nil }
    let network = FixedNetwork(fixed: [try subnet("10.0.0.1", 30), try subnet("10.0.0.2", 30)])

    _ = try await HubDiscovery(httpClient: client, network: network).discover()

    #expect(await client.requests.count == 2)

  }

  @Test func asksNoMoreAddressesAtOnceThanAllowed() async throws {

    let gate = Gate()
    let client = GatedHTTPClient(gate: gate)
    let discovery = HubDiscovery(
      httpClient: client,
      network: FixedNetwork(fixed: [try subnet("10.0.0.1", 28)]),
      concurrentProbes: 4
    )

    async let hubs = discovery.discover()

    await gate.waitForWaiters(4)
    #expect(await gate.waiting == 4)

    await gate.openAll()
    _ = try await hubs

    #expect(await gate.mostWaiting == 4)

  }

}

/// The Hubs a discovery reported, in order.
actor Found {

  private(set) var hubs: [DiscoveredHub] = []

  func append(_ hub: DiscoveredHub) {

    hubs.append(hub)

  }

}

/// Holds requests until a test opens it, counting how many wait at once.
actor Gate {

  private(set) var waiting = 0

  private(set) var mostWaiting = 0

  private var isOpen = false

  private var held: [CheckedContinuation<Void, Never>] = []

  private var watchers: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

  func pass() async {

    guard !isOpen else {

      return

    }

    waiting += 1
    mostWaiting = max(mostWaiting, waiting)

    for watcher in watchers where waiting >= watcher.count {

      watcher.continuation.resume()

    }

    watchers.removeAll { waiting >= $0.count }

    await withCheckedContinuation { held.append($0) }

    waiting -= 1

  }

  func waitForWaiters(_ count: Int) async {

    guard waiting < count else {

      return

    }

    await withCheckedContinuation { watchers.append((count, $0)) }

  }

  func openAll() {

    isOpen = true

    for continuation in held {

      continuation.resume()

    }

    held.removeAll()

  }

}

/// A client whose requests wait at a gate, then find nothing listening.
struct GatedHTTPClient: HTTPClient {

  let gate: Gate

  func send(_ request: URLRequest) async throws -> HTTPResponse {

    await gate.pass()

    throw URLError(.cannotConnectToHost)

  }

}

struct IPv4SubnetTests {

  @Test func readsDottedDecimal() throws {

    let subnet = try #require(IPv4Subnet(address: "192.168.1.20", prefixLength: 24))

    #expect(subnet.description == "192.168.1.0/24")
    #expect(subnet.hosts.first == "192.168.1.1")
    #expect(subnet.hosts.last == "192.168.1.254")

  }

  @Test(arguments: ["+192.168.1.20", "192.168.1", "192.168.1.256", "192.168..20", "192.168.1.٢"])
  func rejectsAddressesThatArentDottedDecimal(_ address: String) {

    #expect(IPv4Subnet(address: address, prefixLength: 24) == nil)

  }

  @Test func hasNoHostsInASubnetOfOneAddress() throws {

    #expect(try #require(IPv4Subnet(address: "255.255.255.255", prefixLength: 32)).hosts.isEmpty)

  }

  @Test(arguments: [("10.1.2.3", 24, true), ("172.20.0.1", 16, true), ("192.168.0.1", 24, true), ("172.32.0.1", 24, false), ("100.64.0.1", 24, false), ("10.0.0.1", 7, false)])
  func knowsThePrivateRanges(_ address: String, _ prefixLength: Int, _ isPrivate: Bool) throws {

    #expect(try #require(IPv4Subnet(address: address, prefixLength: prefixLength)).isPrivate == isPrivate)

  }

}
