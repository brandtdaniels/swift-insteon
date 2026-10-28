import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonHubClient
import InsteonNetworking
import InsteonProtocol

/// Errors reported by ``InsteonConnectLookup``.
public enum InsteonConnectError: Error, Hashable, Sendable {

  /// Insteon Connect answered with a status other than `200 OK`.
  case unexpectedStatus(Int)

  /// The page neither listed a Hub nor said it found none, so its format may have changed.
  case unrecognizedPage

}

/// Looks up the Hubs on the local network with Insteon Connect, Insteon's own Hub-finding
/// page.
///
/// Each Hub reports its local address to Insteon's servers when it starts and from time to
/// time after. Insteon Connect's Get Info page lists the Hubs that reported from the same
/// public IP address as the browser asking, within the past 24 hours, which is how Insteon's
/// apps found Hubs. Use it alongside or instead of ``HubDiscovery``, which never leaves the
/// local network:
///
/// ```swift
/// let hubs = try await InsteonConnectLookup().hubs()
/// ```
///
/// The lookup sends Insteon no credentials, but Insteon sees the network's public IP address,
/// as it does for any request. The page also lists each Hub's MAC address, network settings
/// and firmware versions; only the Hub's local address and Insteon ID are kept. A Hub that
/// hasn't reported recently, or can't reach the internet, isn't listed; power-cycling it
/// makes it report again.
///
/// The page is HTML for people rather than an API, so it's read by its labels, and a change
/// to its wording can stop the lookup with ``InsteonConnectError/unrecognizedPage``.
public struct InsteonConnectLookup: Sendable {

  /// The address of Insteon Connect's Get Info page.
  public static let pageURL = URL(string: "https://connect.insteon.com/GetInfo.aspx")!

  /// How long to wait for the page by default: 10 seconds.
  public static let defaultTimeout: Duration = .seconds(10)

  /// The client the page is requested with.
  public let httpClient: any HTTPClient

  /// How long to wait for the page.
  public let timeout: Duration

  /// Creates a lookup.
  ///
  /// - Parameters:
  ///   - httpClient: The client to request the page with. Defaults to a
  ///     `URLSessionHTTPClient`. It must not add credentials, so a
  ///     `BasicAuthenticationHTTPClient` is refused.
  ///   - timeout: How long to wait for the page. Defaults to
  ///     ``InsteonConnectLookup/defaultTimeout``.
  public init(httpClient: any HTTPClient = URLSessionHTTPClient(), timeout: Duration = InsteonConnectLookup.defaultTimeout) {

    precondition(
      !(httpClient is BasicAuthenticationHTTPClient),
      "The lookup must not send the Hub's credentials to Insteon."
    )

    self.httpClient = httpClient
    self.timeout = timeout

  }

  /// The Hubs Insteon Connect lists for this network.
  ///
  /// - Returns: The Hubs in the page's order, each with its local endpoint and Insteon ID.
  ///   Empty when the page says it found no Hub.
  /// - Throws: ``InsteonConnectError/unexpectedStatus(_:)`` if the page doesn't load,
  ///   ``InsteonConnectError/unrecognizedPage`` if it can't be read, or the client's error.
  public func hubs() async throws -> [DiscoveredHub] {

    var request = URLRequest(url: Self.pageURL)
    request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    // Cookies would let Insteon link one lookup to the next.
    request.httpShouldHandleCookies = false
    request.timeoutInterval = timeout.timeInterval

    let response = try await httpClient.send(request)

    guard response.statusCode == 200 else {

      throw InsteonConnectError.unexpectedStatus(response.statusCode)

    }

    return try Self.hubs(inPage: String(decoding: response.body, as: UTF8.self))

  }

  /// Reads the Hubs from the Get Info page.
  ///
  /// The page shows one block for each Hub. The Hub's local address, usually with its port,
  /// starts the block, as a link such as `http://10.0.1.10:25105` or as text such as
  /// `10.0.1.10:25105` after "Insteon device was found on your network". A table of labels
  /// and values follows, including "Insteon ID" or "Your Insteon ID". The page reads "Sorry,
  /// cannot find an Insteon Hub on your network" when there are none.
  ///
  /// The table also lists the gateway and subnet mask, so an address given as text starts a
  /// block only when it carries a port or follows the "found" line.
  ///
  /// Only Hubs at a private address (`10.0.0.0/8`, `172.16.0.0/12` or `192.168.0.0/16`) are
  /// kept, since the address is where the Hub's password will be sent, and each address is
  /// kept once. An address without a port is at the Hub's default port.
  ///
  /// - Parameter page: The page's HTML.
  /// - Returns: The Hubs in the page's order.
  /// - Throws: ``InsteonConnectError/unrecognizedPage`` if the page neither lists a Hub nor
  ///   says it found none.
  static func hubs(inPage page: String) throws(InsteonConnectError) -> [DiscoveredHub] {

    var hubs: [DiscoveredHub] = []
    var sawLink = false
    // The index of the Hub whose block is being read, if it's kept.
    var current: Int?
    let lines = textLines(of: page)

    // Whether the previous line said a Hub was found.
    var follows = false

    for (index, line) in lines.enumerated() {

      defer { follows = saysFound(line) }

      if let link = link(in: line) ?? address(in: line, follows: follows) {

        sawLink = true
        current = nil

        // The host is rebuilt from the parsed address, so it's the address that was checked.
        let endpoint = HubEndpoint(host: IPv4Subnet.dottedDecimal(link.address), port: link.port)

        if IPv4Subnet(address: link.address, mask: .max).isPrivate, !hubs.contains(where: { $0.endpoint == endpoint }) {

          current = hubs.count
          hubs.append(DiscoveredHub(endpoint: endpoint))

        }

      } else if ["insteon id", "your insteon id"].contains(label(line)), let current, index + 1 < lines.count {

        hubs[current].insteonID = InsteonAddress(lines[index + 1])

      }

    }

    if sawLink {

      return hubs

    }

    guard page.range(of: "cannot find an Insteon Hub", options: .caseInsensitive) != nil else {

      throw .unrecognizedPage

    }

    return []

  }

  /// The page's text, one line for each element's text, trimmed, without empty lines.
  private static func textLines(of page: String) -> [String] {

    var text = ""
    var isInTag = false

    for character in page {

      switch character {
      case "<":
        isInTag = true
        text.append("\n")
      case ">":
        isInTag = false
      default:
        if !isInTag {

          text.append(character)

        }
      }

    }

    return text
      .replacingOccurrences(of: "&nbsp;", with: " ")
      .replacingOccurrences(of: "&amp;", with: "&")
      .split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }

  }

  /// The address and port of a line that's a link such as `http://10.0.1.10:25105`.
  private static func link(in line: String) -> (address: UInt32, port: Int)? {

    guard line.lowercased().hasPrefix("http://") else {

      return nil

    }

    let authority = line.dropFirst("http://".count).prefix { $0 != "/" }
    let parts = authority.split(separator: ":", omittingEmptySubsequences: false)

    guard
      (1...2).contains(parts.count),
      let host = IPv4Subnet(address: String(parts[0]), prefixLength: 32),
      let port = parts.count == 2 ? Int(parts[1]) : HubEndpoint.defaultPort,
      (1...65_535).contains(port)
    else {

      return nil

    }

    return (host.address, port)

  }

  /// The address and port of a line that's an address as text, such as `10.0.1.10:25105`.
  ///
  /// - Parameters:
  ///   - line: The line.
  ///   - follows: Whether the line follows the page's "found on your network" line, which
  ///     lets an address without a port through.
  private static func address(in line: String, follows: Bool) -> (address: UInt32, port: Int)? {

    guard
      line.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "." || $0 == ":") }),
      follows || line.contains(":")
    else {

      return nil

    }

    return link(in: "http://" + line)

  }

  /// Whether a line says a Hub was found, as "Insteon device was found on your network" does,
  /// and not that none was.
  private static func saysFound(_ line: String) -> Bool {

    let line = line.lowercased()

    return line.contains("was found on your network") && !line.contains("not found")

  }

  /// A line as a label: lowercased, without a trailing colon.
  private static func label(_ line: String) -> String {

    var label = line.lowercased()

    if label.hasSuffix(":") {

      label.removeLast()

    }

    return label.trimmingCharacters(in: .whitespaces)

  }

}
