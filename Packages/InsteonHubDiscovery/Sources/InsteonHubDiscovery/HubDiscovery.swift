import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonHubClient
import InsteonNetworking

/// Finds Insteon Hubs on the local network, without Insteon's servers.
///
/// A Hub doesn't announce itself, so discovery asks every address on the device's private
/// subnets. Each address is sent one HTTP request for the Hub's buffer page, `/buffstatus.xml`
/// on port `25105`, without credentials. A Hub answers that with `401 Unauthorized` and a
/// `Basic` challenge, since the page needs the user name and password printed on it, so an
/// address that answers that way is reported as a Hub. Nothing is sent to a Hub beyond that
/// request.
///
/// Any device can answer that way, so a result is a candidate, not a verified Hub. Show the
/// user the address and let them confirm it before sending the Hub's password there, since
/// the Hub's interface sends it unencrypted.
///
/// ```swift
/// let hubs = try await HubDiscovery().discover { hub in
///   print("Found a Hub at", hub.endpoint.host)
/// }
/// ```
///
/// Asking every address takes a moment: the probes run a few dozen at a time, and an address
/// that doesn't answer costs ``HubDiscovery/probeTimeout``. Only the private address ranges
/// home networks use are searched, never a cellular, public or other network, and only
/// subnets of at most 1,024 addresses, so discovery never sweeps a large network.
///
/// On iOS, iPadOS, tvOS and visionOS, an app must say why it uses the local network, with
/// `NSLocalNetworkUsageDescription` in its `Info.plist`, and the user is asked to allow it the
/// first time discovery runs.
public struct HubDiscovery: Sendable {

  /// The shortest subnet prefix that's searched: `22`, a subnet of 1,024 addresses.
  public static let shortestPrefixLength = 22

  /// How long each address has to answer by default: 1 second.
  public static let defaultProbeTimeout: Duration = .seconds(1)

  /// How many addresses are asked at once by default: 32.
  public static let defaultConcurrentProbes = 32

  /// The client the probes are sent with.
  public let httpClient: any HTTPClient

  /// The network whose subnets are searched.
  public let network: any LocalNetwork

  /// The port Hubs are looked for on.
  public let port: Int

  /// How long each address has to answer.
  public let probeTimeout: Duration

  /// How many addresses are asked at once.
  public let concurrentProbes: Int

  /// Creates a discovery.
  ///
  /// - Parameters:
  ///   - httpClient: The client to send the probes with. Defaults to a
  ///     `URLSessionHTTPClient`. It must not add credentials, which would go to every address
  ///     probed, so a `BasicAuthenticationHTTPClient` is refused.
  ///   - network: The network whose subnets to search. Defaults to the device's network
  ///     interfaces.
  ///   - port: The port to look for Hubs on. Defaults to `HubEndpoint.defaultPort`.
  ///   - probeTimeout: How long each address has to answer. Defaults to
  ///     ``HubDiscovery/defaultProbeTimeout``.
  ///   - concurrentProbes: How many addresses to ask at once. Defaults to
  ///     ``HubDiscovery/defaultConcurrentProbes``; a value below 1 is raised to 1.
  public init(
    httpClient: any HTTPClient = URLSessionHTTPClient(),
    network: any LocalNetwork = InterfaceNetwork(),
    port: Int = HubEndpoint.defaultPort,
    probeTimeout: Duration = HubDiscovery.defaultProbeTimeout,
    concurrentProbes: Int = HubDiscovery.defaultConcurrentProbes
  ) {

    precondition(
      !(httpClient is BasicAuthenticationHTTPClient),
      "Discovery probes every address, so its client must not send the Hub's credentials."
    )

    self.httpClient = httpClient
    self.network = network
    self.port = port
    self.probeTimeout = probeTimeout
    self.concurrentProbes = max(1, concurrentProbes)

  }

  /// Asks every address on the local private subnets whether it's a Hub.
  ///
  /// - Parameter found: Called with each Hub as it's found, in the order the Hubs answer.
  /// - Returns: Every Hub found, in address order.
  /// - Throws: The network's error if its subnets can't be read, `HubError.invalidEndpoint`
  ///   if ``HubDiscovery/port`` is outside 0 to 65,535, or `CancellationError` if the task is
  ///   canceled.
  @discardableResult
  public func discover(_ found: @Sendable (DiscoveredHub) async -> Void = { _ in }) async throws -> [DiscoveredHub] {

    try Task.checkCancellation()

    // Two subnets can overlap, so each address is asked once, and in address order.
    let addresses = try network.subnets()
      .filter { $0.isPrivate && $0.prefixLength >= Self.shortestPrefixLength }
      .reduce(into: Set<UInt32>()) { $0.formUnion($1.hostAddresses) }
      .sorted()
    let candidates = try addresses.map { address in

      let endpoint = HubEndpoint(host: IPv4Subnet.dottedDecimal(address), port: port)

      return (endpoint, try HubRequest.readBuffer.urlRequest(for: endpoint))

    }

    var hubs: [(index: Int, hub: DiscoveredHub)] = []

    try await withThrowingTaskGroup(of: (Int, DiscoveredHub?).self) { group in

      var next = candidates.startIndex

      // Starts a probe of the next candidate, if there's one left.
      func probeNext() {

        guard next < candidates.endIndex else {

          return

        }

        let index = next
        let (endpoint, request) = candidates[index]
        next += 1

        group.addTask {

          (index, try await probe(endpoint, with: request))

        }

      }

      for _ in 0..<min(concurrentProbes, candidates.count) {

        probeNext()

      }

      while let (index, hub) = try await group.next() {

        try Task.checkCancellation()

        if let hub {

          hubs.append((index, hub))
          await found(hub)

        }

        probeNext()

      }

    }

    try Task.checkCancellation()

    return hubs.sorted { $0.index < $1.index }.map(\.hub)

  }

  /// Asks one address whether it's a Hub.
  ///
  /// - Returns: The Hub, or `nil` if the address doesn't answer as one.
  /// - Throws: `CancellationError` if the task is canceled.
  private func probe(_ endpoint: HubEndpoint, with request: URLRequest) async throws -> DiscoveredHub? {

    var request = request
    request.timeoutInterval = probeTimeout.timeInterval

    let response: HTTPResponse

    do {

      response = try await httpClient.send(request)

    } catch {

      // An address with nothing listening, or that doesn't answer in time, isn't a Hub.
      try Task.checkCancellation()

      return nil

    }

    guard
      response.statusCode == 401,
      response.value(forHeader: "WWW-Authenticate")?.lowercased().hasPrefix("basic") == true
    else {

      return nil

    }

    return DiscoveredHub(endpoint: endpoint)

  }

}

extension Duration {

  /// The duration in seconds, as `URLRequest` takes it.
  var timeInterval: TimeInterval {

    let (seconds, attoseconds) = components

    return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18

  }

}
