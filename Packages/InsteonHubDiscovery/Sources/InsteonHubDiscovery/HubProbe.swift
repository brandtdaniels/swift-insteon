import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonHubClient
import InsteonHubPro
import InsteonNetworking

/// Asks one host whether it is a Hub of a kind, sending only reads that carry no credentials.
///
/// ``HubDiscovery`` runs its probes in order on each address and reports the first Hub one of
/// them recognizes.
public protocol HubProbe: Sendable {

  /// Asks a host whether it's the kind of Hub this probe looks for.
  ///
  /// - Parameter host: The host's IPv4 address.
  /// - Returns: The Hub, or `nil` if the host doesn't answer as one.
  /// - Throws: `HTTPClientError.proxyConfigured` or `HTTPClientError.credentialsRefused` if the
  ///   client refuses to send the probe, or `CancellationError` if the task is canceled.
  func probe(host: String) async throws -> DiscoveredHub?

}

/// Asks a host for the Hub interface's buffer page, on the Hub's port, without credentials.
///
/// A Hub answers with `401 Unauthorized` and a `Basic` challenge, since the page needs the user
/// name and password printed on the Hub.
struct HubInterfaceProbe: HubProbe {

  let httpClient: UnauthenticatedHTTPClient

  let port: Int

  let timeout: Duration

  func probe(host: String) async throws -> DiscoveredHub? {

    let endpoint = HubEndpoint(host: host, port: port)
    let request = try HubRequest.readBuffer.urlRequest(for: endpoint)

    guard
      let response = try await HubProbeRequest.send(request, with: httpClient, timeout: timeout),
      response.statusCode == 401,
      response.value(forHeader: "WWW-Authenticate")?.lowercased().hasPrefix("basic") == true
    else {

      return nil

    }

    return DiscoveredHub(endpoint: endpoint)

  }

}

/// Asks a host whether it's a Hub Pro.
///
/// The Hub Pro's HTTP interface answers `GET /` with `401 Unauthorized` and no
/// `WWW-Authenticate` header, and `GET /settings` with the JSON that ``HubProSettings`` reads. Only a host that answers the first request that way is sent the second,
/// so a printer, a router or any other web server is sent one request and nothing more. Both
/// requests are reads that carry no credentials.
public struct HubProProbe: HubProbe {

  /// The client the requests are sent with, which can't carry credentials.
  public let httpClient: UnauthenticatedHTTPClient

  /// The port the Hub Pro's HTTP interface is looked for on.
  public let port: Int

  /// How long each request has to answer, in all.
  public let timeout: Duration

  /// Creates a probe.
  ///
  /// - Parameters:
  ///   - port: The port to look for the Hub Pro's HTTP interface on.
  ///   - httpClient: The client to send the requests with, which can't carry credentials.
  ///     Defaults to `UnauthenticatedHTTPClient.localNetwork()`.
  ///   - timeout: How long each request has to answer, in all. Defaults to
  ///     ``HubDiscovery/defaultProbeTimeout``.
  public init(
    port: Int,
    httpClient: UnauthenticatedHTTPClient = .localNetwork(),
    timeout: Duration = HubDiscovery.defaultProbeTimeout
  ) {

    self.port = port
    self.httpClient = httpClient
    self.timeout = timeout

  }

  /// Asks a host whether it's a Hub Pro.
  ///
  /// - Parameter host: The host's IPv4 address.
  /// - Returns: The Hub Pro at the host and the probe's port, or `nil` if the host doesn't
  ///   answer as one.
  /// - Throws: `HubError.invalidEndpoint(_:)` if the port is outside 0 to 65,535,
  ///   `HTTPClientError.proxyConfigured` if the requests would go through a proxy, on Linux, or
  ///   `CancellationError` if the task is canceled.
  public func probe(host: String) async throws -> DiscoveredHub? {

    let endpoint = HubEndpoint(host: host, port: port)

    guard
      let gate = try await HubProbeRequest.send(try Self.get("/", at: endpoint), with: httpClient, timeout: timeout),
      gate.statusCode == 401,
      gate.value(forHeader: "WWW-Authenticate") == nil,
      let answer = try await HubProbeRequest.send(try Self.get("/settings", at: endpoint), with: httpClient, timeout: timeout),
      answer.statusCode == 200,
      let settings = try? JSONDecoder().decode(HubProSettings.self, from: answer.body)
    else {

      return nil

    }

    return DiscoveredHub(endpoint: endpoint, kind: .hubPro, hubProSettings: settings)

  }

  private static func get(_ path: String, at endpoint: HubEndpoint) throws(HubError) -> URLRequest {

    var components = URLComponents()
    components.scheme = "http"
    components.host = endpoint.host
    components.port = endpoint.port
    components.path = path

    guard (0...65_535).contains(endpoint.port), let url = components.url else {

      throw .invalidEndpoint(endpoint)

    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    request.httpShouldHandleCookies = false

    return request

  }

}

/// Sends a probe's request.
enum HubProbeRequest {

  /// Sends a request, giving up after a time in all.
  ///
  /// - Returns: The response, or `nil` if nothing answered, as when nothing listens on the
  ///   port or the host doesn't answer in time.
  /// - Throws: `HTTPClientError.proxyConfigured` or `HTTPClientError.credentialsRefused` if
  ///   the client refuses to send the request, or `CancellationError` if the task is canceled.
  static func send(_ request: URLRequest, with client: UnauthenticatedHTTPClient, timeout: Duration) async throws -> HTTPResponse? {

    var request = request
    request.timeoutInterval = timeout.timeInterval

    let sent: URLRequest = request

    do {

      // The request's own timeout limits only the wait between bytes, so an address that
      // answers a byte at a time is given up on too.
      return try await withDeadline(timeout) {

        try await client.send(sent)

      }

    } catch let error as HTTPClientError where error == .proxyConfigured || error == .credentialsRefused {

      // The client wouldn't send the request at all, so it wouldn't send any other either.
      throw error

    } catch {

      try Task.checkCancellation()

      return nil

    }

  }

}
