/// A way a ``DiscoveredHub`` was found, recorded in ``DiscoveredHub/foundBy`` so a caller can
/// show how each Hub turned up and tell a Hub found two ways from one found only one way.
///
/// ``HubFinder`` tags each result with its source and unions the sources when it merges the
/// same Hub found both ways.
public enum DiscoverySource: String, Hashable, Sendable, CaseIterable {

  /// By asking every address on the local network, as ``HubDiscovery`` does.
  case localNetwork

  /// By asking Insteon Connect, as ``InsteonConnectLookup`` does.
  case insteonConnect

}
