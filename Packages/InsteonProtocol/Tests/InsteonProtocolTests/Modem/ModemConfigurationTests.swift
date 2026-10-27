import Testing
import InsteonProtocol

struct ModemConfigurationTests {

  @Test func modemConfigurationUsesDocumentedBits() {

    #expect(ModemConfiguration.disableDeadman.rawValue == 0x10)
    #expect(ModemConfiguration.disableAutomaticLED.rawValue == 0x20)
    #expect(ModemConfiguration.monitorMode.rawValue == 0x40)
    #expect(ModemConfiguration.disableAutomaticLinking.rawValue == 0x80)

  }

}
