import Foundation
import Testing
@testable import InsteonGateway

@Suite(.timeLimit(.minutes(1)))
struct GatewayTests {
  private let password = String(repeating: "p", count: 40)
  private let formKey = "test-form-key"

  private func request(_ method: String, _ path: String, _ body: String = "", type: String? = nil, authenticated: Bool = true, api: Bool = false) -> GatewayRequest {
    var headers: [String: String] = [:]
    if authenticated { headers["Authorization"] = "Basic " + Data(("insteon:" + password).utf8).base64EncodedString() }
    headers["Content-Type"] = type
    if api { headers["X-Insteon-Request"] = "1" }
    return GatewayRequest(method: method, path: path, headers: headers, body: Data(body.utf8))
  }

  @Test func unauthorizedRequestsNeverReachTheController() async throws {
    let controller = RecordingController()
    let gateway = try Gateway(controller: controller, password: password, formKey: formKey)
    let response = await gateway.respond(to: request("GET", "/api/v1/devices", authenticated: false))
    #expect(response.status == 401)
    #expect(response.headers["WWW-Authenticate"] != nil)
    #expect(await controller.reads == 0)
    #expect(await controller.commands.isEmpty)
  }

  @Test func websiteEscapesNamesAndUsesProtectedFormsWithoutScripts() async throws {
    let controller = RecordingController()
    let gateway = try Gateway(controller: controller, password: password, formKey: formKey)
    let response = await gateway.respond(to: request("GET", "/"))
    let page = String(decoding: response.body, as: UTF8.self)
    #expect(response.status == 200)
    #expect(page.contains("&lt;script&gt;Example&lt;/script&gt;"))
    #expect(!page.contains("<script>"))
    #expect(page.contains("method=\"post\""))
    #expect(page.contains("name=\"formKey\""))
    #expect(page.contains("Cached"))
    #expect(response.headers["Cache-Control"] == "no-store")
    #expect(await controller.commands.isEmpty)
  }

  @Test func apiReturnsVersionedDeviceData() async throws {
    let gateway = try Gateway(controller: RecordingController(), password: password, formKey: formKey)
    let response = await gateway.respond(to: request("GET", "/api/v1/devices"))
    let list = try JSONDecoder().decode(GatewayDeviceList.self, from: response.body)
    #expect(list.version == 1)
    #expect(list.devices.first?.address == "1A.2B.3C")
    #expect(!String(decoding: response.body, as: UTF8.self).contains(password))
  }

  @Test func commandsRequireExplicitPostsAndAPIMarker() async throws {
    let controller = RecordingController()
    let gateway = try Gateway(controller: controller, password: password, formKey: formKey)
    let path = "/api/v1/devices/1A.2B.3C/commands"
    let body = #"{"action":"on","levelPercent":50}"#
    #expect(await gateway.respond(to: request("GET", path)).status == 404)
    #expect(await gateway.respond(to: request("POST", path, body)).status == 415)
    #expect(await gateway.respond(to: request("POST", path, body, type: "application/json")).status == 403)
    #expect(await gateway.respond(to: request("POST", path, body, type: "application/json", api: true)).status == 200)
    #expect(await controller.commands == [GatewayCommand(address: "1A.2B.3C", action: .on, levelPercent: 50)])
  }

  @Test(arguments: [#"{"action":"on","levelPercent":101}"#, #"{"action":"on","levelPercent":-1}"#, #"{"action":"off","levelPercent":50}"#, #"{"action":"remove"}"#, #"{"action":"on","levelPercent":"50"}"#, "{", #"{"action":"on","levle":50}"#])
  func invalidCommandsNeverReachHardware(_ json: String) async throws {
    let controller = RecordingController()
    let gateway = try Gateway(controller: controller, password: password, formKey: formKey)
    #expect(await gateway.respond(to: request("POST", "/api/v1/devices/1A.2B.3C/commands", json, type: "application/json", api: true)).status == 400)
    #expect(await controller.commands.isEmpty)
  }

  @Test func formsRequireTheirKeyAndRedirectAfterCommands() async throws {
    let controller = RecordingController()
    let gateway = try Gateway(controller: controller, password: password, formKey: formKey)
    #expect(await gateway.respond(to: request("POST", "/devices/1A.2B.3C", "action=off", type: "application/x-www-form-urlencoded")).status == 403)
    #expect(await controller.commands.isEmpty)
    let response = await gateway.respond(to: request("POST", "/devices/1A.2B.3C", "action=off&formKey=" + formKey, type: "application/x-www-form-urlencoded"))
    #expect(response.status == 303)
    #expect(response.headers["Location"] == "/")
    #expect(await controller.commands.count == 1)
  }

  @Test func errorsAreRedactedAndCommandsAreNotRetried() async throws {
    let controller = RecordingController(fails: true)
    let gateway = try Gateway(controller: controller, password: password, formKey: formKey)
    let response = await gateway.respond(to: request("POST", "/api/v1/devices/1A.2B.3C/commands", #"{"action":"off"}"#, type: "application/json", api: true))
    #expect(response.status == 502)
    #expect(!String(decoding: response.body, as: UTF8.self).contains("private diagnostic"))
    #expect(await controller.commands.count == 1)
  }

  @Test func rejectsOversizedRequestsAndInvalidAddresses() async throws {
    let controller = RecordingController()
    let gateway = try Gateway(controller: controller, password: password, formKey: formKey)
    #expect(await gateway.respond(to: request("POST", "/api/v1/devices/1A.2B.3C/commands", String(repeating: " ", count: 8193), type: "application/json", api: true)).status == 413)
    #expect(await gateway.respond(to: request("POST", "/api/v1/devices/invalid/commands", #"{"action":"off"}"#, type: "application/json", api: true)).status == 400)
    #expect(await controller.commands.isEmpty)
  }

  @Test func weakPasswordsAreRefused() throws {
    #expect(throws: GatewayConfigurationError.self) {
      try Gateway(controller: RecordingController(), password: "short", formKey: formKey)
    }
  }

  @Test func concurrentRequestsDoNotInterleaveControllerOperations() async throws {
    let controller = PausedController()
    let gateway = try Gateway(controller: controller, password: password, formKey: formKey)
    let first = request("GET", "/api/v1/devices")
    try await withThrowingTaskGroup(of: GatewayResponse.self) { group in
      group.addTask { await gateway.respond(to: first) }
      await controller.waitUntilReading()
      let second = await gateway.respond(to: request("GET", "/api/v1/devices"))
      #expect(second.status == 409)
      await controller.finish()
      let response = try await group.next()
      #expect(response?.status == 200)
    }
  }
}

actor RecordingController: GatewayControlling {
  var reads = 0
  var commands: [GatewayCommand] = []
  let fails: Bool
  init(fails: Bool = false) { self.fails = fails }
  func devices() async throws -> [GatewayDevice] {
    reads += 1
    return [GatewayDevice(address: "1A.2B.3C", productName: "<script>Example</script>", canTurnOnAndOff: true, canDim: true, value: 128, lastAnsweredAt: nil)]
  }
  func perform(_ command: GatewayCommand) async throws -> GatewayCommandResult {
    commands.append(command)
    if fails { throw Diagnostic() }
    return GatewayCommandResult(address: command.address, outcome: .acknowledged, status: nil)
  }
  struct Diagnostic: Error, CustomStringConvertible {
    var description: String { "private diagnostic" }
  }
}

private actor PausedController: GatewayControlling {
  private var reading = false
  private var started: CheckedContinuation<Void, Never>?
  private var release: CheckedContinuation<Void, Never>?

  func waitUntilReading() async {
    if !reading { await withCheckedContinuation { started = $0 } }
  }

  func finish() { release?.resume(); release = nil }

  func devices() async throws -> [GatewayDevice] {
    await withCheckedContinuation { continuation in
      release = continuation
      reading = true
      started?.resume()
      started = nil
    }
    return []
  }

  func perform(_ command: GatewayCommand) async throws -> GatewayCommandResult { throw GatewayControlError.busy }
}
