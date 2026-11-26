import Foundation
import InsteonNetworking

/// Turns a transport's route into an address on this device.
///
/// A transport plugin carries requests to the home and listens on a local address, such as
/// `http://127.0.0.1:9100`. The opener starts or reuses that listener for one route's ticket and
/// returns the address. This library speaks the same service contract to it as to a local address.
public protocol RouteOpening: Sendable {

  /// The route kind this opener serves, as the pairing document names it.
  var kind: String { get }

  /// Opens a route and returns the local address that reaches the home through it.
  ///
  /// - Parameter ticket: What the document's route carries for this transport.
  func open(ticket: String?) async throws -> URL

}

/// A route that a transport carries, reached through the address its opener returns.
struct RemoteRoutePath: HomePath {

  let name: String
  let opener: any RouteOpening
  let ticket: String?
  let token: String
  let http: any HTTPClient

  func open() async throws -> any HomeCalls {
    let address: URL
    do {
      address = try await opener.open(ticket: ticket)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw HomePathError.notReached("the \(name) route didn't open")
    }
    return try await ServicePath(name: name, baseURL: address, token: token, http: http).open()
  }

}

extension ClientPairing {

  /// The paths a connection tries for this home, in the document's order.
  ///
  /// A `lan` route goes straight to its address, and a route of a kind a transport serves goes
  /// through it. A kind no transport serves is skipped, so an app never picks a route itself.
  /// Every path sends the document's credential.
  ///
  /// - Parameters:
  ///   - transports: The transports this device has.
  ///   - http: Sends the requests.
  public func homePaths(transports: [any RouteOpening], http: any HTTPClient = URLSessionHTTPClient()) -> [any HomePath] {
    var paths: [any HomePath] = []
    for route in routes {
      if route.kind == "lan" {
        if let text = route.url, let url = URL(string: text) {
          paths.append(ServicePath(name: "lan", baseURL: url, token: credential, http: http))
        }
      } else if let opener = transports.first(where: { $0.kind == route.kind }) {
        paths.append(RemoteRoutePath(name: route.kind, opener: opener, ticket: route.ticket, token: credential, http: http))
      }
    }
    return paths
  }

}

extension HomeConnection {

  /// Creates a connection from a pairing document.
  ///
  /// The paths are `local`, when there is one, then the document's routes in its order, as
  /// ``ClientPairing/homePaths(transports:http:)`` gives them.
  ///
  /// - Parameters:
  ///   - pairing: The document the service showed.
  ///   - local: The path to try before any route, such as a ``LocalHubPath``.
  ///   - routeOpeners: The transports this device has.
  ///   - http: Sends the requests.
  public init(pairing: ClientPairing, local: (any HomePath)? = nil, routeOpeners: [any RouteOpening], http: any HTTPClient) {
    self.init(paths: (local.map { [$0] } ?? []) + pairing.homePaths(transports: routeOpeners, http: http))
  }

}
