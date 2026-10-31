import Testing
import InsteonCLISupport

struct ModemTargetTests {

  @Test func readsTheHubAndItsPort() throws {

    #expect(try ModemTarget.resolve(hub: "192.168.1.20", serialPath: nil, environment: [:]) == .hub(host: "192.168.1.20", port: nil))
    #expect(try ModemTarget.resolve(hub: "192.168.1.20:8080", serialPath: nil, environment: [:]) == .hub(host: "192.168.1.20", port: 8080))
    #expect(try ModemTarget.resolve(hub: "hub.local", serialPath: nil, environment: [:]) == .hub(host: "hub.local", port: nil))

  }

  @Test func readsTheHubFromTheEnvironment() throws {

    let environment = ["INSTEON_HUB_HOST": "192.168.1.20", "INSTEON_HUB_PORT": "8080"]

    #expect(try ModemTarget.resolve(hub: nil, serialPath: nil, environment: environment) == .hub(host: "192.168.1.20", port: 8080))

  }

  @Test func prefersTheCommandLineOverTheEnvironment() throws {

    let environment = ["INSTEON_HUB_HOST": "192.168.1.20", "INSTEON_HUB_PORT": "8080"]

    #expect(try ModemTarget.resolve(hub: "192.168.1.30:9090", serialPath: nil, environment: environment) == .hub(host: "192.168.1.30", port: 9090))
    #expect(try ModemTarget.resolve(hub: nil, serialPath: "/dev/ttyUSB0", environment: environment) == .serial(path: "/dev/ttyUSB0"))

  }

  @Test func needsAModem() {

    #expect(throws: ConfigurationError.noModem) {

      try ModemTarget.resolve(hub: nil, serialPath: nil, environment: ["INSTEON_HUB_HOST": ""])

    }

  }

  @Test func rejectsBothKindsOfModem() {

    #expect(throws: ConfigurationError.conflictingModems) {

      try ModemTarget.resolve(hub: "192.168.1.20", serialPath: "/dev/ttyUSB0", environment: [:])

    }

  }

  @Test func rejectsAMalformedHub() {

    #expect(throws: ConfigurationError.invalidPort("70000")) {

      try ModemTarget.resolve(hub: "192.168.1.20:70000", serialPath: nil, environment: [:])

    }

    #expect(throws: ConfigurationError.invalidPort("")) {

      try ModemTarget.resolve(hub: "192.168.1.20:", serialPath: nil, environment: [:])

    }

    #expect(throws: ConfigurationError.invalidHost(":25105")) {

      try ModemTarget.resolve(hub: ":25105", serialPath: nil, environment: [:])

    }

    #expect(throws: ConfigurationError.invalidPort("http")) {

      try ModemTarget.resolve(hub: nil, serialPath: nil, environment: ["INSTEON_HUB_HOST": "192.168.1.20", "INSTEON_HUB_PORT": "http"])

    }

  }

  // MARK: - Credentials

  @Test func readsTheCredentialsFromTheEnvironment() throws {

    let environment = ["INSTEON_HUB_USERNAME": "example-user", "INSTEON_HUB_PASSWORD": "example-password"]

    #expect(try HubCredentials(environment: environment) == HubCredentials(user: "example-user", password: "example-password"))

  }

  @Test func needsBothCredentials() {

    #expect(throws: ConfigurationError.missingCredentials) {

      try HubCredentials(environment: ["INSTEON_HUB_USERNAME": "example-user"])

    }

    #expect(throws: ConfigurationError.missingCredentials) {

      try HubCredentials(environment: ["INSTEON_HUB_USERNAME": "example-user", "INSTEON_HUB_PASSWORD": ""])

    }

  }

  @Test func neverPrintsTheCredentials() {

    let credentials = HubCredentials(user: "example-user", password: "example-password")
    var dumped = ""
    dump(credentials, to: &dumped)

    for text in [String(describing: credentials), String(reflecting: credentials), "\(credentials)", dumped] {

      #expect(!text.contains("example-user"))
      #expect(!text.contains("example-password"))

    }

  }

}
