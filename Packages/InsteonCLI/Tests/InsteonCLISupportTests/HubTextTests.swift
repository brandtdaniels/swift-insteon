import Testing
import InsteonCLISupport
import InsteonCore

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

}
