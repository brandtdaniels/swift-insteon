import Foundation

/// The proxy settings in a process's environment, which swift-corelibs-foundation on Linux
/// leaves to libcurl.
///
/// On Linux, `URLSession` ignores `URLSessionConfiguration.connectionProxyDictionary`, and
/// libcurl sends a request through the proxy its environment names unless `no_proxy` names
/// the request's host. A client for the local network asks this whether a request would go
/// through a proxy, and refuses to send it if it would.
///
/// The reading errs toward finding a proxy. `HTTP_PROXY` counts as well as `http_proxy`,
/// though libcurl reads only the lowercase name for plain HTTP. In `no_proxy`, only `*`, the
/// host itself and, for a host name, a domain it's in count; an address range such as
/// `192.168.0.0/16` doesn't, since libcurl before 7.86 doesn't read ranges.
struct ProxyEnvironment: Hashable, Sendable {

  /// The proxy for plain HTTP, from `http_proxy` or `HTTP_PROXY`, if one is set.
  let httpProxy: String?

  /// The proxy for HTTPS, from `https_proxy` or `HTTPS_PROXY`, if one is set.
  let httpsProxy: String?

  /// The proxy for every scheme, from `all_proxy` or `ALL_PROXY`, if one is set.
  let allProxy: String?

  /// The entries of `no_proxy` or `NO_PROXY`, lowercased and trimmed, without empty ones.
  let exclusions: [String]

  /// Reads the proxy settings from an environment.
  ///
  /// - Parameter environment: The environment, such as the process's.
  init(_ environment: [String: String]) {

    func value(_ names: String...) -> String? {

      names.lazy.compactMap { environment[$0] }.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

    }

    httpProxy = value("http_proxy", "HTTP_PROXY")
    httpsProxy = value("https_proxy", "HTTPS_PROXY")
    allProxy = value("all_proxy", "ALL_PROXY")

    // libcurl separates entries with commas, and trims spaces around them.
    let exclusionText: String = value("no_proxy", "NO_PROXY") ?? ""

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

  /// Whether `no_proxy` names a host: as `*`, as the host itself, or, for a host name, as a
  /// domain it's in, with or without a leading dot.
  private func isExcluded(_ host: String) -> Bool {

    // An IPv6 address keeps its brackets in some URL readings and not in others.
    let bareHost: String = host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
    let isAddress: Bool = bareHost.contains(":") || bareHost.allSatisfy { (character: Character) -> Bool in character == "." || character.isASCII && character.isNumber }

    return exclusions.contains { (entry: String) -> Bool in

      if entry == "*" {

        return true

      }

      let name: String = entry.hasPrefix(".") ? String(entry.dropFirst()) : entry

      if name == bareHost {

        return true

      }

      // A domain covers the names in it, but not an address.
      return !isAddress && !name.isEmpty && bareHost.hasSuffix("." + name)

    }

  }

}
