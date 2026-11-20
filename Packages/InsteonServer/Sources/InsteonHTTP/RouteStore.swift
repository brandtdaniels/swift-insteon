import Foundation

/// A route a transport registered: the transport's kind and the ticket only that transport reads.
///
/// A pairing document lists it after the LAN route. A client that doesn't know the kind skips it.
public struct RegisteredRoute: Codable, Sendable, Equatable {
  /// The transport's identifier: lowercase letters, digits and `-`, starting with a letter.
  public let kind: String
  /// What the transport needs to reach the service. The service never reads it.
  public let ticket: String

  /// Creates a route.
  public init(kind: String, ticket: String) {
    self.kind = kind
    self.ticket = ticket
  }

  /// The route as a pairing document lists it.
  public var pairingRoute: PairingRoute { PairingRoute(kind: kind, ticket: ticket) }
}

/// What the routes file holds.
public struct RouteRegistry: Codable, Sendable, Equatable {
  /// The file's format.
  public var version = 1
  /// The routes, in the order they were registered.
  public var routes: [RegisteredRoute]

  /// Creates a registry.
  public init(routes: [RegisteredRoute]) { self.routes = routes }
}

/// Where the registered routes live between runs.
///
/// Calls are synchronous so a change reads, edits and writes the registry without another change
/// slipping in between.
public protocol RoutePersisting: Sendable {
  /// The stored registry, or `nil` when none has been stored.
  func load() throws -> RouteRegistry?
  /// Replaces the stored registry.
  func save(_ registry: RouteRegistry) throws
}

/// Why a route operation was refused.
public enum RouteError: Error, Equatable, Sendable {
  /// The kind isn't a short lowercase identifier, or the ticket is empty, too long or has anything but printable ASCII.
  case invalidRoute
  /// No route is registered for that kind.
  case unknownRoute
  /// The service already keeps the most routes it keeps.
  case limitReached
  /// The routes couldn't be read or written, so nothing changed.
  case notSaved
}

/// The routes transports registered: listing, registering, replacing and removing them.
public protocol RouteStoring: Sendable {
  /// The routes, in the order they were registered.
  func routes() async throws -> [RegisteredRoute]
  /// Registers the route, or replaces the ticket of the route with that kind, which keeps its place.
  func put(kind: String, ticket: String) async throws -> RegisteredRoute
  /// Removes the route with that kind.
  func remove(kind: String) async throws
}

/// Keeps the registered routes in a ``RoutePersisting``, or in memory when there is none.
///
/// Every call reads the stored registry again, so a route another process stored is seen at once, as
/// the `pair` command sees the routes of a running server.
public actor RouteStore: RouteStoring {
  /// The most routes the store keeps.
  public static let maximumRoutes = 8
  /// The most characters a ticket has.
  public static let longestTicket = 1024
  /// The most characters a kind has.
  public static let longestKind = 32

  private let persistence: (any RoutePersisting)?
  private var memory: [RegisteredRoute] = []

  /// Creates a store.
  /// - Parameter persistence: Where the routes live. Without one they last as long as the store.
  public init(persistence: (any RoutePersisting)? = nil) {
    self.persistence = persistence
  }

  public func routes() throws -> [RegisteredRoute] {
    guard let persistence else { return memory }
    do { return try persistence.load()?.routes ?? [] } catch { throw RouteError.notSaved }
  }

  public func put(kind: String, ticket: String) throws -> RegisteredRoute {
    guard Self.isValid(kind: kind), Self.isValid(ticket: ticket) else { throw RouteError.invalidRoute }
    var stored = try routes()
    let route = RegisteredRoute(kind: kind, ticket: ticket)
    if let index = stored.firstIndex(where: { $0.kind == kind }) {
      stored[index] = route
    } else {
      guard stored.count < Self.maximumRoutes else { throw RouteError.limitReached }
      stored.append(route)
    }
    try commit(stored)
    return route
  }

  public func remove(kind: String) throws {
    var stored = try routes()
    guard stored.contains(where: { $0.kind == kind }) else { throw RouteError.unknownRoute }
    stored.removeAll { $0.kind == kind }
    try commit(stored)
  }

  private func commit(_ routes: [RegisteredRoute]) throws {
    if let persistence {
      do { try persistence.save(RouteRegistry(routes: routes)) } catch { throw RouteError.notSaved }
    }
    memory = routes
  }

  /// A kind is 1 through 32 lowercase ASCII letters, digits and `-`, starting with a letter. `lan` is the service's own.
  static func isValid(kind: String) -> Bool {
    guard kind != "lan", (1...longestKind).contains(kind.utf8.count), let first = kind.utf8.first, (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(first) else { return false }
    return kind.utf8.allSatisfy { ($0 >= UInt8(ascii: "a") && $0 <= UInt8(ascii: "z")) || ($0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9")) || $0 == UInt8(ascii: "-") }
  }

  /// What a ticket matches: 1 through 1024 printable ASCII characters, none of them a space.
  static let ticketPattern = "^[!-~]{1,\(longestTicket)}$"

  /// A ticket is 1 through 1024 printable ASCII characters without spaces, which every transport can carry in a QR code, a link or a file.
  static func isValid(ticket: String) -> Bool {
    (1...longestTicket).contains(ticket.utf8.count) && ticket.utf8.allSatisfy { (UInt8(ascii: "!")...UInt8(ascii: "~")).contains($0) }
  }
}
