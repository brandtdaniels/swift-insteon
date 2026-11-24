import Foundation

/// Registers a transport's route with the service, and removes it again.
///
/// A route is a `kind` and a `ticket`. The kind names the transport; the ticket is the opaque
/// locator only that transport reads. The service lists each registered route in the pairing
/// documents it issues afterward, after the `lan` route. Registering needs an `admin` token.
public struct RouteRegistrar: Sendable {
  private let service: ServiceClient

  /// Creates a registrar.
  /// - Parameter service: The service, with an `admin` token.
  public init(service: ServiceClient) {
    self.service = service
  }

  /// Registers the route, or replaces the ticket of the route with that kind.
  /// - Throws: A ``PluginError``: ``PluginError/unauthorized(status:code:)`` for a token without the `admin` scope.
  public func register(kind: String, ticket: String) async throws {
    let body = try JSONSerialization.data(withJSONObject: ["ticket": ticket])
    let response = try await service.send("PUT", "/api/v1/routes/" + kind, body: body)
    if let failure = response.failure { throw failure }
  }

  /// Removes the route, so the pairing documents issued afterward don't list it.
  ///
  /// Removing a route the service doesn't hold isn't a failure: the route is gone either way.
  public func unregister(kind: String) async throws {
    let response = try await service.send("DELETE", "/api/v1/routes/" + kind)
    if response.status == 404, response.errorCode == "unknownRouteRegistration" { return }
    if let failure = response.failure { throw failure }
  }
}
