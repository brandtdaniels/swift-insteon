import Foundation

/// Whether a host name is on the local network, where a bearer token may cross plain HTTP.
///
/// A loopback or link-local address, a private range (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16,
/// fc00::/7), a documentation range, `localhost`, a `.local` name and a single-label name are
/// local. Everything else is not, so a token meant for a home never crosses the internet unencrypted.
enum LocalAddress {

  static func isLocal(host rawHost: String) -> Bool {
    var host = rawHost.lowercased()
    if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
    if host.hasSuffix(".") { host.removeLast() }
    if host.isEmpty { return false }
    if host.contains(":") { return isLocalIPv6(host) }
    let parts = host.split(separator: ".", omittingEmptySubsequences: false)
    if parts.count == 4, let octets = Optional(parts.compactMap { UInt8($0) }), octets.count == 4 {
      return isLocalIPv4(octets)
    }
    return host == "localhost" || host.hasSuffix(".local") || !host.contains(".")
  }

  private static func isLocalIPv4(_ o: [UInt8]) -> Bool {
    switch (o[0], o[1], o[2]) {
    case (127, _, _), (10, _, _), (192, 168, _), (169, 254, _): true
    case (172, 16...31, _): true
    case (192, 0, 2), (198, 51, 100), (203, 0, 113): true
    default: false
    }
  }

  private static func isLocalIPv6(_ host: String) -> Bool {
    if host == "::1" { return true }
    let first = host.split(separator: ":", omittingEmptySubsequences: true).first.map(String.init) ?? ""
    guard let group = UInt16(first, radix: 16) else { return false }
    return group & 0xFFC0 == 0xFE80 || group & 0xFE00 == 0xFC00
  }

}
