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
  @Test func theHubProPollIntervalDefaultsToFiveSecondsAndStartsAtTwo() throws {
    #expect(try ServerOptions(arguments: [], environment: [:]).pollIntervalSeconds == 5)
    #expect(try ServerOptions(arguments: ["--poll-interval", "2"], environment: [:]).pollIntervalSeconds == 2)
    #expect(try ServerOptions(arguments: ["--poll-interval", "3600"], environment: [:]).pollIntervalSeconds == 3600)
  }

  @Test(arguments: ["1", "0", "-5", "3601", "fast", "2.5"])
  func aPollIntervalBelowTheFloorOrNotANumberIsRefused(_ value: String) {
    #expect(throws: ServerOptionError.invalidPollInterval) { try ServerOptions(arguments: ["--poll-interval", value], environment: [:]) }
  }

  @Test func theAdvertisedAddressAndNetworkNameAreOptionsWithDefaults() throws {
    let defaults = try ServerOptions(arguments: [], environment: [:])
    #expect(defaults.advertiseURL == nil)
    #expect(defaults.networkName == "Network")
    let chosen = try ServerOptions(arguments: ["--advertise-url", "https://insteon.example.net:8443/", "--network-name", "Beach house"], environment: [:])
    #expect(chosen.advertiseURL == "https://insteon.example.net:8443")
    #expect(chosen.networkName == "Beach house")
  }

  @Test(arguments: [["--advertise-url", "insteon.local"], ["--advertise-url", "ftp://insteon.local"], ["--advertise-url", "http://u:p@insteon.local"], ["--advertise-url", "http://insteon.local/x"], ["--advertise-url", "http://insteon.local?x=1"], ["--advertise-url", "http://"], ["--network-name", String(repeating: "h", count: 65)], ["--network-name", "bad\u{7}name"]])
  func anUnusableAdvertisedAddressOrNetworkNameIsRefused(_ arguments: [String]) {
    #expect(throws: ServerOptionError.self) { try ServerOptions(arguments: arguments, environment: [:]) }
  }
}

extension ServerTests {
  @Test func theLocationAndTimeZoneAreOptionsWithoutDefaults() throws {
    let defaults = try ServerOptions(arguments: [], environment: [:])
    #expect(defaults.latitude == nil && defaults.longitude == nil && defaults.timeZone == nil)
    let chosen = try ServerOptions(arguments: ["--latitude", "-33.87", "--longitude", "151.21", "--time-zone", "Australia/Sydney"], environment: [:])
    #expect(chosen.latitude == -33.87 && chosen.longitude == 151.21 && chosen.timeZone == "Australia/Sydney")
  }

  @Test(arguments: [
    ["--latitude", "34"], ["--longitude", "-118"], ["--latitude", "91", "--longitude", "0"], ["--latitude", "0", "--longitude", "181"],
    ["--latitude", "north", "--longitude", "0"], ["--latitude", "nan", "--longitude", "0"]
  ])
  func aLocationNeedsBothCoordinatesWithinRange(_ arguments: [String]) {
    #expect(throws: ServerOptionError.invalidLocation) { try ServerOptions(arguments: arguments, environment: [:]) }
  }

  @Test(arguments: ["Not a zone", "../etc/localtime", "bad\u{7}zone", String(repeating: "z", count: 65)])
  func aTimeZoneThatIsNotAZoneNameIsRefused(_ name: String) {
    #expect(throws: ServerOptionError.invalidTimeZone) { try ServerOptions(arguments: ["--time-zone", name], environment: [:]) }
  }

  @Test func aTimeZoneTheHostMightNotHaveIsStillAccepted() throws {
    #expect(try ServerOptions(arguments: ["--time-zone", "Not/AZone"], environment: [:]).timeZone == "Not/AZone")
  }
}
