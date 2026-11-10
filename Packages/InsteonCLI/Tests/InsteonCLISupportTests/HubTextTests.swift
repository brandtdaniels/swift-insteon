import Foundation
import Testing
import InsteonCLISupport
import InsteonCore
import InsteonHubClient
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
