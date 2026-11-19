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

extension ServerTests {
  @Test func theAdvertisedAddressAndHomeNameAreOptionsWithDefaults() throws {
    let defaults = try ServerOptions(arguments: [], environment: [:])
    #expect(defaults.advertiseURL == nil)
    #expect(defaults.homeName == "Home")
    let chosen = try ServerOptions(arguments: ["--advertise-url", "https://insteon.example.net:8443/", "--home-name", "Beach house"], environment: [:])
    #expect(chosen.advertiseURL == "https://insteon.example.net:8443")
    #expect(chosen.homeName == "Beach house")
  }

  @Test(arguments: [["--advertise-url", "insteon.local"], ["--advertise-url", "ftp://insteon.local"], ["--advertise-url", "http://u:p@insteon.local"], ["--advertise-url", "http://insteon.local/x"], ["--advertise-url", "http://insteon.local?x=1"], ["--advertise-url", "http://"], ["--home-name", String(repeating: "h", count: 65)], ["--home-name", "bad\u{7}name"]])
  func anUnusableAdvertisedAddressOrHomeNameIsRefused(_ arguments: [String]) {
    #expect(throws: ServerOptionError.self) { try ServerOptions(arguments: arguments, environment: [:]) }
  }
}
