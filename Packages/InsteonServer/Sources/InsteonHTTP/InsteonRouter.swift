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
  makeRegisteredRouter(service: service, authentication: authentication, logger: logger, now: now).router
}

/// Builds the router and says which operations it registered. Every route comes from ``APIOperation``,
/// so the routes served and the routes described are the same list.
func makeRegisteredRouter<Service: InsteonServiceAPI>(service: Service, authentication: any HTTPAuthenticating, logger: Logger, now: @escaping @Sendable () -> Date) -> (router: Router<BasicRequestContext>, registered: [APIOperation]) {
  let router = Router<BasicRequestContext>()
  router.add(middleware: SecurityHeadersMiddleware<BasicRequestContext>())
  router.add(middleware: ErrorMappingMiddleware<BasicRequestContext>())
  router.add(middleware: RequestLogMiddleware<BasicRequestContext>(logger: logger))
  router.add(middleware: AuthenticationMiddleware<BasicRequestContext>(authentication: authentication))
  router.add(middleware: RequestBodyLimitMiddleware<BasicRequestContext>())
  let api = DeviceAPI(service: service, idempotency: IdempotencyStore(now: now))
  let website = DeviceWebsite(service: service)

  // The one place a route is registered. The switch is exhaustive, so an operation without a handler doesn't compile.
  func handler(for operation: APIOperation) -> @Sendable (Request, BasicRequestContext) async throws -> Response {
    switch operation {
    case .listDevices: { _, _ in try await api.devices() }
    case .health: { _, _ in try await api.health() }
    case .executeCommand: { request, context in try await api.command(request, address: context.parameters.get("address")) }
    case .streamEvents: { request, _ in await api.events(resumingAfter: EventCursor(request)) }
    case .openAPI: { _, _ in Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(bytes: OpenAPIDocument.bytes))) }
    case .browserIndex: { request, _ in try await website.index(request) }
    case .browserControls: { _, _ in Response(status: .ok, headers: [.contentType: "text/javascript; charset=utf-8"], body: .init(byteBuffer: ByteBuffer(string: BrowserControls.source))) }
    case .browserCard: { _, context in try await website.device(address: context.parameters.get("address")) }
    case .browserCommand: { request, context in try await website.command(request, address: context.parameters.get("address")) }
    }
  }
  var registered: [APIOperation] = []
  for operation in APIOperation.allCases {
    router.on(RouterPath(operation.path), method: operation.method, use: handler(for: operation))
    registered.append(operation)
  }
  return (router, registered)
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
