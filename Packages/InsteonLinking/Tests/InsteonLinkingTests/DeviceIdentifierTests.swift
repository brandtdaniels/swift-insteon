import Testing
import InsteonLinking
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// Identifying devices, on a ``TestClock`` that moves only when a test advances it.
struct DeviceIdentifierTests {

  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)

  let clock = TestClock()

  var identity: SetButtonPressed {

    SetButtonPressed(sender: lamp, role: .responder, category: 0x01, subcategory: 0x19, firmwareVersion: 0x41)

  }

  func identifier(_ modem: InMemoryModem) -> DeviceIdentifier {

    DeviceIdentifier(modem: modem, clock: clock)

  }

  @Test func asksForTheEngineThenTheIdentity() async throws {

    let modem = InMemoryModem()
    await modem.setEngine(.i2cs, of: lamp)
    await modem.setIdentity(identity)

    let identification = try await identifier(modem).identify(lamp)

    #expect(identification == DeviceIdentification(device: lamp, engine: .i2cs, acceptsModem: true, identity: identity))
    #expect(await modem.linkingSteps == [.device(lamp, Command(command1: 0x0D), isExtended: false)])

  }

  // An i2CS device rejects a modem it isn't linked to, so it can't be asked for its identity.
  @Test func identifiesADeviceThatRejectsTheModemAsI2cs() async throws {

    let modem = InMemoryModem()
    await modem.setUnlinked(lamp)
    await modem.setIdentity(identity)

    let identification = try await identifier(modem).identify(lamp)

    #expect(identification == DeviceIdentification(device: lamp, engine: .i2cs, acceptsModem: false, identity: nil))

  }

  @Test func reportsAnEngineItDoesntKnowAsNil() async throws {

    let modem = InMemoryModem()
    await modem.setUnknownEngine(0x03, of: lamp)
    await modem.setIdentity(identity)

    let identification = try await identifier(modem).identify(lamp)

    #expect(identification.engine == nil)
    #expect(identification.identity == identity)

  }

  @Test func returnsNoIdentityWhenNoBroadcastArrives() async throws {

    let modem = InMemoryModem()

    async let identification = identifier(modem).identify(lamp)
    await clock.waitForSleeper(until: Modem.defaultRequestTimeout)
    clock.advance(by: Modem.defaultRequestTimeout)

    #expect(try await identification == DeviceIdentification(device: lamp, engine: .i2, acceptsModem: true, identity: nil))

  }

  @Test func ignoresAnotherDevicesBroadcast() async throws {

    let modem = InMemoryModem()
    let other = InsteonAddress(0x44, 0x55, 0x66)
    await modem.setIdentity(SetButtonPressed(sender: other, role: .controller, category: 0x10, subcategory: 0x01, firmwareVersion: nil))

    // The lamp doesn't answer its ID request at once: another device's broadcast arrives
    // first, then the lamp's, so the identity can only be the lamp's if the other is skipped.
    async let identification = identifier(modem).identify(lamp)
    await clock.waitForSleeper(until: Modem.defaultRequestTimeout)
    await modem.broadcastIdentity(of: other)
    await modem.setIdentity(identity)
    await modem.broadcastIdentity(of: lamp)

    #expect((try await identification).identity == identity)

  }

}
