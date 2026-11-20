import Foundation
import Testing
import InsteonCLISupport
import InsteonCore
import InsteonHubClient
import InsteonHubPro
import InsteonModem
import InsteonProtocol

struct HubTextTests {

  @Test func aHubThatNeverAnswersIsLookedForWithDiscover() {

    let message: String = HubText.unanswered(host: "hub.example", port: 25105)

    #expect(message == "The Hub at hub.example:25105 didn't answer. If its address changed, 'insteon discover' finds it.")

  }

  @Test func aHubThatStopsAnsweringDuringADeviceCommandNamesTheDevice() {

    let message: String = HubText.stoppedAnswering(host: "hub.example", port: 25105, device: InsteonAddress(0x4D, 0x5E, 0x6F))

    #expect(message == "The Hub stopped answering while it was waiting for 4D.5E.6F. Check that the device is powered and in range, then try again.")
    #expect(!message.contains("insteon discover"))

  }

  @Test func aHubThatStopsAnsweringDuringAnotherCommandSaysToTryAgain() {

    let message: String = HubText.stoppedAnswering(host: "hub.example", port: 25105, device: nil)

    #expect(message == "The Hub at hub.example:25105 stopped answering partway through the command. Try again.")
    #expect(!message.contains("insteon discover"))

  }

  // MARK: - Which failure

  struct Other: Error {}

  @Test func wordsAHubThatStoppedAnsweringOrNeverDid() {

    let device = InsteonAddress(0x4D, 0x5E, 0x6F)

    #expect(
      HubText.failure(HubStoppedAnswering(underlyingError: URLError(.timedOut)), host: "hub.example", port: 25105, device: device)
        == HubText.stoppedAnswering(host: "hub.example", port: 25105, device: device)
    )
    #expect(HubText.failure(URLError(.timedOut), host: "hub.example", port: 25105, device: device) == HubText.unanswered(host: "hub.example", port: 25105))
    #expect(HubText.failure(Other(), host: "hub.example", port: 25105, device: device) == nil)

  }

  // A Hub at an unreachable address leaves the modem's first command to time out; the Hub is
  // what didn't answer.
  @Test func saysTheHubDidNotAnswerWhenOnlyTheModemTimedOutAndTheHubNeverAnswered() {

    let timedOut = ModemError.timedOut(.getModemInfo)

    #expect(
      HubText.failure(timedOut, host: "hub.example", port: 25105, device: nil, hubHasAnswered: false)
        == HubText.unanswered(host: "hub.example", port: 25105)
    )
    #expect(HubText.failure(timedOut, host: "hub.example", port: 25105, device: nil, hubHasAnswered: true) == nil)

  }

  // MARK: - A Hub Pro

  private let settings = HubProSettings(
    time: "t",
    network: HubProSettings.Network(address: "192.168.1.50"),
    version: HubProSettings.Versions(
      config: HubProSettings.SoftwareVersion(version: "5.0.1"),
      server: HubProSettings.SoftwareVersion(version: "1.0.2")
    )
  )

  @Test func saysUnderTheTableHowToUseTheHubProsListed() {

    #expect(HubText.hubProNote(settings: [settings]) == [
      "A Hub Pro is listed. Use --hub with its address to read and control its devices; it has no ALL-Link database to change.",
      "Hub Pro at 192.168.1.50 reports configuration version 5.0.1 and server version 1.0.2.",
    ])
    #expect(HubText.hubProNote(settings: [nil, nil]) == ["Hub Pros are listed. Use --hub with an address to read and control a Hub Pro's devices; they have no ALL-Link database to change."])
    #expect(HubText.hubProNote(settings: []).isEmpty)

  }

  @Test func namesTheDeviceTheCommandIsFor() throws {

    let device = InsteonAddress(0x4D, 0x5E, 0x6F)

    #expect(try Invocation.parse(["device", "4D.5E.6F", "status"]).device == device)
    #expect(try Invocation.parse(["link", "4D.5E.6F"]).device == device)
    #expect(try Invocation.parse(["unlink", "4D.5E.6F"]).device == device)
    #expect(try Invocation.parse(["remove", "4D.5E.6F", "--yes"]).device == device)
    #expect(try Invocation.parse(["link"]).device == nil)
    #expect(try Invocation.parse(["links"]).device == nil)

  }

}
