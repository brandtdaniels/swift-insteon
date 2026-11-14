import Foundation
import Hummingbird
import HummingbirdTesting
import InsteonGateway
import Testing
@testable import InsteonServerSupport

@Suite(.timeLimit(.minutes(1)))
struct ServerTests {
  let password = String(repeating: "p", count: 40)

  @Test(arguments: [TestingSetup.router, .live])
  func httpBoundaryRequiresAuthenticationAndServesHTML(_ setup: TestingSetup) async throws {
    let gateway = try Gateway(controller: EmptyController(), password: password)
    let app = Application(responder: GatewayHTTPResponder(gateway: gateway))
    try await app.test(setup) { client in
      try await client.execute(uri: "/", method: .get) { response in
        #expect(response.status == .unauthorized)
        #expect(response.headers[.wwwAuthenticate] != nil)
      }
      try await client.execute(uri: "/api/v1/events", method: .get) { response in
        #expect(response.status == .unauthorized)
      }
      let authorization = "Basic " + Data(("insteon:" + password).utf8).base64EncodedString()
      try await client.execute(uri: "/", method: .get, headers: [.authorization: authorization]) { response in
        #expect(response.status == .ok)
        #expect(response.headers[.contentType] == "text/html; charset=utf-8")
        #expect(String(buffer: response.body).contains("Insteon home"))
        #expect(response.headers[.cacheControl] == "no-store")
      }
      try await client.execute(uri: "/api/v1/devices", method: .get, headers: [.authorization: authorization]) { response in
        #expect(response.status == .ok)
        #expect(String(buffer: response.body).contains("\"version\":1"))
      }
    }
  }

  @Test func adapterBoundsBodiesBeforePassingThemToGateway() async throws {
    let gateway = try Gateway(controller: EmptyController(), password: password)
    let app = Application(responder: GatewayHTTPResponder(gateway: gateway))
    let authorization = "Basic " + Data(("insteon:" + password).utf8).base64EncodedString()
    try await app.test(.router) { client in
      try await client.execute(uri: "/api/v1/devices/1A.2B.3C/commands", method: .post, headers: [.authorization: authorization, .contentType: "application/json"], body: ByteBuffer(repeating: 32, count: 8193)) { response in
        #expect(response.status == .contentTooLarge)
      }
    }
  }

  @Test func configDefaultsToLoopbackAndCanBindToVPNAddress() throws {
    let defaults = try ServerOptions(arguments: [], environment: [:])
    #expect(defaults.listen == "127.0.0.1")
    #expect(defaults.port == 8080)
    let vpn = try ServerOptions(arguments: ["--listen", "100.100.20.30", "--port", "8888"], environment: [:])
    #expect(vpn.listen == "100.100.20.30")
    #expect(vpn.port == 8888)
  }

  @Test func missingOrWeakServerPasswordFailsBeforeConnectingToHardware() async {
    await #expect(throws: ServerRunError.self) {
      try await ServerRunner.run(arguments: ["--hub", "192.168.1.20"], environment: [:])
    }
    await #expect(throws: GatewayConfigurationError.self) {
      try await ServerRunner.run(arguments: ["--hub", "192.168.1.20"], environment: ["INSTEON_GATEWAY_PASSWORD": "short"])
    }
  }

  @Test(arguments: [["--listen", "0.0.0.0"], ["--listen", "8.8.8.8"], ["--listen", "example.com"], ["--port", "0"], ["--port", "65536"], ["--hub"], ["--unknown", "value"], ["--port", "8080", "--port", "8081"]])
  func invalidConfigurationIsRefused(_ arguments: [String]) {
    #expect(throws: ServerOptionError.self) { try ServerOptions(arguments: arguments, environment: [:]) }
  }
}

private struct EmptyController: GatewayControlling {
  func devices() async throws -> [GatewayDevice] { [] }
  func perform(_ command: GatewayCommand) async throws -> GatewayCommandResult {
    GatewayCommandResult(address: command.address, outcome: .acknowledged, status: nil)
  }
}
