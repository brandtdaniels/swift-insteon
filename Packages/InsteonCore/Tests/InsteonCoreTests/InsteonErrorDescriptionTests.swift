import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import InsteonCore
import InsteonHubClient
import InsteonHubDiscovery
import InsteonLinking
import InsteonModem
import InsteonProtocol

/// What InsteonCore says about the lower-level modules' errors, and how it reads them.
struct InsteonErrorDescriptionTests {

  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)

  let other = InsteonAddress(0x4D, 0x5E, 0x6F)

  // MARK: - The modem

  @Test func aModemThatNeverAnswersIsCheckedForConnectionAndPower() {

    let message: String = InsteonErrorDescription.modemUnanswered(command: "Send Insteon Standard or Extended Message")

    #expect(message == "The modem didn't answer Send Insteon Standard or Extended Message. Check that it's connected and powered.")
    #expect(InsteonErrorDescription.message(for: ModemError.timedOut(.sendMessage)) == InsteonErrorDescription.modemUnanswered(command: SerialCommandNumber.sendMessage.name))

  }

  @Test func aModemThatStopsEchoingAMessageToADeviceNamesTheDevice() {

    let message: String = InsteonErrorDescription.didntConfirmSending(to: other)

    #expect(message == "The modem didn't confirm sending to 4D.5E.6F; it may still be busy with a device that isn't answering. Check that 4D.5E.6F is powered and in range, then try again.")
    #expect(!message.contains("connected and powered"))

  }

  @Test func describesADeviceThatDidntAnswer() {

    #expect(InsteonErrorDescription.message(for: ModemError.deviceTimedOut(lamp)) == "Device 1A.2B.3C didn't answer. Check its address, and that it's powered and in range.")

  }

  // MARK: - The Hub

  @Test func saysWhenTheHubRejectsItsCredentials() {

    let rejected: any Error = HubError.unexpectedStatus(401)

    #expect(InsteonErrorDescription.message(for: rejected) == "The Hub rejected its user name and password (HTTP 401).")
    #expect(InsteonErrorDescription.isRejectedHubCredentials(rejected))
    #expect(!InsteonErrorDescription.isRejectedHubCredentials(HubError.unexpectedStatus(500)))
    #expect(InsteonErrorDescription.message(for: HubError.unexpectedStatus(500)) == "The Hub answered with HTTP status 500.")

  }

  @Test func theInlineTextFollowsAColonWithoutTheDiscoverHint() {

    let message: String = InsteonErrorDescription.hubStoppedAnsweringInline

    #expect(message.first == "t")
    #expect(message.contains("stopped answering"))
    #expect(!message.contains("insteon discover"))
    #expect(InsteonErrorDescription.message(for: HubStoppedAnswering(underlyingError: URLError(.timedOut))) == message)

  }

  @Test func readsHowAHubStoppedAnswering() {

    #expect(HubFailure(HubStoppedAnswering(underlyingError: URLError(.timedOut))) == .stoppedAnswering)
    #expect(HubFailure(URLError(.timedOut)) == .unanswered)
    #expect(HubFailure(HubError.malformedBuffer) == nil)

  }

  // MARK: - Linking

  @Test func explainsAMismatchTheLibraryFound() {

    let removed = AllLinkingCompleted(linkCode: AllLinkMode.delete.rawValue, group: 0, address: lamp, category: nil, subcategory: nil, firmwareVersion: nil)
    let mismatch = LinkMismatch(link: removed, reason: .unlinkedInsteadOfLinking)
    let expected: String = "1A.2B.3C removed its link in group 0 instead of linking: it was in unlinking mode, not linking mode. "
      + "Run the command again, and hold its SET button only until it first beeps."

    #expect(InsteonErrorDescription.message(for: mismatch) == expected)
    #expect(InsteonErrorDescription.linkMismatch(removed, direction: .linking, device: nil) == expected)
    #expect(InsteonErrorDescription.linkMismatch(removed, direction: .unlinking, device: lamp) == nil)

  }

  @Test func describesNothingOfItsOwn() {

    #expect(InsteonErrorDescription.message(for: CancellationError()) == nil)

  }

  // MARK: - Sends

  @Test func readsWhatWentWrongWithASend() {

    let reason = NAKReason(rawValue: 0xFF)

    #expect(SendFailure(ModemError.rejected(.beep)) == .modemRejected)
    #expect(SendFailure(ModemError.timedOut(.beep)) == .modemUnanswered)
    #expect(SendFailure(ModemError.deviceRejected(lamp, reason)) == .deviceRejected(lamp, reason))
    #expect(SendFailure(ModemError.deviceTimedOut(lamp)) == .deviceUnanswered(lamp))
    #expect(SendFailure(ModemError.connectionClosed) == nil)
    #expect(SendFailure(CancellationError()) == nil)

  }

  // MARK: - Raw passthroughs

  @Test func fillsAnExtendedMessagesUserDataAndChecksum() {

    let standard = DirectMessage(to: lamp, command1: 0x19, command2: 0x00, data: nil, hasChecksum: true)
    let unchecked = DirectMessage(to: lamp, command1: 0x2E, command2: 0x00, data: [0x01], hasChecksum: false)
    let checked = DirectMessage(to: lamp, command1: 0x2E, command2: 0x00, data: [0x01], hasChecksum: true)

    #expect(standard.userData == nil)
    #expect(unchecked.userData == [0x01] + [UInt8](repeating: 0x00, count: 13))
    #expect(checked.userData?.count == 14)
    #expect(checked.userData?.first == 0x01)
    #expect(checked.userData?.last != 0x00)

  }

  @Test func showsAnEchoWithItsAcknowledgment() {

    let echo = CommandEcho(number: .beep, parameters: [], isAccepted: true)

    #expect(RawModemReply(.echo(echo)) == .echo(bytes: [0x02, 0x77, 0x06], kind: DeviceMonitor.replyKind(.echo(echo))))
    #expect(RawModemReply(.negativeAcknowledgment) == .negativeAcknowledgment)

  }

  // MARK: - Discovery

  @Test func keepsTheIdentityAHubReported() {

    var hub = HubCandidate(DiscoveredHub(endpoint: HubEndpoint(host: "hub.example"), foundBy: [.localNetwork, .insteonConnect]))
    let info = ModemInfo(address: other, category: 0x03, subcategory: 0x33, firmwareVersion: 0x9E)

    #expect(hub.foundBy == [.localNetwork, .insteonConnect])
    #expect(hub.port == HubLocation.defaultPort)
    #expect(hub.insteonID == nil)

    hub.record(info)

    #expect(hub.insteonID == other)
    #expect(hub.subcategory == 0x33)
    #expect(hub.firmwareVersion == 0x9E)

  }

}
