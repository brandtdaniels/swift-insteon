import InsteonHubClient

/// An INSTEON Hub that ``HubDiscovery`` found on the local network.
///
/// Connect to it with the user name and password printed on the Hub:
///
/// ```swift
/// let connection = HubConnection(hub: Hub(endpoint: hub.endpoint, user: username, password: password))
/// ```
public struct DiscoveredHub: Hashable, Sendable {

  /// Where the Hub answers on the local network.
  public var endpoint: HubEndpoint

  /// Creates a discovered Hub.
  ///
  /// - Parameter endpoint: Where the Hub answers.
  public init(endpoint: HubEndpoint) {

    self.endpoint = endpoint

  }

}
