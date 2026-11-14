import Hummingbird
import InsteonService

/// Browser presentation needs only queries and commands, not an event source or modem type.
struct DeviceWebsite<Service: DeviceQuerying & DeviceCommanding>: Sendable {
  let service: Service
  private let forms = BrowserFormProtection()

  init(service: Service) { self.service = service }

  func index(_ request: Request) async throws -> Response {
    let notice = request.uri.queryParameters["notice"] == "persistence-failed" ? "The device operation completed, but its snapshot could not be saved. Do not repeat the control just to retry storage." : nil
    let page = HTMLRenderer.page(devices: try await service.devices(), formKey: forms.key, notice: notice)
    return Response(status: .ok, headers: [.contentType: "text/html; charset=utf-8"], body: .init(byteBuffer: ByteBuffer(string: page)))
  }

  func command(_ request: Request, address: String?) async throws -> Response {
    let input = try await forms.command(request)
    let receipt = try await service.execute(input.serviceCommand(address: address))
    return Response(status: .seeOther, headers: [.location: receipt.persistence == .failed ? "/?notice=persistence-failed" : "/"])
  }
}
