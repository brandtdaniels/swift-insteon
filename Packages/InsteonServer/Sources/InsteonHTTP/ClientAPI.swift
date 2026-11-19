import Foundation
import Hummingbird
import HTTPTypes

/// Creating, listing, revoking and re-pairing clients. Every operation needs the `admin` scope,
/// which the authentication middleware has already enforced.
struct ClientAPI: Sendable {
  let clients: any ClientStoring
  let pairing: PairingConfiguration
  let streams: EventStreamRegistry

  func list() async throws -> Response {
    try json(ClientListDTO(clients: try await clients.clients()))
  }

  func create(_ request: Request) async throws -> Response {
    guard HTTPBody.mediaType(request) == "application/json" else { throw HTTPInputError.unsupportedMedia }
    try HTTPBody.requireMarker(request)
    let input = try ClientRequest(try await HTTPBody.read(request))
    let issued = try await clients.issue(name: input.name, scope: input.scope)
    let document = pairing.document(for: issued, serviceID: try await clients.serviceID())
    return try json(ClientCreatedDTO(client: issued.client, pairing: document), status: .created)
  }

  func revoke(_ request: Request, id: String?) async throws -> Response {
    try HTTPBody.requireMarker(request)
    guard let id else { throw ClientError.unknownClient }
    try await revoke(id: id)
    return Response(status: .noContent)
  }

  /// Removes the client, then ends its open event streams.
  func revoke(id: String) async throws {
    try await clients.revoke(id: id)
    await streams.end(clientID: id)
  }

  func pair(_ request: Request, id: String?) async throws -> Response {
    try HTTPBody.requireMarker(request)
    guard let id else { throw ClientError.unknownClient }
    let issued = try await clients.rotate(id: id)
    // Streams opened with the old credential end, so only the new one is in use.
    await streams.end(clientID: id)
    return try json(pairing.document(for: issued, serviceID: try await clients.serviceID()))
  }

  private func json(_ value: some Encodable, status: HTTPResponse.Status = .ok) throws -> Response {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return Response(status: status, headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(bytes: try encoder.encode(value))))
  }
}

/// The body of a request to create a client. Unknown fields are refused.
struct ClientRequest: Decodable {
  let name: String
  let scope: ClientScope

  init(_ data: Data) throws {
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], Set(object.keys) == ["name", "scope"],
          let decoded = try? JSONDecoder().decode(Self.self, from: data) else { throw ClientRequestError.malformed }
    self = decoded
  }
}

/// A request body that isn't a name and a scope.
enum ClientRequestError: Error { case malformed }

struct ClientListDTO: Encodable {
  let version = 1
  let clients: [ClientRecord]
}

struct ClientCreatedDTO: Encodable {
  let version = 1
  let client: ClientRecord
  let pairing: PairingDocument
}
