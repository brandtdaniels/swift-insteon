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

  @Test func saysWhatEachLegDoes() {

    let leg = HubLinkingLeg(device: lamp, index: 1, count: 3, modemRole: .responder, modemGroup: 2, deviceGroup: 2)
    let link = AllLinkingCompleted(linkCode: 0x00, group: 2, address: lamp, category: nil, subcategory: nil, firmwareVersion: nil)

    #expect(notes(.hubLinkingLegStarted(leg)) == [
      "Leg 2 of 3: the modem starts ALL-Linking as responder of group 2, for 1A.2B.3C's group 2..."
    ])
    #expect(notes(.hubLinkingLegJoined(leg, by: .enterLinkingMode)) == [
      "1A.2B.3C took Enter Linking Mode for its group 2; waiting for the modem to report the link..."
    ])
    #expect(notes(.hubLinkingLegJoined(leg, by: .deviceFirst)) == ["1A.2B.3C is in linking mode."])
    #expect(notes(.hubLinkingLegJoined(leg, by: .setButton)).isEmpty)
    #expect(notes(.hubLinkingLegCompleted(leg, link: link)).isEmpty)
    #expect(notes(.allGroupsWhen(leg, condition: DeviceProfile.Group.Condition(flag: "linkToAllGroups", isSet: true))) == [
      "Leg 2 of 3 links every group 1A.2B.3C controls while its linkToAllGroups setting is on. "
        + "The setting isn't read or changed here; with it off, each group needs a link of its own."
    ])

  }

  @Test func saysClearlyWhenALegTheCatalogPromisesFails() {

    let promised = HubLinkingLeg(device: lamp, index: 0, count: 2, modemRole: .controller, modemGroup: 0, deviceGroup: 1, remoteEnterLinkingMode: .yes)
    let unknown = HubLinkingLeg(device: lamp, index: 1, count: 2, modemRole: .responder, modemGroup: 1, deviceGroup: 1, remoteEnterLinkingMode: .unknown)

    #expect(notes(.hubLinkingLegFailed(promised, reason: Failure(), notRun: [unknown])) == [
      "Leg 1 of 2 didn't link: It failed. The Insteon device catalog says 1A.2B.3C takes Enter Linking Mode, "
        + "so check that it's powered and in range, and that no other device is in linking mode.",
      "The leg after it wasn't run; run 'insteon link 1A.2B.3C' again to link it."
    ])
    #expect(notes(.hubLinkingLegFailed(unknown, reason: Failure(), notRun: [])) == ["Leg 2 of 2 didn't link: It failed."])

  }

  @Test func explainsALinkWhoseLaterLegFailed() {

    let first = HubLinkingLeg(device: lamp, index: 0, count: 2, modemRole: .controller, modemGroup: 0, deviceGroup: 1)
    let second = HubLinkingLeg(device: lamp, index: 1, count: 2, modemRole: .responder, modemGroup: 1, deviceGroup: 1)
    let made = AllLinkingCompleted(linkCode: 0x01, group: 0, address: lamp, category: nil, subcategory: nil, firmwareVersion: nil)
    let result = DeviceLinkingResult(
      links: [made],
      device: nil,
      linkBackFailure: nil,
      legs: [
        HubLinkingLegOutcome(leg: first, status: .linked(made, by: .enterLinkingMode)),
        HubLinkingLegOutcome(leg: second, status: .failed(Failure()))
      ]
    )
    let message: (any Error) -> String = { (_: any Error) -> String in "It failed." }

    #expect(LinkingEventText.incompleteLegs(result, message: message)
      == "1A.2B.3C linked 1 of its 2 legs; leg 2 of 2 didn't link: It failed. Run 'insteon link 1A.2B.3C' again to link the rest.")
    #expect(LinkingEventText.incompleteLegs(DeviceLinkingResult(links: [made], device: nil, linkBackFailure: nil), message: message) == nil)

  }

  @Test func saysHowTheDeviceIsKeptAwakeAndLetSleep() {

    #expect(notes(.keepAwake(.sending(lamp, timing: .afterLinked))) == ["Keeping 1A.2B.3C awake while it links, as the Insteon device catalog says..."])
    #expect(notes(.keepAwake(.sent(lamp))).isEmpty)
    #expect(notes(.keepAwake(.notSent(lamp, reason: Failure()))) == [
      "1A.2B.3C wasn't kept awake: It failed. Linking goes on; if it falls asleep, wake it and run the command again."
    ])
    #expect(notes(.keepAwake(.releasing(lamp))) == ["Letting 1A.2B.3C sleep again..."])
    #expect(notes(.keepAwake(.released(lamp))).isEmpty)
    #expect(notes(.keepAwake(.notReleased(lamp, reason: Failure()))) == [
      "1A.2B.3C wasn't let sleep again: It failed. It may stay awake and use its batteries until it sleeps on its own "
        + "or is woken and linked again."
    ])

  }

  @Test func asksForTheDeviceToBeWokenWithTheCatalogsSteps() {

    let steps: [DeviceLifecycle.Step] = [DeviceLifecycle.Step(text: "Press the Program button.")]

    #expect(LinkingEventText.wake(WakePrompt(device: lamp, deviceDescription: nil, steps: steps), waitsForReturn: true) == [
      "First wake 1A.2B.3C:",
      "  1. Press the Program button.",
      "Then press Return, and the modem keeps it awake while it links."
    ])
    #expect(LinkingEventText.wake(WakePrompt(device: lamp, deviceDescription: nil, steps: []), waitsForReturn: false) == [
      "First wake 1A.2B.3C; its manual says how, such as by pressing one of its buttons.",
      "The modem keeps it awake while it links now."
    ])

  }

  @Test func saysWhenALegFallsBackToTheSETButtonThoughEnterLinkingModeWasExpectedToWork() {

    let promised = HubLinkingLeg(device: lamp, index: 0, count: 2, modemRole: .controller, modemGroup: 0, deviceGroup: 1, remoteEnterLinkingMode: .yes)
    let unknown = HubLinkingLeg(device: lamp, index: 0, count: 2, modemRole: .controller, modemGroup: 0, deviceGroup: 1, remoteEnterLinkingMode: .unknown)

    #expect(notes(.fallback(.setButtonLeg(promised, reason: Failure()))) == [
      "1A.2B.3C didn't link remotely, though the Insteon device catalog says it takes Enter Linking Mode: It failed. "
        + "Link it with its SET button instead."
    ])
    #expect(notes(.fallback(.setButtonLeg(unknown, reason: Failure()))) == [
      "1A.2B.3C didn't link remotely: It failed. Link it with its SET button instead."
    ])

  }

}
