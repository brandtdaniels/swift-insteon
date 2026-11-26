import Foundation

/// What a client reads from the pairing document the service shows once: a credential and the
/// routes that reach the service.
///
/// The document is the same object whatever carries it, a QR code, a link or a file. A reader
/// ignores fields it doesn't know, so fields can be added inside version 1.
public struct ClientPairing: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {

  /// One way to reach the service, as the document lists it.
  public struct Route: Sendable, Equatable {

    /// `lan` for a direct address, or the identifier of a transport.
    public let kind: String

    /// Where a `lan` route is reached.
    public let url: String?

    /// What a transport needs to reach the service. Only that transport reads it.
    public let ticket: String?

    /// Creates a route.
    public init(kind: String, url: String?, ticket: String?) {
      self.kind = kind
      self.url = url
      self.ticket = ticket
    }

  }

  /// Why a document couldn't be read.
  public enum Failure: Error, Equatable, Sendable {

    /// The bytes aren't a pairing document.
    case unreadable

    /// The document is of a version this library doesn't read.
    case unsupportedVersion(Int)

  }

  /// Names the service, the same for every client that pairs with it.
  public let serviceID: String

  /// The home's name, for a client to show.
  public let name: String

  /// What the credential may do: `read`, `control` or `admin`.
  public let scope: String

  /// The routes, most preferred first.
  public let routes: [Route]

  let credential: String

  /// Reads a document.
  ///
  /// - Throws: ``Failure`` when the bytes aren't a version 1 document.
  public init(decoding data: Data) throws {
    let wire: Wire
    do {
      wire = try JSONDecoder().decode(Wire.self, from: data)
    } catch {
      throw Failure.unreadable
    }
    guard wire.version == 1 else { throw Failure.unsupportedVersion(wire.version) }
    serviceID = wire.serviceId
    name = wire.name
    scope = wire.scope
    credential = wire.credential
    routes = wire.routes.map { Route(kind: $0.kind, url: $0.url, ticket: $0.ticket) }
  }

  init(serviceID: String, name: String, scope: String, routes: [Route], credential: String) {
    self.serviceID = serviceID
    self.name = name
    self.scope = scope
    self.routes = routes
    self.credential = credential
  }

  /// Names the home and its routes, never the credential.
  public var description: String { "ClientPairing(\(name), routes: \(routes.map(\.kind)))" }

  public var debugDescription: String { description }

  private struct Wire: Decodable {
    let version: Int
    let serviceId: String
    let name: String
    let credential: String
    let scope: String
    let routes: [WireRoute]
  }

  private struct WireRoute: Decodable {
    let kind: String
    let url: String?
    let ticket: String?
  }

}
