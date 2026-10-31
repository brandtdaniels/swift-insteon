import Foundation

/// The proxy settings in a process's environment, which swift-corelibs-foundation on Linux
/// leaves to libcurl.
///
/// On Linux, `URLSession` ignores `URLSessionConfiguration.connectionProxyDictionary`, and
/// libcurl sends a request through the proxy its environment names unless `no_proxy` names
/// the request's host. A client for the local network asks this whether a request would go
/// through a proxy, and refuses to send it if it would.
///
/// The reading errs toward finding a proxy, and is never more willing than libcurl to go
/// direct:
///
/// - A variable that's set to anything but the empty string names a proxy, and `HTTP_PROXY`
///   counts as well as `http_proxy`, though libcurl reads only the lowercase name for plain
///   HTTP.
/// - `no_proxy` is read when it's set and not empty, and `NO_PROXY` otherwise.
/// - `*` turns every proxy off only when it's the whole of `no_proxy`, exactly as written.
/// - Otherwise an entry counts only when it's the host itself or, for a host name, a domain the
///   name is in, with or without a leading dot. An entry for an address must be the address as
///   written, without a leading dot, and an address range such as `192.168.0.0/16` doesn't
///   count, since libcurl before 7.86 doesn't read ranges.
struct ProxyEnvironment: Hashable, Sendable {

  /// The proxy for plain HTTP, from `http_proxy` or `HTTP_PROXY`, if one is set.
  let httpProxy: String?

  /// The proxy for HTTPS, from `https_proxy` or `HTTPS_PROXY`, if one is set.
  let httpsProxy: String?

  /// The proxy for every scheme, from `all_proxy` or `ALL_PROXY`, if one is set.
  let allProxy: String?

  /// Whether `no_proxy` is exactly `*`, which turns every proxy off.
  let excludesEveryHost: Bool

  /// The entries of `no_proxy` or `NO_PROXY`, lowercased, without empty ones.
  let exclusions: [String]

  /// Reads the proxy settings from an environment.
  ///
  /// - Parameter environment: The environment, such as the process's.
  init(_ environment: [String: String]) {

    // The first of the names that's set to anything but the empty string.
    func value(_ names: String...) -> String? {

      names.lazy.compactMap { (name: String) -> String? in environment[name] }.first { (value: String) -> Bool in !value.isEmpty }

    }

    httpProxy = value("http_proxy", "HTTP_PROXY")
    httpsProxy = value("https_proxy", "HTTPS_PROXY")
    allProxy = value("all_proxy", "ALL_PROXY")

    let exclusionText: String = value("no_proxy", "NO_PROXY") ?? ""

    excludesEveryHost = exclusionText == "*"

    // libcurl separates entries with commas, and trims spaces around them.
    exclusions = exclusionText
      .split(whereSeparator: { (character: Character) -> Bool in character == "," || character.isWhitespace })
      .map { (entry: Substring) -> String in entry.lowercased() }
      .filter { (entry: String) -> Bool in !entry.isEmpty }

  }

  /// Whether a request to an address would go through a proxy.
  ///
  /// - Parameter url: The request's address.
  /// - Returns: `true` if a proxy is set for the address's scheme, or for every scheme, and
  ///   `no_proxy` doesn't name its host. `false` for an address without a host.
  func proxies(_ url: URL?) -> Bool {

    guard let url, let host = url.host?.lowercased(), !host.isEmpty else {

      return false

    }

    let proxy: String?

    switch url.scheme?.lowercased() {
    case "http":
      proxy = httpProxy ?? allProxy
    case "https":
      proxy = httpsProxy ?? allProxy
    default:
      proxy = allProxy
    }

    guard proxy != nil else {

      return false

    }

    return !isExcluded(host)

  }

  /// Whether `no_proxy` names a host: as `*` alone, as the host itself, or, for a host name,
  /// as a domain it's in, with or without a leading dot.
  private func isExcluded(_ host: String) -> Bool {

    if excludesEveryHost {

      return true

    }

    // An IPv6 address keeps its brackets in some URL readings and not in others.
    let bareHost: String = host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
    let isAddress: Bool = bareHost.contains(":")
      || bareHost.allSatisfy { (character: Character) -> Bool in character == "." || character.isASCII && character.isNumber }

    return exclusions.contains { (entry: String) -> Bool in

      // An address counts only as written; a dot in front of it, or a wildcard among other
      // entries, isn't read the same way by every libcurl.
      if isAddress {

        return entry == bareHost

      }

      let name: String = entry.hasPrefix(".") ? String(entry.dropFirst()) : entry

      return !name.isEmpty && name != "*" && (name == bareHost || bareHost.hasSuffix("." + name))

    }

  }

}
