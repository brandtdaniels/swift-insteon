import Foundation
import Hummingbird
import HTTPTypes

/// Listing, registering and removing transport routes. Reading needs the `read` scope and writing the
/// `admin` scope, which the authentication middleware has already enforced.
struct RouteAPI: Sendable {
  let routes: any RouteStoring

  func list() async throws -> Response {
    try json(RouteListDTO(routes: try await routes.routes()))
  }

  func put(_ request: Request, kind: String?) async throws -> Response {
    guard HTTPBody.mediaType(request) == "application/json" else { throw HTTPInputError.unsupportedMedia }
    try HTTPBody.requireMarker(request)
    guard let kind else { throw RouteError.invalidRoute }
    let body = try RouteRequestBody(try await HTTPBody.read(request))
    return try json(RouteStoredDTO(route: try await routes.put(kind: kind, ticket: body.ticket)))
  }

  func remove(_ request: Request, kind: String?) async throws -> Response {
    try HTTPBody.requireMarker(request)
    guard let kind else { throw RouteError.unknownRoute }
    try await routes.remove(kind: kind)
    return Response(status: .noContent)
  }

  private func json(_ value: some Encodable) throws -> Response {
    Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(bytes: try JSONEncoder().encode(value))))
  }
}

/// The body of a request to register a route. Unknown fields are refused.
struct RouteRequestBody {
  let ticket: String

  init(_ data: Data) throws {
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], Set(object.keys) == ["ticket"],
          let ticket = object["ticket"] as? String, RouteStore.isValid(ticket: ticket) else { throw RouteError.invalidRoute }
    self.ticket = ticket
  }
}

struct RouteListDTO: Encodable {
  let version = 1
  let routes: [RegisteredRoute]
}

struct RouteStoredDTO: Encodable {
  let version = 1
  let route: RegisteredRoute
}
