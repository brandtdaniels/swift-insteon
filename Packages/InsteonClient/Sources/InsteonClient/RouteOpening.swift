import Foundation
import InsteonNetworking

/// Turns a transport's route into an address on this device.
///
/// A transport plugin carries requests to the service and listens on a local address, such as
/// `http://127.0.0.1:9100`. The opener starts or reuses that listener for one route's ticket and
/// returns the address. This library speaks the same service contract to it as to a local address.
public protocol RouteOpening: Sendable {

  /// The route kind this opener serves, as the pairing document names it.
  var kind: String { get }

  /// Opens a route and returns the local address that reaches the service through it.
  ///
  /// - Parameter ticket: What the document's route carries for this transport.
  func open(ticket: String?) async throws -> URL

}

/// A route that a transport carries, reached through the address its opener returns.
struct RemoteRoutePath: ConnectionPath {

  let name: String
  let opener: any RouteOpening
  let ticket: String?
  let token: String
  let http: any HTTPClient

  func open() async throws -> any ConnectionCalls {
    let address: URL
    do {
      address = try await opener.open(ticket: ticket)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw ConnectionPathError.notReached("the \(name) route didn't open")
    }
    return try await ServicePath(name: name, baseURL: address, token: token, http: http).open()
  }

}

extension ClientPairing {

  /// The paths a pairing yields, and the routes left out with the reason for each.
  struct RoutePlan {
    var paths: [any ConnectionPath] = []
    var skipped: [PathFailure] = []
  }

  /// Turns the routes into paths, in the document's order, and records each route it can't use.
  func routePlan(transports: [any RouteOpening], http: any HTTPClient) -> RoutePlan {
    var plan = RoutePlan()
    for route in routes {
      if route.kind == "lan" {
        guard let text = route.url, let url = URL(string: text), let host = url.host, ["http", "https"].contains(url.scheme?.lowercased()) else {
          plan.skipped.append(PathFailure(path: "lan", reason: "the route has no usable address"))
          continue
        }
        guard url.scheme?.lowercased() == "https" || LocalAddress.isLocal(host: host) else {
          plan.skipped.append(PathFailure(path: "lan", reason: "the token is never sent over HTTP to a host outside the local network"))
          continue
        }
        plan.paths.append(ServicePath(name: "lan", baseURL: url, token: credential, http: http))
      } else if let opener = transports.first(where: { $0.kind == route.kind }) {
        plan.paths.append(RemoteRoutePath(name: route.kind, opener: opener, ticket: route.ticket, token: credential, http: http))
      } else {
        plan.skipped.append(PathFailure(path: route.kind, reason: "this device has no transport for the \(route.kind) route"))
      }
    }
    return plan
  }

}

extension ClientConnection {

  /// Creates a connection from a pairing document.
  ///
  /// The paths are `local`, when there is one, then the document's routes in its order. A `lan`
  /// route goes straight to its address, and a route of a kind an opener serves goes through it.
  /// A route that can't be used is left out and named, with its reason, in the error when no path
  /// is reached: a kind no opener serves, an address that isn't one, or plain HTTP to a host outside
  /// the local network, since the credential never crosses the internet unencrypted. Every route sends
  /// the document's credential.
  ///
  /// - Parameters:
  ///   - pairing: The document the service showed.
  ///   - local: The path to try before any route, such as a ``LocalHubPath``.
  ///   - routeOpeners: The transports this device has.
  ///   - http: Sends the requests.
  public init(pairing: ClientPairing, local: (any ConnectionPath)? = nil, routeOpeners: [any RouteOpening], http: any HTTPClient) {
    let plan = pairing.routePlan(transports: routeOpeners, http: http)
    self.init(paths: (local.map { [$0] } ?? []) + plan.paths, skipped: plan.skipped)
  }

}
