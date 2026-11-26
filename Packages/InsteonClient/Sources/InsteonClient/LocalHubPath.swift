import InsteonHubDiscovery

/// A Hub found on the local network, reached directly.
///
/// It looks for a Hub each time it opens, hands each one found, in order, to `open` until one opens, which
/// makes the calls that reach it. Searching and opening are supplied, so the path holds no Hub
/// credential and runs the same on a phone, a Mac or a test.
public struct LocalHubPath: ConnectionPath {

  public let name = "local network"
  private let locate: @Sendable () async throws -> [DiscoveredHub]
  private let openHub: @Sendable (DiscoveredHub) async throws -> any ConnectionCalls

  /// Creates a path.
  ///
  /// - Parameters:
  ///   - locate: Finds Hubs on the local network, such as with `HubFinder`.
  ///   - open: Opens the calls that reach a Hub it found.
  public init(
    locate: @escaping @Sendable () async throws -> [DiscoveredHub],
    open: @escaping @Sendable (DiscoveredHub) async throws -> any ConnectionCalls
  ) {
    self.locate = locate
    self.openHub = open
  }

  public func open() async throws -> any ConnectionCalls {
    let hubs: [DiscoveredHub]
    do {
      hubs = try await locate()
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw ConnectionPathError.notReached("the search of the local network failed")
    }
    guard !hubs.isEmpty else { throw ConnectionPathError.notReached("no Hub answered on the local network") }
    // What the path reports when no Hub opens: the most telling failure, not the first.
    var failure: ConnectionPathError?
    func note(_ error: ConnectionPathError) {
      func rank(_ e: ConnectionPathError?) -> Int { switch e { case .unauthorized?: 3; case .forbidden?: 2; case .badResponse?: 1; default: 0 } }
      if rank(error) > rank(failure) { failure = error }
    }
    for hub in hubs {
      do {
        return try await openHub(hub)
      } catch is CancellationError {
        throw CancellationError()
      } catch let error as ConnectionPathError {
        note(error)
      } catch {
        // This Hub didn't open; the next may.
      }
    }
    throw failure ?? ConnectionPathError.notReached("no Hub on the local network opened")
  }

}
