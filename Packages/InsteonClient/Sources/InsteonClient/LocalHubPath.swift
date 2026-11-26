import InsteonHubDiscovery

/// A Hub found on the local network, reached directly.
///
/// It looks for a Hub each time it opens, hands each one found, in order, to `open` until one opens, which
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
    guard !hubs.isEmpty else { throw HomePathError.notReached("no Hub answered on the local network") }
    var refused = false
    for hub in hubs {
      do {
        return try await openHub(hub)
      } catch is CancellationError {
        throw CancellationError()
      } catch HomePathError.unauthorized {
        refused = true
      } catch {
        // This Hub didn't open; the next may.
      }
    }
    throw refused ? HomePathError.unauthorized : HomePathError.notReached("no Hub on the local network opened")
  }

}
