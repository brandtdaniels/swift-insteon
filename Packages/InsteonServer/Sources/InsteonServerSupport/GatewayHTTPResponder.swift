import Foundation
import Hummingbird
import HTTPTypes
import InsteonGateway

/// Adapts HTTP to the gateway, checking authentication before collecting any request body.
public struct GatewayHTTPResponder: HTTPResponder {
  /// The request context supplied by the server framework.
  public typealias Context = BasicRequestContext
  private let gateway: Gateway
  private let controller: NetworkGatewayController?

  /// Creates an adapter. A controller enables the authenticated live event endpoint.
  public init(gateway: Gateway, controller: NetworkGatewayController? = nil) {
    self.gateway = gateway
    self.controller = controller
  }

  /// Handles the website, JSON API or event stream without logging supplied headers or bodies.
  public func respond(to request: Request, context: Context) async throws -> Response {
    let headers = Dictionary(request.headers.map { ($0.name.rawName.lowercased(), $0.value) }, uniquingKeysWith: { $0 + "," + $1 })
    let boundary = GatewayRequest(method: request.method.rawValue, path: request.uri.path, headers: headers)
    guard gateway.authorizes(headers["authorization"]) else {
      return convert(await gateway.respond(to: boundary))
    }
    if request.method == .get, request.uri.path == "/api/v1/events", let controller {
      let events = await controller.events()
      let body = ResponseBody { writer in
        try await writer.write(ByteBuffer(string: ": connected\n\n"))
        let encoder = JSONEncoder()
        for await event in events {
          try Task.checkCancellation()
          let data = try encoder.encode(event)
          try await writer.write(ByteBuffer(string: "data: " + String(decoding: data, as: UTF8.self) + "\n\n"))
        }
        try await writer.finish(nil)
      }
      var fields = securityFields()
      fields[.contentType] = "text/event-stream"
      return Response(status: .ok, headers: fields, body: body)
    }
    let buffer: ByteBuffer
    do {
      buffer = try await request.body.collect(upTo: 8192)
    } catch let error as any HTTPResponseError where error.status == .contentTooLarge {
      return Response(status: .contentTooLarge, headers: securityFields())
    }
    return convert(await gateway.respond(to: GatewayRequest(method: boundary.method, path: boundary.path, headers: headers, body: Data(buffer.readableBytesView))))
  }

  private func convert(_ response: GatewayResponse) -> Response {
    var headers = HTTPFields()
    for (name, value) in response.headers {
      if let name = HTTPField.Name(name) { headers[name] = value }
    }
    return Response(status: .init(code: response.status), headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: response.body)))
  }

  private func securityFields() -> HTTPFields {
    var fields = HTTPFields()
    for (name, value) in Gateway.securityHeaders {
      if let name = HTTPField.Name(name) { fields[name] = value }
    }
    return fields
  }
}
