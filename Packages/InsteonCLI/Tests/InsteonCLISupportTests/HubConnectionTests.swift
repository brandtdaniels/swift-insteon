import Testing
import InsteonCLISupport
import InsteonCore

/// Where the `insteon` command connects for '--hub HOST[:PORT]'.
struct HubConnectionTests {

  @Test func connectsToAPrivateHostOnTheHubsPortByDefault() throws {

    #expect(try ModemTarget.hubLocation(host: "192.168.0.20", port: nil) == HubLocation(host: "192.168.0.20", port: HubLocation.defaultPort))
    #expect(try ModemTarget.hubLocation(host: "192.168.0.20", port: 8080) == HubLocation(host: "192.168.0.20", port: 8080))

  }

  @Test func refusesAHostThatWouldntBeSentThePasswordBeforeConnecting() {

    #expect(throws: HubAddressRefused(host: "203.0.113.5")) {

      try ModemTarget.hubLocation(host: "203.0.113.5", port: nil)

    }

  }

}
