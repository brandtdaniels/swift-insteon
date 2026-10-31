import Testing
@testable import InsteonCore
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// A modem's scenes, and a device's product data, on an in-memory modem.
struct ModemSceneTests {

  @Test(.timeLimit(.minutes(1))) func listsTheGroupsRespondersFromTheModemsControllerRecords() async throws {

    let modem = InMemoryModem()
    let controller = AllLinkRecordFlags(rawValue: 0xE2)
    let responder = AllLinkRecordFlags(rawValue: 0xA2)

    await modem.setModemRecords([
      AllLinkRecord(flags: controller, group: 0x01, address: Example.lamp),
      AllLinkRecord(flags: controller, group: 0x01, address: Example.plug),
      AllLinkRecord(flags: controller, group: 0x01, address: Example.lamp),
      AllLinkRecord(flags: controller, group: 0x02, address: Example.sensor),
      AllLinkRecord(flags: responder, group: 0x01, address: Example.sensor)
    ])

    let responders: [InsteonAddress] = try await ModemScene(group: 0x01).responders(in: modem)

    #expect(responders == [Example.plug, Example.lamp].sorted { $0.description < $1.description })

  }

  @Test func waitsLongerForMoreResponders() {

    #expect(ModemScene.cleanupTimeout(responderCount: 0) == .seconds(10))
    #expect(ModemScene.cleanupTimeout(responderCount: 3) == .seconds(10))
    #expect(ModemScene.cleanupTimeout(responderCount: 5) == .seconds(13))

  }

  @Test func takesAProductKeyOfZerosAsNone() {

    let zeros = ProductData(sender: Example.plug, productKey: ProductKey(0, 0, 0), category: 0x02, subcategory: 0x7A, userDefined: [])
    let reported = ProductData(sender: Example.plug, productKey: ProductKey(0x00, 0x10, 0x2A), category: 0x02, subcategory: 0x7A, userDefined: [])

    #expect(DeviceProductData(zeros).productKey == nil)
    #expect(DeviceProductData(reported).productKey == ProductKey(0x00, 0x10, 0x2A))
    #expect(DeviceProductData(reported).category == 0x02)

  }

  @Test(.timeLimit(.minutes(1))) func givesNoProductDataForADeviceThatDoesntAnswer() async throws {

    let modem = InMemoryModem()

    await modem.setUnanswering(Example.plug)

    let network = DeviceNetwork(modem: modem, catalog: nil, clock: TestClock())

    #expect(try await network.productData(of: Example.plug) == nil)

  }

}
