import Testing
import InsteonCLICore
import InsteonCore
import InsteonDeviceCatalog
import InsteonLinking
import InsteonProtocol

/// What `insteon link` and `insteon unlink` print for each step a coordinator takes, which
/// the hardware checklist relies on word for word.
struct LinkingEventTextTests {

  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)

  struct Failure: Error {}

  func notes(_ event: LinkingEvent) -> [String] {

    LinkingEventText.notes(for: event, message: { (_: any Error) -> String in "It failed." })

  }

  @Test func saysWhatTheLinkDoesBeforeTheModemStarts() {

    #expect(notes(.identifying(lamp)) == ["Asking 1A.2B.3C for its identity with ID Request..."])
    #expect(notes(.turningOnBeforeLinking(lamp)) == ["Turning 1A.2B.3C on with Light On first, so it links with full on as its on-level..."])
    #expect(notes(.notTurningOnBeforeLinking(lamp)) == [
      "Not turning 1A.2B.3C on first: the catalog doesn't identify it as a light or switched load, so it links with whatever on-level it captures."
    ])
    #expect(notes(.linkingRemotely(lamp, modemRole: .responder)) == [
      "Linking 1A.2B.3C without its SET button: the modem starts ALL-Linking as responder and sends the device Enter Linking Mode..."
    ])
    #expect(notes(.fallback(.setButtonLinking(lamp, reason: Failure()))) == [
      "1A.2B.3C didn't link remotely: It failed. Link it with its SET button instead."
    ])
    #expect(notes(.linkingBack(lamp, group: 1)) == [
      "Linking back: sending 1A.2B.3C Enter Linking Mode for its group 1, so the modem becomes its responder..."
    ])

  }

  @Test func tellsThePersonToPressTheSETButtonWithTheCatalogsSteps() {

    let steps: [DeviceLifecycle.Step] = [DeviceLifecycle.Step(text: "Hold the SET button.", expectation: "Beeps")]
    let prompt = SETButtonPrompt(direction: .linking, group: 0, timeout: .seconds(240), device: lamp, deviceDescription: nil, steps: steps)

    #expect(notes(.pressSETButton(prompt)) == [
      "The modem is in linking mode for group 0.",
      "Now, on 1A.2B.3C:",
      "  1. Hold the SET button. [Beeps]",
      "Waiting up to 240 seconds; Control-C stops."
    ])
    #expect(notes(.modemJoining(timeout: .seconds(240))) == ["The modem is joining as responder. Waiting up to 240 seconds; Control-C stops."])

  }

  @Test func asksForTheDeviceFirst() {

    let prompt = DeviceFirstPrompt(direction: .unlinking, device: nil, deviceDescription: nil, steps: [])

    #expect(LinkingEventText.deviceFirst(prompt, waitsForReturn: true) == [
      "First put the device into unlinking mode. On most devices, press and hold the SET button until it beeps, "
        + "then press and hold it again until it beeps again; the device's manual has its steps.",
      "Then press Return, and the modem joins as its responder."
    ])

  }

  @Test func saysWhichLinksAreLeft() {

    let links: [ModemLink] = [ModemLink(modemRole: .controller, group: 0), ModemLink(modemRole: .responder, group: 1)]

    #expect(notes(.linksRemaining(lamp, links)) == [
      "1A.2B.3C still has links in group 0; run 'insteon unlink 1A.2B.3C --group 0'.",
      "1A.2B.3C still has links in group 1; run 'insteon unlink 1A.2B.3C --group 1 --responder'."
    ])
    #expect(notes(.remainingLinksUnknown(lamp, reason: Failure())) == ["Couldn't check the modem for 1A.2B.3C's other links: It failed."])
    #expect(notes(.unlinkGroupChosen(lamp, group: 3, isFromModemRecords: true)) == [
      "The modem's records link 1A.2B.3C in group 3, so the unlink uses it."
    ])
    #expect(notes(.unlinkGroupChosen(lamp, group: 0, isFromModemRecords: false)) == [
      "The modem has no record for 1A.2B.3C in that role, so the unlink uses group 0."
    ])
    #expect(notes(.readingModemLinks(lamp, purpose: .findingLinksToRemove)) == ["Reading the modem's ALL-Link database for 1A.2B.3C's links..."])
    #expect(notes(.readingModemLinks(lamp, purpose: .findingGroupToUnlink)) == ["Reading the modem's ALL-Link database for 1A.2B.3C's groups..."])

  }

  @Test func leavesTheResultsToTheCommand() {

    let link = AllLinkingCompleted(linkCode: 0x01, group: 0, address: lamp, category: nil, subcategory: nil, firmwareVersion: nil)

    #expect(notes(.linked(LinkedDevice(link: link, device: nil, leg: .first))).isEmpty)
    #expect(notes(.unlinkedAll(RemovedLinks(address: lamp, device: nil, links: []))).isEmpty)

  }

}
