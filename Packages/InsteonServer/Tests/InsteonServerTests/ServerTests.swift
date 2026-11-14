import Testing
@testable import InsteonServerSupport

@Suite(.timeLimit(.minutes(1)))
struct ServerTests {
  @Test func configDefaultsToLoopbackAndCanBindToVPNAddress() throws {
    let defaults = try ServerOptions(arguments: [], environment: [:])
    #expect(defaults.listen == "127.0.0.1")
    #expect(defaults.port == 8080)
    let vpn = try ServerOptions(arguments: ["--listen", "100.100.20.30", "--port", "8888"], environment: [:])
    #expect(vpn.listen == "100.100.20.30")
    #expect(vpn.port == 8888)
  }

  @Test func missingOrWeakServerPasswordFailsBeforeConnectingToHardware() async {
    await #expect(throws: ServerRunError.missingPassword) {
      try await ServerRunner.run(arguments: ["--hub", "192.168.1.20"], environment: [:])
    }
    await #expect(throws: ServerRunError.invalidPassword) {
      try await ServerRunner.run(arguments: ["--hub", "192.168.1.20"], environment: ["INSTEON_GATEWAY_PASSWORD": "short"])
    }
  }

  @Test(arguments: [["--listen", "0.0.0.0"], ["--listen", "8.8.8.8"], ["--listen", "example.com"], ["--port", "0"], ["--port", "65536"], ["--hub"], ["--unknown", "value"], ["--port", "8080", "--port", "8081"]])
  func invalidConfigurationIsRefused(_ arguments: [String]) {
    #expect(throws: ServerOptionError.self) { try ServerOptions(arguments: arguments, environment: [:]) }
  }
}
