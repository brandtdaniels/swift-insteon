import Hummingbird
import InsteonService

/// Builds the HTTP adapter around one service instance and an independent authentication policy.
/// Security, request limits, errors, API coding and browser presentation stay in this package.
public func makeInsteonRouter<Service: InsteonServiceAPI>(service: Service, authentication: any HTTPAuthenticating) -> Router<BasicRequestContext> {
  let router = Router<BasicRequestContext>()
  router.add(middleware: SecurityHeadersMiddleware<BasicRequestContext>())
  router.add(middleware: AuthenticationMiddleware<BasicRequestContext>(authentication: authentication))
  router.add(middleware: ErrorMappingMiddleware<BasicRequestContext>())
  router.add(middleware: RequestBodyLimitMiddleware<BasicRequestContext>())
  let api = DeviceAPI(service: service)
  let website = DeviceWebsite(service: service)
  router.get("/controls.js") { _, _ in
    Response(status: .ok, headers: [.contentType: "text/javascript; charset=utf-8"], body: .init(byteBuffer: ByteBuffer(string: BrowserControls.source)))
  }
  router.get("/") { request, _ in try await website.index(request) }
  router.get("/api/v1/devices") { _, _ in try await api.devices() }
  router.post("/api/v1/devices/{address}/commands") { request, context in
    try await api.command(request, address: context.parameters.get("address"))
  }
  router.get("/api/v1/events") { _, _ in await api.events() }
  router.post("/devices/{address}") { request, context in
    try await website.command(request, address: context.parameters.get("address"))
  }
  return router
}
