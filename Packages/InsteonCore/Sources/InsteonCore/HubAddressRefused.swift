import InsteonHubDiscovery

/// A Hub's address that isn't a private IPv4 address, so ``ModemSession/withHub(host:port:user:password:_:)``
/// sends it neither the Hub's user name and password nor any request.
///
/// The Hub's interface is plain HTTP, so its credentials are readable wherever they go. They go
/// only to an IPv4 address in `10.0.0.0/8`, `172.16.0.0/12` or `192.168.0.0/16`, where a Hub on
/// a home network is. A host name, an IPv6 address, a loopback or link-local address and a
/// public address, such as one mistyped, are refused. A Hub reached through a VPN keeps its
/// private address on the home network, so give that address.
public struct HubAddressRefused: Error, Hashable, Sendable {

  /// The host that was refused, as it was given.
  public let host: String

  /// Creates the error.
  ///
  /// - Parameter host: The host that was refused.
  public init(host: String) {

    self.host = host

  }

}

extension HubAddressRefused: CustomStringConvertible {

  /// What was refused and what to give instead, on one line.
  public var description: String {

    "The Hub's address, \(Self.printable(host)), isn't an IPv4 address in 10.0.0.0/8, 172.16.0.0/12 or 192.168.0.0/16, "
      + "so the Hub's user name and password aren't sent to it. Give the Hub's private IPv4 address, such as 192.168.1.20."

  }

  /// The host with any control character replaced, and cut short, so printing it can't change
  /// a terminal.
  private static func printable(_ host: String) -> String {

    let cleaned: String = String(host.unicodeScalars.map { (scalar: Unicode.Scalar) -> Character in

      scalar.properties.generalCategory == .control ? "?" : Character(scalar)

    })

    return cleaned.count > 64 ? String(cleaned.prefix(64)) + "..." : cleaned

  }

}

extension HubLocation {

  /// Whether the Hub's user name and password may be sent to this location's host: only when
  /// it's an IPv4 address in `10.0.0.0/8`, `172.16.0.0/12` or `192.168.0.0/16`.
  ///
  /// ``ModemSession/withHub(host:port:user:password:_:)`` refuses any other host with
  /// ``HubAddressRefused`` before sending anything, so a front end can check a host as it's
  /// entered.
  public var acceptsCredentials: Bool {

    HubAddressPolicy.allowsCredentials(to: host)

  }

}
