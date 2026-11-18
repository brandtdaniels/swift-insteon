import Foundation
import Hummingbird
import HTTPTypes
import InsteonService
import Logging

/// Builds the HTTP adapter around one service instance and an independent authentication policy.
/// Security, request limits, errors, API coding and browser presentation stay in this package.
///
/// Each request logs one record to `logger`: method, route template, status, duration and a stable
/// outcome code, with no path, query, header or body.
///
/// A command that carries an `Idempotency-Key` header is recorded for 10 minutes, up to 256 at a time,
/// measured by `now`, so a repeat returns its outcome without sending anything.
public func makeInsteonRouter<Service: InsteonServiceAPI>(service: Service, authentication: any HTTPAuthenticating, logger: Logger = Logger(label: "insteon-server"), now: @escaping @Sendable () -> Date = { Date() }) -> Router<BasicRequestContext> {
  let router = Router<BasicRequestContext>()
  router.add(middleware: SecurityHeadersMiddleware<BasicRequestContext>())
  router.add(middleware: ErrorMappingMiddleware<BasicRequestContext>())
  router.add(middleware: RequestLogMiddleware<BasicRequestContext>(logger: logger))
  router.add(middleware: AuthenticationMiddleware<BasicRequestContext>(authentication: authentication))
  router.add(middleware: RequestBodyLimitMiddleware<BasicRequestContext>())
  let api = DeviceAPI(service: service, idempotency: IdempotencyStore(now: now))
  let website = DeviceWebsite(service: service)
  router.get("/controls.js") { _, _ in
    Response(status: .ok, headers: [.contentType: "text/javascript; charset=utf-8"], body: .init(byteBuffer: ByteBuffer(string: BrowserControls.source)))
  }
  router.get("/") { request, _ in try await website.index(request) }
  router.get("/api/v1/devices") { _, _ in try await api.devices() }
  router.get("/api/v1/health") { _, _ in try await api.health() }
  router.post("/api/v1/devices/{address}/commands") { request, context in
    try await api.command(request, address: context.parameters.get("address"))
  }
  router.get("/api/v1/events") { request, _ in await api.events(resumingAfter: EventCursor(request)) }
  router.get("/devices/{address}") { _, context in
    try await website.device(address: context.parameters.get("address"))
  }
  router.post("/devices/{address}") { request, context in
    try await website.command(request, address: context.parameters.get("address"))
  }
  return router
}

extension EventCursor {
  /// Where a reconnecting client left off: the `Last-Event-ID` header, or the `lastEventId` query
  /// parameter for a client that can't set headers. An id the server can't read stands for another
  /// run, so the client is told to refresh.
  init?(_ request: Request) {
    let header = request.headers[HTTPField.Name("Last-Event-ID")!]
    let query = request.uri.queryParameters["lastEventId"].map { String($0) }
    guard let text = header ?? query else { return nil }
    self = EventCursor(token: text) ?? .unrecognized
  }
}
