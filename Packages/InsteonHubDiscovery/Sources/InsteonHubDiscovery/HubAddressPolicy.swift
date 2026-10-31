/// Where a Hub's user name and password may be sent: only to an IPv4 address in the private
/// ranges of RFC 1918, `10.0.0.0/8`, `172.16.0.0/12` and `192.168.0.0/16`, where a Hub on a
/// home network is.
///
/// The Hub's interface is plain HTTP, so the credentials are readable wherever they go. The
/// policy refuses everything else before any request: a host name, which a name server could
/// answer with any address; an IPv6 address; a loopback, link-local or shared address, such as
/// `127.0.0.1`, `169.254.1.1` or `100.64.0.1`; and a public address, such as one mistyped. An
/// address is read strictly, as four decimal numbers without leading zeros, so it's the address
/// a connection goes to. ``HubIdentifier`` follows it, and so does InsteonCore's
/// `ModemSession.withHub`.
///
/// ```swift
/// HubAddressPolicy.allowsCredentials(to: "192.168.1.20")   // true
/// HubAddressPolicy.allowsCredentials(to: "hub.local")      // false
/// HubAddressPolicy.allowsCredentials(to: "19.168.1.20")    // false
/// ```
public enum HubAddressPolicy {

  /// Whether a Hub's credentials may be sent to a host.
  ///
  /// - Parameter host: The host, as a person or a search gave it.
  /// - Returns: `true` only for an IPv4 address in `10.0.0.0/8`, `172.16.0.0/12` or
  ///   `192.168.0.0/16`.
  public static func allowsCredentials(to host: String) -> Bool {

    IPv4Subnet(address: host, prefixLength: 32)?.isPrivate == true

  }

}
