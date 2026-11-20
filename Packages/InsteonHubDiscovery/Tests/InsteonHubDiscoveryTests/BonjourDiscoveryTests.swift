import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import InsteonHubClient
import InsteonHubDiscovery
import InsteonNetworking

/// A Bonjour browser that lists the services a test gives, in order, resolves each to the
/// address the test gives, and records what it was asked.
actor FakeBonjour: BonjourBrowsing {

  private(set) var browsedTypes: [String] = []

  private(set) var resolved: [String] = []

  private let services: [BonjourService]

  private let addresses: [String: String]

  /// - Parameters:
  ///   - services: What the browse lists.
  ///   - addresses: The IPv4 address each service name resolves to; a name that's absent
  ///     doesn't resolve.
  init(services: [BonjourService], addresses: [String: String]) {

    self.services = services
    self.addresses = addresses

  }

  func browse(type: String) -> AsyncStream<BonjourService> {

    browsedTypes.append(type)

    let services = services

    return AsyncStream { continuation in

      for service in services {

        continuation.yield(service)

      }

      continuation.finish()

    }

  }

  func resolveAddress(of service: BonjourService) -> String? {

    resolved.append(service.name)

    return addresses[service.name]

  }

}

@Suite(.timeLimit(.minutes(1)))
struct BonjourDiscoveryTests {

  static let hubPro = BonjourService(name: "Example Bridge", type: "_hap._tcp", domain: "local.", port: 8020, textRecord: ["md": "9801-222", "ci": "2"])

  static let television = BonjourService(name: "Example TV", type: "_hap._tcp", domain: "local.", port: 7000, textRecord: ["md": "TV-3000"])

  /// A Hub Pro at 10.0.0.2 and nothing else.
  static func network() -> ScriptedNetwork {

    ScriptedNetwork([
      ScriptedNetwork.Address(host: "10.0.0.2", port: 80, path: "/"): HTTPResponse(statusCode: 401),
      ScriptedNetwork.Address(host: "10.0.0.2", port: 80, path: "/settings"): HTTPResponse(statusCode: 200, body: HubProDiscoveryTests.settings),
    ])

  }

  func discovery(
    _ network: ScriptedNetwork,
    bonjour: FakeBonjour?,
    models: [String] = ["9801"]
  ) throws -> HubDiscovery {

    let subnet = try #require(IPv4Subnet(address: "10.0.0.1", prefixLength: 30))

    return HubDiscovery(
      httpClient: UnauthenticatedHTTPClient(transport: network),
      network: FixedNetwork(fixed: [subnet]),
      hubProPorts: [80],
      hubProModels: models,
      bonjour: bonjour
    )

  }

  @Test func listsTheHubProAndNotTheTelevision() async throws {

    let network = Self.network()
    let bonjour = FakeBonjour(
      services: [Self.television, Self.hubPro],
      addresses: ["Example Bridge": "10.0.0.2", "Example TV": "10.0.0.1"]
    )

    let hubs = try await discovery(network, bonjour: bonjour).discover()

    #expect(hubs.map(\.endpoint) == [HubEndpoint(host: "10.0.0.2", port: 80)])
    #expect(hubs.first?.kind == .hubPro)
    #expect(hubs.first?.foundBy == [.bonjour])
    #expect(await bonjour.browsedTypes == ["_hap._tcp"])
    #expect(await bonjour.resolved == ["Example Bridge"])

  }

  @Test func confirmsTheResolvedAddressWithTheGateAndTheSettingsOnly() async throws {

    let network = Self.network()
    let bonjour = FakeBonjour(services: [Self.hubPro], addresses: ["Example Bridge": "10.0.0.2"])

    _ = try await discovery(network, bonjour: bonjour).discover()

    // The scan leaves the address alone once Bonjour found it there.
    #expect(await network.requests(to: "10.0.0.2") == ["GET http://10.0.0.2:80/", "GET http://10.0.0.2:80/settings"])

  }

  @Test func sendsNothingToTheTelevision() async throws {

    let network = Self.network()
    let bonjour = FakeBonjour(services: [Self.television], addresses: ["Example TV": "10.0.0.1"])

    _ = try await discovery(network, bonjour: bonjour).discover()

    #expect(await bonjour.resolved.isEmpty)
    #expect(await network.requests(to: "10.0.0.1") == ["GET http://10.0.0.1:25105/buffstatus.xml", "GET http://10.0.0.1:80/"])

  }

  @Test func scansWhenBonjourFindsNothing() async throws {

    let network = Self.network()
    let bonjour = FakeBonjour(services: [], addresses: [:])

    let hubs = try await discovery(network, bonjour: bonjour).discover()

    #expect(hubs.map(\.endpoint) == [HubEndpoint(host: "10.0.0.2", port: 80)])
    #expect(hubs.first?.foundBy.isEmpty == true)
    #expect(await network.requests(to: "10.0.0.2").count == 3)

  }

  @Test func scansWhenTheServiceDoesNotResolve() async throws {

    let network = Self.network()
    let bonjour = FakeBonjour(services: [Self.hubPro], addresses: [:])

    let hubs = try await discovery(network, bonjour: bonjour).discover()

    #expect(hubs.map(\.endpoint) == [HubEndpoint(host: "10.0.0.2", port: 80)])
    #expect(hubs.first?.foundBy.isEmpty == true)

  }

  @Test func neverAsksAnAddressOutsideThePrivateRanges() async throws {

    let network = Self.network()
    let bonjour = FakeBonjour(services: [Self.hubPro], addresses: ["Example Bridge": "203.0.113.9"])

    _ = try await discovery(network, bonjour: bonjour).discover()

    #expect(await network.requests(to: "203.0.113.9").isEmpty)

  }

  @Test func matchesTheModelRecordByTheCatalogsModelAsAPrefix() async throws {

    let network = Self.network()
    let other = BonjourService(name: "Other", type: "_hap._tcp", domain: "local.", port: 1, textRecord: ["md": "9802-222"])
    let bonjour = FakeBonjour(services: [other, Self.hubPro], addresses: ["Other": "10.0.0.1", "Example Bridge": "10.0.0.2"])

    _ = try await discovery(network, bonjour: bonjour, models: ["9801"]).discover()

    #expect(await bonjour.resolved == ["Example Bridge"])

    let none = FakeBonjour(services: [Self.hubPro], addresses: ["Example Bridge": "10.0.0.2"])

    _ = try await discovery(network, bonjour: none, models: []).discover()

    #expect(await none.resolved.isEmpty)

  }

  @Test func browsesNothingWithoutABrowser() async throws {

    let network = Self.network()

    let hubs = try await discovery(network, bonjour: nil).discover()

    #expect(hubs.map(\.endpoint) == [HubEndpoint(host: "10.0.0.2", port: 80)])

  }

}
