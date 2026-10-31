import InsteonHubClient
import InsteonHubDiscovery
import InsteonProtocol

/// Finds Insteon Hubs: on the local network, and with Insteon Connect, and confirms a Hub by
/// asking it for its identity with its user name and password.
///
/// A Hub found either way is only a candidate. Identifying one sends it the Hub's credentials,
/// which its interface sends unencrypted, so they go only where a Hub on the local network is:
/// a candidate at a private address, and when several are identified, only one on the Hub's
/// port, stopping at the first that rejects them with HTTP 401 or 403, and only those the
/// caller agrees to send them to.
///
/// ```swift
/// let search = HubSearch()
/// var hubs: [HubCandidate] = []
///
/// for hub in try await search.searchLocalNetwork(stoppingAtFirstHub: true).hubs {
///   HubSearch.merge(hub, into: &hubs)
/// }
///
/// let results = try await search.identify(hubs, user: user, password: password) { candidate in
///   await askTheUser(about: candidate)
/// }
/// ```
public struct HubSearch: Sendable {

  private let finder: HubFinder

  private let identifier: HubIdentifier

  /// Creates a search that asks the local network and Insteon Connect, and identifies Hubs on
  /// the Hub's default port, ``HubLocation/defaultPort``.
  public init() {

    self.finder = HubFinder()
    self.identifier = HubIdentifier()

  }

  /// How many addresses a local-network search asks.
  ///
  /// - Returns: The number of addresses.
  /// - Throws: The network's error if its interfaces can't be read.
  public func searchableAddressCount() throws -> Int {

    try finder.discovery.searchableAddressCount()

  }

  /// Asks Insteon Connect for the Hubs that reported from this network's public IP address.
  ///
  /// - Returns: The Hubs, each found by ``HubSource/insteonConnect``.
  /// - Throws: The lookup's error, or `CancellationError`.
  public func insteonConnectHubs() async throws -> [HubCandidate] {

    try await finder.lookup.hubs().map { (hub: DiscoveredHub) -> HubCandidate in

      var found: DiscoveredHub = hub
      found.foundBy = [.insteonConnect]

      return HubCandidate(found)

    }

  }

  /// Searches the local network, stopping at the first Hub when asked to.
  ///
  /// - Parameters:
  ///   - stoppingAtFirstHub: Whether to stop at the first Hub rather than asking every address.
  ///   - onHubFound: Called with each Hub as it's found, so a caller can show progress.
  /// - Returns: The Hubs found, each found by ``HubSource/localNetwork``, and whether the
  ///   search stopped early.
  /// - Throws: The network's error if its interfaces can't be read, or `CancellationError`.
  public func searchLocalNetwork(
    stoppingAtFirstHub: Bool,
    onHubFound: @Sendable (HubCandidate) -> Void = { _ in }
  ) async throws -> LocalHubSearch {

    let search: HubFinder.LocalSearch = try await finder.searchLocalNetwork(stoppingAtFirstHub: stoppingAtFirstHub) { (hub: DiscoveredHub) -> Void in

      onHubFound(HubCandidate(hub))

    }

    return LocalHubSearch(
      hubs: search.hubs.map { (hub: DiscoveredHub) -> HubCandidate in HubCandidate(hub) },
      stoppedAtFirstHub: search.stoppedAtFirstHub
    )

  }

  /// Adds a Hub to a list, merged with the same Hub found another way, by host and port.
  ///
  /// - Parameters:
  ///   - hub: The Hub.
  ///   - hubs: The list.
  public static func merge(_ hub: HubCandidate, into hubs: inout [HubCandidate]) {

    var discovered: [DiscoveredHub] = hubs.map(\.discovered)

    HubFinder.merge(hub.discovered, into: &discovered)
    hubs = discovered.map { (merged: DiscoveredHub) -> HubCandidate in HubCandidate(merged) }

  }

  /// Asks one Hub the caller chose for Get IM Info with the Hub's credentials, if it's at a
  /// private address, whatever its port.
  ///
  /// - Parameters:
  ///   - hub: The Hub.
  ///   - user: The Hub's user name.
  ///   - password: The Hub's password.
  /// - Returns: What came of asking.
  /// - Throws: `CancellationError`.
  public func identify(_ hub: HubCandidate, user: String, password: String) async throws -> HubIdentification {

    let credentials = HubIdentifier.Credentials(user: user, password: password)

    return HubIdentification(try await identifier.identify(hub.discovered, credentials: credentials))

  }

  /// Asks Hubs for Get IM Info with the Hub's credentials, one at a time: only a Hub at a
  /// private address on the Hub's port that the caller agrees to send them to, and none after
  /// the first that rejects them.
  ///
  /// - Parameters:
  ///   - hubs: The Hubs.
  ///   - user: The Hub's user name.
  ///   - password: The Hub's password.
  ///   - sendsCredentials: Whether to send the credentials to a Hub, such as after asking a
  ///     person.
  ///   - onResult: Called with what came of each Hub as it's known.
  /// - Returns: Each Hub asked about and what came of it, in order.
  /// - Throws: The error `sendsCredentials` throws, or `CancellationError`.
  @discardableResult
  public func identify(
    _ hubs: [HubCandidate],
    user: String,
    password: String,
    sendsCredentials: @Sendable (HubCandidate) async throws -> Bool,
    onResult: @Sendable (HubCandidate, HubIdentification) -> Void = { _, _ in }
  ) async throws -> [(hub: HubCandidate, outcome: HubIdentification)] {

    let credentials = HubIdentifier.Credentials(user: user, password: password)

    let results = try await identifier.identify(
      hubs.map(\.discovered),
      provideCredentials: { (hub: DiscoveredHub) async throws -> HubIdentifier.Credentials? in

        try await sendsCredentials(HubCandidate(hub)) ? credentials : nil

      },
      onResult: { (hub: DiscoveredHub, outcome: HubIdentifier.Outcome) -> Void in

        onResult(HubCandidate(hub), HubIdentification(outcome))

      }
    )

    return results.map { (result: (hub: DiscoveredHub, outcome: HubIdentifier.Outcome)) -> (hub: HubCandidate, outcome: HubIdentification) in

      (HubCandidate(result.hub), HubIdentification(result.outcome))

    }

  }

}

/// A way a Hub was found.
public enum HubSource: Hashable, Sendable {

  /// The Hub answered on the local network.
  case localNetwork

  /// Insteon Connect listed the Hub for this network's public IP address.
  case insteonConnect

}

/// A Hub that ``HubSearch`` found, which is only a candidate until it's identified.
///
/// Its fields that the way it was found doesn't report are `nil` until it's identified.
public struct HubCandidate: Hashable, Sendable {

  /// The record discovery keeps.
  var discovered: DiscoveredHub

  init(_ discovered: DiscoveredHub) {

    self.discovered = discovered

  }

  /// The Hub's host name or IP address.
  public var host: String { discovered.endpoint.host }

  /// The Hub's port.
  public var port: Int { discovered.endpoint.port }

  /// The Hub's Insteon ID, if it's known.
  public var insteonID: InsteonAddress? { discovered.insteonID }

  /// The category of the Hub's modem, if it's known.
  public var category: DeviceCategory? { discovered.category }

  /// The subcategory of the Hub's modem, which names the Hub's model, if it's known.
  public var subcategory: DeviceSubcategory? { discovered.subcategory }

  /// The firmware version of the Hub's modem, if it's known.
  public var firmwareVersion: FirmwareVersion? { discovered.modemFirmwareVersion }

  /// The kind of Hub as Insteon's servers name it, such as `"HUB2"`, if it's known.
  public var unitType: String? { discovered.unitType }

  /// The ways the Hub was found.
  public var foundBy: Set<HubSource> {

    Set(discovered.foundBy.map { (source: DiscoverySource) -> HubSource in

      switch source {
      case .localNetwork: .localNetwork
      case .insteonConnect: .insteonConnect
      }

    })

  }

  /// Keeps the identity the Hub reported for Get IM Info: its Insteon ID, category,
  /// subcategory and firmware version.
  ///
  /// - Parameter info: The Hub's answer.
  public mutating func record(_ info: ModemInfo) {

    discovered.insteonID = info.address
    discovered.category = info.category
    discovered.subcategory = info.subcategory
    discovered.modemFirmwareVersion = info.firmwareVersion

  }

}

/// What a local-network search found.
public struct LocalHubSearch: Sendable {

  /// The Hubs found, in address order.
  public var hubs: [HubCandidate]

  /// Whether the search stopped at the first Hub rather than asking every address.
  public var stoppedAtFirstHub: Bool

}

/// What came of asking a Hub for Get IM Info with its credentials.
///
/// A failure carries its underlying error, which never carries the credentials.
public enum HubIdentification: Sendable {

  /// The Hub answered, confirming it's a Hub, and reported this identity.
  case identified(ModemInfo)

  /// The Hub's address isn't a private address, so no credentials were sent.
  case skippedNonPrivateAddress

  /// The Hub isn't on the Hub's port, so no credentials were sent.
  case skippedNonHubPort

  /// The caller chose not to send credentials to the Hub.
  case declined

  /// The Hub didn't answer in time.
  case didNotAnswer

  /// The Hub rejected the credentials with HTTP 401 or 403.
  case rejected(any Error)

  /// Asking the Hub failed for another reason.
  case failed(any Error)

  init(_ outcome: HubIdentifier.Outcome) {

    switch outcome {
    case let .identified(info):
      self = .identified(info)
    case .skippedNonPrivateAddress:
      self = .skippedNonPrivateAddress
    case .skippedNonHubPort:
      self = .skippedNonHubPort
    case .declined:
      self = .declined
    case .didNotAnswer:
      self = .didNotAnswer
    case let .rejected(error):
      self = .rejected(error)
    case let .failed(error):
      self = .failed(error)
    }

  }

  /// Whether the Hub rejected the credentials.
  public var isAuthenticationFailure: Bool {

    if case .rejected = self {

      return true

    }

    return false

  }

}
