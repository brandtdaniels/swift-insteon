import InsteonHubClient
import InsteonProtocol

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

  /// The Hub's INSTEON ID, printed on its label, when the way it was found reports one, so a
  /// user with several Hubs can tell them apart. ``HubDiscovery`` doesn't;
  /// ``InsteonConnectLookup`` does.
  public var insteonID: InsteonAddress?

  /// Creates a discovered Hub.
  ///
  /// - Parameters:
  ///   - endpoint: Where the Hub answers.
  ///   - insteonID: The Hub's INSTEON ID, if known. Defaults to `nil`.
  public init(endpoint: HubEndpoint, insteonID: InsteonAddress? = nil) {

    self.endpoint = endpoint
    self.insteonID = insteonID

  }

}
