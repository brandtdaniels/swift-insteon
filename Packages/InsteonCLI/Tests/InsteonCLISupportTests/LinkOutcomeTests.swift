import Testing
import InsteonCLISupport
import InsteonCore
import InsteonProtocol

/// What `insteon link` and `insteon unlink` say about a link that isn't the one asked for.
struct LinkOutcomeTests {

  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)

  let other = InsteonAddress(0x4D, 0x5E, 0x6F)

  func link(_ mode: AllLinkMode, with device: InsteonAddress, group: AllLinkGroupNumber = 0) -> LinkMade {

    LinkMade(address: device, group: group, mode: mode)

  }

  @Test func acceptsTheLinkAskedFor() {

    #expect(LinkOutcome.mismatch(link(.controller, with: lamp), mode: .linking, device: lamp) == nil)
    #expect(LinkOutcome.mismatch(link(.responder, with: lamp), mode: .linking, device: nil) == nil)
    #expect(LinkOutcome.mismatch(link(.delete, with: lamp), mode: .unlinking, device: lamp) == nil)

  }

  @Test func explainsAnotherDevicesLink() {

    let linked: String = "The modem reported 4D.5E.6F, not 1A.2B.3C: another device's SET button was pressed, "
      + "and the modem linked with it in group 3. Run the command again for 1A.2B.3C."
    let removed: String = "The modem reported 4D.5E.6F, not 1A.2B.3C: another device's SET button was pressed, "
      + "and the modem removed its link with it in group 0. Run the command again for 1A.2B.3C."

    #expect(LinkOutcome.mismatch(link(.controller, with: other, group: 3), mode: .linking, device: lamp) == linked)
    #expect(LinkOutcome.mismatch(link(.delete, with: other), mode: .unlinking, device: lamp) == removed)

  }

  // Another device is reported first, even when its link is also of the wrong kind.
  @Test func explainsAnotherDeviceBeforeTheWrongMode() {

    let message: String? = LinkOutcome.mismatch(link(.delete, with: other), mode: .linking, device: lamp)

    #expect(message?.hasPrefix("The modem reported 4D.5E.6F, not 1A.2B.3C") == true)

  }

  @Test func explainsADeviceThatLinkedInsteadOfUnlinking() {

    let expected: String = "1A.2B.3C linked again in group 1 instead of unlinking: it was in linking mode, not unlinking mode. "
      + "Put it into unlinking mode (on most devices, hold its SET button until it beeps, then hold it again until it beeps again) "
      + "and run the command again."

    #expect(LinkOutcome.mismatch(link(.responder, with: lamp, group: 1), mode: .unlinking, device: lamp) == expected)

  }

  @Test func explainsADeviceThatUnlinkedInsteadOfLinking() {

    let expected: String = "1A.2B.3C removed its link in group 0 instead of linking: it was in unlinking mode, not linking mode. "
      + "Run the command again, and hold its SET button only until it first beeps."

    #expect(LinkOutcome.mismatch(link(.delete, with: lamp), mode: .linking, device: nil) == expected)

  }

  // MARK: - unlink --all

  @Test func saysWhichLinkIsBeingRemoved() {

    let controls: String = LinkingInstructions.remoteUnlinking(modemRole: .controller, device: "1A.2B.3C", group: 0)
    let responds: String = LinkingInstructions.remoteUnlinking(modemRole: .responder, device: "1A.2B.3C", group: 1)

    #expect(controls.hasPrefix("Removing 1A.2B.3C from the modem's group 0:"))
    #expect(responds.hasPrefix("Removing the modem from 1A.2B.3C's group 1:"))

  }

  @Test func givesTheDevicesOwnUnlinkingStepsWhenRemoteUnlinkingFails() {

    let lines: [String] = LinkingInstructions.setButtonUnlinking(device: "1A.2B.3C", steps: ["Hold the SET button.", "Hold it again."])

    #expect(lines == [
      "Remove the links that are left with the SET button of 1A.2B.3C. To put it into unlinking mode:",
      "  1. Hold the SET button.",
      "  2. Hold it again.",
    ])
    #expect(LinkingInstructions.setButtonUnlinking(device: "1A.2B.3C", steps: []).count == 1)

  }

}
