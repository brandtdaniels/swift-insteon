import Testing
import InsteonCLISupport
import InsteonCore
import InsteonDeviceCatalog
import InsteonProtocol

/// What the commands say when InsteonCore stops short of sending a message because the command
/// didn't grant what the message does. The words come from the protocol.
struct ConsentTextTests {

  static let device = InsteonAddress(0x3A, 0x4B, 0x01)

  @Test func deviceSendNamesForceForADestructiveMessage() {

    let sentence: String = SendRefusalText.sentence(.needsConsent(.destructive), from: .deviceSend)

    #expect(sentence == "The Insteon device catalog describes this message as one that removes or overwrites ALL-Link records, memory or counters, restores factory settings, or leaves the device unable to communicate with the modem; pass --force to send it.")
    #expect(ExitStatus.status(for: CommandFailure(description: sentence)) == ExitStatus.failure)

  }

  @Test func deviceSendReadsAnEffectItDoesntKnowAsDestructive() {

    #expect(SendRefusalText.sentence(.needsConsent(CommandEffect(rawValue: "sideEffect")), from: .deviceSend) == SendRefusalText.sentence(.needsConsent(.destructive), from: .deviceSend))

  }

  @Test func saysWhatAnEffectDoesInProtocolTerms() {

    #expect(ConsentText.clause(.readOnly) == "asks for state")
    #expect(ConsentText.clause(.configuration) == "changes a setting the device keeps")
    #expect(ConsentText.clause(.link) == "puts the device in or out of ALL-Linking mode, or adds an ALL-Link record")
    #expect(ConsentText.clause(.actuation) == "changes what the device does at once")
    #expect(ConsentText.clause(nil) == "no entry of the device's catalog describes")

  }

  @Test func saysWhatAControlCommandDoesntGrant() {

    let sentence: String = DeviceText.failure(.needsConsent(.turnOn, effect: .configuration, product: "Example Relay 9101"), device: Self.device)

    #expect(sentence == "The Insteon device catalog describes the command that would turn on Example Relay 9101 as one that changes a setting the device keeps, which this command doesn't grant. 'insteon device 3A.4B.01 send' sends it a message as given.")

  }

  @Test func saysWhatASettingWriteDoesntGrant() {

    let sentence: String = SettingsText.failure(.needsConsent(label: "Ramp rate", effect: .actuation), device: "3A.4B.01")

    #expect(sentence == "Writing Ramp rate sends a message that changes what the device does at once, which 'insteon device 3A.4B.01 set' doesn't grant, so nothing was changed.")

  }

}
