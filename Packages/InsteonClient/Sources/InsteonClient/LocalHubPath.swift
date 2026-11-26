import InsteonHubDiscovery

/// A Hub found on the local network, reached directly.
///
/// It looks for a Hub each time it opens, takes the first one found and hands it to `open`, which
/// makes the calls that reach it. Searching and opening are supplied, so the path holds no Hub
/// credential and runs the same on a phone, a Mac or a test.
public struct LocalHubPath: HomePath {

  public let name = "local network"
  private let locate: @Sendable () async throws -> [DiscoveredHub]
  private let openHub: @Sendable (DiscoveredHub) async throws -> any HomeCalls

  /// Creates a path.
  ///
  /// - Parameters:
  ///   - locate: Finds Hubs on the local network, such as with `HubFinder`.
  ///   - open: Opens the calls that reach a Hub it found.
  public init(
    locate: @escaping @Sendable () async throws -> [DiscoveredHub],
    open: @escaping @Sendable (DiscoveredHub) async throws -> any HomeCalls
  ) {
    self.locate = locate
    self.openHub = open
  }

  public func open() async throws -> any HomeCalls {
    let hubs: [DiscoveredHub]
    do {
      hubs = try await locate()
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw HomePathError.notReached("the search of the local network failed")
    }
    guard let hub = hubs.first else { throw HomePathError.notReached("no Hub answered on the local network") }
    do {
      return try await openHub(hub)
    } catch let error as HomePathError {
      throw error
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw HomePathError.notReached("the Hub didn't open")
    }
  }

}
