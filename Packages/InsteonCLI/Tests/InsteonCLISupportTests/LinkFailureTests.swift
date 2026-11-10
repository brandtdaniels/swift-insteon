import Testing
import InsteonCLISupport
import InsteonCore
import InsteonLinking
import InsteonProtocol

/// When `insteon link` fails after the coordinator returns, and with which message.
struct LinkFailureTests {

  let device = InsteonAddress(0x1A, 0x2B, 0x3C)

  struct Failure: Error {}

  let message: (any Error) -> String = { (_: any Error) -> String in "It failed." }

  @Test func succeedsWhenEveryLinkWasMade() {

    let made = LinkMade(address: device, group: 0, mode: .controller)

    #expect(LinkingEventText.failure(DeviceLinkingResult(links: [made], device: nil, linkBackFailure: nil), message: message) == nil)

  }

  @Test func saysHowToLinkBackWhenTheLinkBackFailed() {

    let made = LinkMade(address: device, group: 0, mode: .controller)
    let result = DeviceLinkingResult(links: [made], device: nil, linkBackFailure: Failure())

    #expect(
      LinkingEventText.failure(result, message: message)
        == "1A.2B.3C is linked with the modem as controller, but it didn't link back: It failed. "
        + "To link back with its SET button, run 'insteon link 1A.2B.3C --responder'."
    )

  }

  @Test func saysNothingOfALinkBackWithoutALinkMade() {

    #expect(LinkingEventText.failure(DeviceLinkingResult(links: [], device: nil, linkBackFailure: Failure()), message: message) == nil)

  }

  @Test func namesAFailedLegBeforeAnythingElse() {

    let first = HubLinkingLeg(device: device, index: 0, count: 2, modemRole: .controller, modemGroup: 0, deviceGroup: 1)
    let second = HubLinkingLeg(device: device, index: 1, count: 2, modemRole: .responder, modemGroup: 1, deviceGroup: 1)
    let made = LinkMade(address: device, group: 0, mode: .controller)
    let result = DeviceLinkingResult(
      links: [made],
      device: nil,
      linkBackFailure: Failure(),
      legs: [
        HubLinkingLegOutcome(leg: first, status: .linked(made, by: .enterLinkingMode)),
        HubLinkingLegOutcome(leg: second, status: .failed(Failure()))
      ]
    )

    #expect(LinkingEventText.failure(result, message: message) == LinkingEventText.incompleteLegs(result, message: message))
    #expect(LinkingEventText.failure(result, message: message) != nil)

  }

}
