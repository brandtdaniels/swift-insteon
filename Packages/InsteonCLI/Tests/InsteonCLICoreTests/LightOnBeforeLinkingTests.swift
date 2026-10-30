import Testing
import InsteonCLICore
import InsteonProtocol

struct LightOnBeforeLinkingTests {

  @Test func aDeviceThatDidNotTurnOnIsToldToLinkAgainForFullOn() {

    let device = InsteonAddress(0x4D, 0x5E, 0x6F)
    let message: String = LinkingInstructions.didNotTurnOnBeforeLinking(
      device,
      reason: "Device 4D.5E.6F rejected the command: it isn't linked to the modem."
    )

    #expect(
      message == "4D.5E.6F didn't turn on: Device 4D.5E.6F rejected the command: it isn't linked to the modem. "
        + "It links in the state it's in, so its on-level matches that state. "
        + "To give it full on, run 'insteon link 4D.5E.6F' again once it's linked, or turn it on at the device before linking."
    )
    #expect(!message.contains("turn it on first"))

  }

}
