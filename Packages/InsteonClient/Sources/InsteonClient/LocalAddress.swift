import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Whether a host name is on the local network, where a bearer token may cross plain HTTP.
///
/// A loopback or link-local address, a private range (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16,
/// fc00::/7), an IPv4-mapped address of one of them, a documentation range, `localhost`, a `.local` name and a single-label name are
/// local. Everything else is not, so a token meant for a home never crosses the internet unencrypted.
enum LocalAddress {

  static func isLocal(host rawHost: String) -> Bool {
    var host = rawHost.lowercased()
    if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
    if let zone = host.firstIndex(of: "%") { host = String(host[..<zone]) }
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

  /// Reads the 16 bytes of the address with the platform's parser and tests the ranges on them.
  /// An IPv4-mapped address is judged by its IPv4 part.
  private static func isLocalIPv6(_ host: String) -> Bool {
    var address = in6_addr()
    guard inet_pton(AF_INET6, host, &address) == 1 else { return false }
    let b = withUnsafeBytes(of: &address) { Array($0) }
    if b[0..<15].allSatisfy({ $0 == 0 }) && b[15] == 1 { return true }
    if b[0..<10].allSatisfy({ $0 == 0 }) && b[10] == 0xFF && b[11] == 0xFF { return isLocalIPv4(Array(b[12..<16])) }
    return (b[0] == 0xFE && b[1] & 0xC0 == 0x80) || b[0] & 0xFE == 0xFC
  }

}
