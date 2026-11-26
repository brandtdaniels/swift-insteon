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

    /// A field the document needs is missing or isn't of the right kind. It names the field, such
    /// as `credential` or `routes[0].kind`.
    case missing(String)

    /// A field has a value the document's format doesn't allow, such as a version that isn't the
    /// integer 1, a scope other than `read`, `control` or `admin`, an empty credential or an empty
    /// route kind. It names the field.
    case invalid(String)

    /// The document lists no routes, so nothing says how to reach the service.
    case noRoutes

  }

  /// Names the service, the same for every client that pairs with it.
  public let serviceID: String

  /// The service's name, for a client to show.
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
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw Failure.unreadable }
    guard let number = object["version"] as? NSNumber else { throw Failure.missing("version") }
    // JSON true and 1.0 read as the number 1; only the integer 1 is version 1.
    guard (try? JSONDecoder().decode(Version.self, from: data)) != nil, !["d", "f"].contains(String(cString: number.objCType)) else {
      throw Failure.invalid("version")
    }
    let version = number.intValue
    guard version == 1 else { throw Failure.unsupportedVersion(version) }
    func text(_ key: String) throws -> String {
      guard let value = object[key] as? String else { throw Failure.missing(key) }
      return value
    }
    serviceID = try text("serviceId")
    name = try text("name")
    credential = try text("credential")
    scope = try text("scope")
    guard ["read", "control", "admin"].contains(scope) else { throw Failure.invalid("scope") }
    guard !credential.isEmpty else { throw Failure.invalid("credential") }
    guard let listed = object["routes"] as? [[String: Any]] else { throw Failure.missing("routes") }
    guard !listed.isEmpty else { throw Failure.noRoutes }
    routes = try listed.enumerated().map { index, route in
      guard let kind = route["kind"] as? String else { throw Failure.missing("routes[\(index)].kind") }
      guard !kind.isEmpty else { throw Failure.invalid("routes[\(index)].kind") }
      return Route(kind: kind, url: route["url"] as? String, ticket: route["ticket"] as? String)
    }
  }

  /// Names the service and its routes, never the credential.
  public var description: String { "ClientPairing(\(name), routes: \(routes.map(\.kind)))" }

  public var debugDescription: String { description }

  /// A version that decodes only from a JSON integer, never from `true`.
  private struct Version: Decodable {
    let version: Int
  }

}
