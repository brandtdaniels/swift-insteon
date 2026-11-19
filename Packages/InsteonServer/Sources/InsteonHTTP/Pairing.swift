import Foundation

/// One way a client can reach the service, in a pairing document.
///
/// A client tries a document's routes in order and uses the first that answers
/// `GET /api/v1/health`. It skips a kind it doesn't know.
public struct PairingRoute: Codable, Sendable, Equatable {
  /// What kind of route it is: `lan` for a direct address, or the identifier of a transport.
  public let kind: String
  /// Where a `lan` route is reached, such as `http://insteon.local:8080`.
  public let url: String?
  /// What a transport needs to reach the service. Only that transport reads it.
  public let ticket: String?

  /// Creates a route.
  public init(kind: String, url: String? = nil, ticket: String? = nil) {
    self.kind = kind
    self.url = url
    self.ticket = ticket
  }
}

/// What a client needs to pair with the service: a credential and the routes to reach it.
///
/// It is the same object whatever carries it, a QR code, a link or a file. A reader ignores fields
/// it doesn't know, so fields can be added inside version 1.
public struct PairingDocument: Codable, Sendable, Equatable {
  /// The document's format, always 1.
  public let version: Int
  /// Names the service, the same for every client that pairs with it.
  public let serviceId: String
  /// The home's name, for a client to show.
  public let name: String
  /// The client's token, which the service shows once.
  public let credential: String
  /// What the credential may do.
  public let scope: ClientScope
  /// The path every API route sits under.
  public let api: String
  /// How to reach the service, most preferred first.
  public let routes: [PairingRoute]

  /// The document as JSON with sorted keys and indentation.
  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(self)
  }
}

/// The home's name and the routes a pairing document lists.
public struct PairingConfiguration: Sendable, Equatable {
  /// The home's name, for a client to show.
  public var homeName: String
  /// How to reach the service, most preferred first.
  public var routes: [PairingRoute]

  /// Creates a configuration.
  public init(homeName: String = "Home", routes: [PairingRoute] = []) {
    self.homeName = homeName
    self.routes = routes
  }

  /// The document that hands `issued` to a client of the service named `serviceID`.
  public func document(for issued: IssuedClient, serviceID: String) -> PairingDocument {
    PairingDocument(version: 1, serviceId: serviceID, name: homeName, credential: issued.token, scope: issued.client.scope, api: "/api/v1", routes: routes)
  }
}
