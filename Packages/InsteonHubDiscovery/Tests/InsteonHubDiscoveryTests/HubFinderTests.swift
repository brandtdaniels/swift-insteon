import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import InsteonHubClient
import InsteonHubDiscovery
import InsteonNetworking
import InsteonProtocol

/// ``HubFinder`` runs the local search and the Insteon Connect lookup against stubbed HTTP
/// clients, with made-up private addresses, and never a real one.
@Suite(.timeLimit(.minutes(1)))
struct HubFinderTests {

  let hubChallenge = HTTPResponse(statusCode: 401, headers: ["WWW-Authenticate": "Basic realm=\"Insteon Hub\""])

  func subnet(_ address: String, _ prefixLength: Int) throws -> IPv4Subnet {

    try #require(IPv4Subnet(address: address, prefixLength: prefixLength))

  }

  /// A finder whose local search answers a Hub at `localHubs`, and whose Insteon Connect lookup
  /// returns `page`.
  func finder(network: IPv4Subnet, localHubs: Set<String>, page: String?) -> HubFinder {

    let hubChallenge = hubChallenge
    let local = ScriptedHTTPClient { localHubs.contains($0) ? hubChallenge : nil }
    let connect = ScriptedHTTPClient { host in

      guard host == "connect.insteon.com", let page else {

        return nil

      }

      return HTTPResponse(statusCode: 200, body: Data(page.utf8))

    }

    return HubFinder(
      discovery: HubDiscovery(httpClient: UnauthenticatedHTTPClient(transport: local), network: FixedNetwork(fixed: [network])),
      lookup: InsteonConnectLookup(httpClient: UnauthenticatedHTTPClient(transport: connect))
    )

  }

  @Test func mergesTheSameHubFoundBothWays() async throws {

    let page = GetInfoPage.page(GetInfoPage.cardBlock(address: "10.0.1.10", insteonID: "1A.2B.3C"))
    let finder = try finder(network: subnet("10.0.1.10", 24), localHubs: ["10.0.1.10"], page: page)

    let result = try await finder.find(searchesLocalNetwork: true, asksInsteonConnect: true, findsAllHubs: true)

    #expect(result.hubs.count == 1)

    let hub = try #require(result.hubs.first)

    #expect(hub.endpoint == HubEndpoint(host: "10.0.1.10"))
    #expect(hub.foundBy == [.localNetwork, .insteonConnect])
    // The Insteon ID and model come from Insteon Connect, which the merge keeps.
    #expect(hub.insteonID == InsteonAddress("1A.2B.3C"))
    #expect(hub.category == DeviceCategory(rawValue: 0x03))
    #expect(result.localNetworkError == nil)
    #expect(result.insteonConnectError == nil)

  }

  @Test func tagsEachWayThatFoundAHub() async throws {

    let localOnly = try finder(network: subnet("10.0.1.10", 24), localHubs: ["10.0.1.10"], page: nil)
    let local = try await localOnly.find(searchesLocalNetwork: true, asksInsteonConnect: false, findsAllHubs: true)

    #expect(local.hubs.map(\.foundBy) == [[.localNetwork]])

    let page = GetInfoPage.page(GetInfoPage.cardBlock(address: "10.0.1.20", insteonID: "4D.5E.6F"))
    let connectOnly = try finder(network: subnet("10.0.1.10", 24), localHubs: [], page: page)
    let connect = try await connectOnly.find(searchesLocalNetwork: false, asksInsteonConnect: true)

    #expect(connect.hubs.map(\.foundBy) == [[.insteonConnect]])

  }

  @Test func stopsTheLocalSearchAtTheFirstHub() async throws {

    let finder = try finder(network: subnet("10.0.0.1", 24), localHubs: ["10.0.0.5", "10.0.0.9"], page: nil)

    let search = try await finder.searchLocalNetwork(stoppingAtFirstHub: true)

    // The probes answer concurrently, so either Hub may be the first to answer.
    #expect(search.stoppedAtFirstHub)
    #expect(search.hubs.count == 1)
    #expect(search.hubs.allSatisfy { ["10.0.0.5", "10.0.0.9"].contains($0.endpoint.host) })
    #expect(search.hubs.allSatisfy { $0.foundBy == [.localNetwork] })

  }

  @Test func findsEveryHubWhenAskedForAll() async throws {

    let finder = try finder(network: subnet("10.0.0.1", 24), localHubs: ["10.0.0.5", "10.0.0.9"], page: nil)

    let search = try await finder.searchLocalNetwork(stoppingAtFirstHub: false)

    #expect(!search.stoppedAtFirstHub)
    #expect(search.hubs.map(\.endpoint.host) == ["10.0.0.5", "10.0.0.9"])

  }

  @Test func keepsAWayGoingWhenTheOtherFails() async throws {

    // Insteon Connect answers with a page that can't be read, but the local search still finds a
    // Hub, so the result carries the Hub and the lookup's error.
    let finder = try finder(network: subnet("10.0.1.10", 24), localHubs: ["10.0.1.10"], page: "<html>unexpected</html>")

    let result = try await finder.find(searchesLocalNetwork: true, asksInsteonConnect: true)

    #expect(result.hubs.map(\.endpoint.host) == ["10.0.1.10"])
    #expect(result.insteonConnectError != nil)
    #expect(result.localNetworkError == nil)

  }

  @Test func mergeKeepsTheEarlierWaysValues() {

    var hubs: [DiscoveredHub] = []
    let endpoint = HubEndpoint(host: "10.0.1.10")

    HubFinder.merge(
      DiscoveredHub(endpoint: endpoint, insteonID: InsteonAddress("1A.2B.3C"), foundBy: [.insteonConnect]),
      into: &hubs
    )
    HubFinder.merge(DiscoveredHub(endpoint: endpoint, foundBy: [.localNetwork]), into: &hubs)

    #expect(hubs.count == 1)
    #expect(hubs[0].insteonID == InsteonAddress("1A.2B.3C"))
    #expect(hubs[0].foundBy == [.insteonConnect, .localNetwork])

  }

}
