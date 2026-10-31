import Testing
import InsteonCore

/// `ModemSession.withHub` sends the Hub's credentials only to a private IPv4 address, and
/// refuses any other host before anything is sent. Every host here is refused before a request,
/// so nothing reaches a network.
@Suite(.timeLimit(.minutes(1)))
struct HubAddressTests {

  @Test(arguments: [
    "172.15.255.255",
    "172.32.0.0",
    "169.254.1.1",
    "127.0.0.1",
    "19.168.1.20",
    "hub.local",
    "::1",
    "fe80::1",
    "192.168.1.20:25105",
  ])
  func withHubRefusesAHostThatIsntAPrivateIPv4Address(_ host: String) async {

    let ran: Ran = Ran()

    await #expect(throws: HubAddressRefused(host: host)) {

      try await ModemSession.withHub(host: host, port: HubLocation.defaultPort, user: "user", password: "secret") { _ in

        await ran.mark()

      }

    }

    #expect(await ran.didRun == false)

  }

  @Test(arguments: ["10.0.0.0", "172.16.0.1", "172.31.255.255", "192.168.255.255"])
  func aPrivateIPv4AddressAcceptsCredentials(_ host: String) {

    #expect(HubLocation(host: host, port: HubLocation.defaultPort).acceptsCredentials)

  }

  @Test(arguments: ["172.15.255.255", "172.32.0.0", "169.254.1.1", "127.0.0.1", "hub.local", "::1"])
  func anyOtherHostDoesnt(_ host: String) {

    #expect(!HubLocation(host: host, port: HubLocation.defaultPort).acceptsCredentials)

  }

  @Test func theRefusalSaysWhatToGiveWithoutTheCredentials() {

    let error: HubAddressRefused = HubAddressRefused(host: "hub.local")
    let message: String = InsteonErrorDescription.message(for: error) ?? ""

    #expect(message.contains("hub.local"))
    #expect(message.contains("192.168.0.0/16"))
    #expect(!message.contains("secret"))

  }

  @Test func theRefusalPrintsNoControlCharacters() {

    let error: HubAddressRefused = HubAddressRefused(host: "hub\u{1B}[2J.local")

    #expect(!error.description.unicodeScalars.contains { $0.properties.generalCategory == .control })

  }

}

/// Whether a session's body ran.
actor Ran {

  private(set) var didRun = false

  func mark() {

    didRun = true

  }

}
