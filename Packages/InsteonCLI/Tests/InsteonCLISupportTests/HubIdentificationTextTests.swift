import Testing
import InsteonCLISupport
import InsteonCore

struct HubIdentificationTextTests {

  struct Unreachable: Error, CustomStringConvertible {

    var description: String { "unreachable" }

  }

  @Test func matchesANamedHubOnTheHubsPortByDefault() {

    #expect(HubAddress(host: "192.168.0.20").matches(host: "192.168.0.20", port: HubLocation.defaultPort))
    #expect(!HubAddress(host: "192.168.0.20").matches(host: "192.168.0.20", port: 8080))
    #expect(HubAddress(host: "192.168.0.20", port: 8080).matches(host: "192.168.0.20", port: 8080))
    #expect(!HubAddress(host: "192.168.0.20").matches(host: "192.168.0.21", port: HubLocation.defaultPort))

  }

  @Test func saysWhyAHubWasntIdentifiedAndNothingWhenItWasOrWasDeclined() {

    let message: (any Error) -> String = { "\($0)" }
    let note = { (outcome: HubIdentification) -> String? in

      HubText.identification(outcome, host: "203.0.113.5", port: 8080, message: message)

    }

    #expect(note(.declined) == nil)
    #expect(note(.skippedNonPrivateAddress) == "203.0.113.5 isn't a private address, so it wasn't sent the password.")
    #expect(
      note(.skippedNonHubPort)
        == "203.0.113.5:8080 isn't on the Hub's port, 25105, so it wasn't sent the password. 'insteon discover --identify 203.0.113.5:8080' sends it."
    )
    #expect(note(.didNotAnswer) == "203.0.113.5:8080 didn't answer Get IM Info in time.")
    #expect(note(.rejected(Unreachable())) == "203.0.113.5:8080: unreachable")
    #expect(note(.failed(Unreachable())) == "203.0.113.5:8080: unreachable")

  }

}
