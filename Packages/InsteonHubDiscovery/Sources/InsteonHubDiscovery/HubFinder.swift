/// Finds Insteon Hubs by running ``HubDiscovery`` on the local network and
/// ``InsteonConnectLookup`` through Insteon's servers, stopping the local search at the first
/// Hub unless asked for all, and merging the same Hub found both ways into one record that notes
/// each way in ``DiscoveredHub/foundBy``.
///
/// ```swift
/// let result = try await HubFinder().find(asksInsteonConnect: true) { hub in
///   print("Found a Hub at", hub.endpoint.host)
/// }
///
/// for hub in result.hubs {
///   print(hub.endpoint.host, hub.foundBy)
/// }
/// ```
///
/// ``HubFinder/find(searchesLocalNetwork:asksInsteonConnect:findsAllHubs:onLocalHubFound:)``
/// runs both ways and returns the merged Hubs, reporting a way that failed without failing the
/// whole search. A caller that wants to show its own progress can instead run
/// ``HubFinder/searchLocalNetwork(stoppingAtFirstHub:onHubFound:)`` and
/// ``InsteonConnectLookup/hubs()`` itself and merge the results with ``HubFinder/merge(_:into:)``.
///
/// Finding a Hub reports where it is, not how to sign in: the user name and password are printed
/// on the Hub. ``HubIdentifier`` asks a found Hub to confirm itself with those credentials.
public struct HubFinder: Sendable {

  /// The local-network discovery this finder runs.
  public let discovery: HubDiscovery

  /// The Insteon Connect lookup this finder runs.
  public let lookup: InsteonConnectLookup

  /// Creates a finder.
  ///
  /// - Parameters:
  ///   - discovery: The local-network discovery to run. Defaults to a ``HubDiscovery``.
  ///   - lookup: The Insteon Connect lookup to run. Defaults to an ``InsteonConnectLookup``.
  public init(discovery: HubDiscovery = HubDiscovery(), lookup: InsteonConnectLookup = InsteonConnectLookup()) {

    self.discovery = discovery
    self.lookup = lookup

  }

  /// What a local-network search found.
  public struct LocalSearch: Sendable {

    /// The Hubs found, in address order, each tagged ``DiscoverySource/localNetwork``.
    public var hubs: [DiscoveredHub]

    /// Whether the search stopped at the first Hub rather than asking every address.
    public var stoppedAtFirstHub: Bool

    /// Creates a local search result.
    ///
    /// - Parameters:
    ///   - hubs: The Hubs found.
    ///   - stoppedAtFirstHub: Whether the search stopped at the first Hub.
    public init(hubs: [DiscoveredHub], stoppedAtFirstHub: Bool) {

      self.hubs = hubs
      self.stoppedAtFirstHub = stoppedAtFirstHub

    }

  }

  /// What a combined search found, with the error of any way that failed.
  ///
  /// This carries each way's underlying error, which an arbitrary HTTP client may make anything,
  /// so it isn't `Sendable`; handle it where it's returned rather than across an actor.
  public struct Result {

    /// The Hubs found, merged across the ways that found them.
    public var hubs: [DiscoveredHub]

    /// The error the local-network search threw, if it failed, or `nil`.
    public var localNetworkError: (any Error)?

    /// The error the Insteon Connect lookup threw, if it failed, or `nil`.
    public var insteonConnectError: (any Error)?

    /// Whether the local-network search stopped at the first Hub rather than asking every
    /// address. `false` when the local network wasn't searched.
    public var stoppedAtFirstHub: Bool

    /// Creates a combined result.
    ///
    /// - Parameters:
    ///   - hubs: The Hubs found.
    ///   - localNetworkError: The local-network search's error, or `nil`.
    ///   - insteonConnectError: The Insteon Connect lookup's error, or `nil`.
    ///   - stoppedAtFirstHub: Whether the local-network search stopped at the first Hub.
    public init(
      hubs: [DiscoveredHub],
      localNetworkError: (any Error)? = nil,
      insteonConnectError: (any Error)? = nil,
      stoppedAtFirstHub: Bool = false
    ) {

      self.hubs = hubs
      self.localNetworkError = localNetworkError
      self.insteonConnectError = insteonConnectError
      self.stoppedAtFirstHub = stoppedAtFirstHub

    }

  }

  /// Searches the local network, stopping at the first Hub when asked to.
  ///
  /// The Hubs are tagged ``DiscoverySource/localNetwork``.
  ///
  /// - Parameters:
  ///   - stoppingAtFirstHub: Whether to stop at the first Hub rather than asking every address.
  ///   - onHubFound: Called with each Hub as it's found, in the order the Hubs answer, so a
  ///     caller can show progress.
  /// - Returns: The Hubs found and whether the search stopped early.
  /// - Throws: The network's error if its subnets can't be read, or `CancellationError` if the
  ///   task is canceled.
  public func searchLocalNetwork(
    stoppingAtFirstHub: Bool,
    onHubFound: @Sendable (DiscoveredHub) -> Void = { _ in }
  ) async throws -> LocalSearch {

    let (found, continuation) = AsyncStream<DiscoveredHub>.makeStream()

    let search = Task {

      defer { continuation.finish() }

      return try await discovery.discover { hub in

        continuation.yield(Self.tagged(hub))

      }

    }

    return try await withTaskCancellationHandler {

      var hubs: [DiscoveredHub] = []

      for await hub in found {

        onHubFound(hub)
        hubs.append(hub)

        if stoppingAtFirstHub {

          search.cancel()

          return LocalSearch(hubs: hubs, stoppedAtFirstHub: true)

        }

      }

      // Every address was asked; the search's own list is in address order.
      let all = try await search.value.map { Self.tagged($0) }

      return LocalSearch(hubs: all, stoppedAtFirstHub: false)

    } onCancel: {

      search.cancel()

    }

  }

  /// Runs the local-network search and the Insteon Connect lookup, as asked, and merges what
  /// they find.
  ///
  /// Insteon Connect is asked first, then the local network, so a Hub found both ways keeps the
  /// Insteon ID and model that only Insteon Connect reports. A way that fails doesn't fail the
  /// search: its error is returned in ``HubFinder/Result`` so the caller can decide. Only a
  /// `CancellationError` from the local search is thrown.
  ///
  /// - Parameters:
  ///   - searchesLocalNetwork: Whether to search the local network. Defaults to `true`.
  ///   - asksInsteonConnect: Whether to ask Insteon Connect, which sees the network's public IP
  ///     address. Defaults to `false`.
  ///   - findsAllHubs: Whether the local search asks every address rather than stopping at the
  ///     first Hub. Defaults to `false`.
  ///   - onLocalHubFound: Called with each Hub the local search finds, as it's found.
  /// - Returns: The merged Hubs and the error of any way that failed.
  /// - Throws: `CancellationError` if the task is canceled during the local search.
  public func find(
    searchesLocalNetwork: Bool = true,
    asksInsteonConnect: Bool = false,
    findsAllHubs: Bool = false,
    onLocalHubFound: @Sendable (DiscoveredHub) -> Void = { _ in }
  ) async throws -> Result {

    var hubs: [DiscoveredHub] = []
    var localNetworkError: (any Error)?
    var insteonConnectError: (any Error)?
    var stoppedAtFirstHub = false

    if asksInsteonConnect {

      do {

        for hub in try await lookup.hubs() {

          Self.merge(Self.tagged(hub, foundBy: .insteonConnect), into: &hubs)

        }

      } catch {

        insteonConnectError = error

      }

    }

    if searchesLocalNetwork {

      do {

        let search = try await searchLocalNetwork(stoppingAtFirstHub: !findsAllHubs, onHubFound: onLocalHubFound)
        stoppedAtFirstHub = search.stoppedAtFirstHub

        for hub in search.hubs {

          Self.merge(hub, into: &hubs)

        }

      } catch let error as CancellationError {

        throw error

      } catch {

        localNetworkError = error

      }

    }

    return Result(
      hubs: hubs,
      localNetworkError: localNetworkError,
      insteonConnectError: insteonConnectError,
      stoppedAtFirstHub: stoppedAtFirstHub
    )

  }

  /// Merges a Hub into a list, combining it with the same Hub already in the list, by endpoint,
  /// or adding it to the end.
  ///
  /// The Hub already in the list keeps its known fields, so merge the Hubs found later into a
  /// list of the Hubs found earlier to prefer the earlier way's values.
  ///
  /// - Parameters:
  ///   - hub: The Hub to add or merge.
  ///   - hubs: The list to merge it into.
  public static func merge(_ hub: DiscoveredHub, into hubs: inout [DiscoveredHub]) {

    if let index = hubs.firstIndex(where: { $0.endpoint == hub.endpoint }) {

      hubs[index].merge(with: hub)

    } else {

      hubs.append(hub)

    }

  }

  /// A copy of a Hub tagged with the way it was found.
  private static func tagged(_ hub: DiscoveredHub, foundBy source: DiscoverySource = .localNetwork) -> DiscoveredHub {

    var hub = hub
    hub.foundBy.insert(source)

    return hub

  }

}
