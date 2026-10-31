import Testing
@testable import InsteonCore
import InsteonDeviceCatalog
import InsteonProtocol

/// Made-up products and addresses for the tests.
enum Example {

  static let plug = InsteonAddress(0x1A, 0x2B, 0x3C)

  static let lamp = InsteonAddress(0x4D, 0x5E, 0x6F)

  static let sensor = InsteonAddress(0x0A, 0x0B, 0x0C)

  static let plugIdentity = ReportedIdentity(category: 0x02, subcategory: 0x7A, firmwareVersion: 0x41)

  static let lampIdentity = ReportedIdentity(category: 0x01, subcategory: 0x7B, firmwareVersion: nil)

  static let plugProfile = DeviceProfile(
    model: "9001",
    name: "Example Plug",
    identities: [DeviceIdentity(category: 0x02, subcategory: 0x7A)]
  )

  static let renamedPlugProfile = DeviceProfile(
    model: "9002",
    name: "Example Outlet",
    identities: [DeviceIdentity(category: 0x02, subcategory: 0x7A)]
  )

  static let lampProfile = DeviceProfile(
    model: "9003",
    name: "Example Lamp",
    identities: [DeviceIdentity(category: 0x01, subcategory: 0x7B)]
  )

  static let catalog = DeviceCatalog(profiles: [plugProfile])

}

@Suite(.timeLimit(.minutes(1)))
struct DeviceRegistryTests {

  @Test func recordsADeviceAndDescribesItWithTheCatalog() async {

    let registry = DeviceRegistry(catalog: Example.catalog)

    let recorded: RegisteredDevice = await registry.record(Example.plugIdentity, for: Example.plug)
    let found: RegisteredDevice? = await registry.device(Example.plug)

    #expect(recorded == found)
    #expect(found?.address == Example.plug)
    #expect(found?.identity == Example.plugIdentity)
    #expect(found?.deviceDescription.profile == Example.plugProfile)
    #expect(found?.deviceDescription.displayName == "Example Plug 9001")

  }

  @Test func describesADeviceTheCatalogDoesntHaveByItsIdentity() async {

    let registry = DeviceRegistry(catalog: Example.catalog)

    await registry.record(Example.lampIdentity, for: Example.lamp)

    let found: RegisteredDevice? = await registry.device(Example.lamp)

    #expect(found?.identity == Example.lampIdentity)
    #expect(found?.deviceDescription.profile == nil)
    #expect(found?.deviceDescription.category == 0x01)
    #expect(found?.deviceDescription.subcategory == 0x7B)

  }

  @Test func describesDevicesWithoutACatalog() async {

    let registry = DeviceRegistry(catalog: nil)

    await registry.record(Example.plugIdentity, for: Example.plug)

    let found: RegisteredDevice? = await registry.device(Example.plug)

    #expect(found?.identity == Example.plugIdentity)
    #expect(found?.deviceDescription.profile == nil)

  }

  @Test func looksUpOnlyRecordedDevices() async {

    let registry = DeviceRegistry(catalog: Example.catalog)

    await registry.record(Example.plugIdentity, for: Example.plug)

    #expect(await registry.device(Example.lamp) == nil)

  }

  @Test func replacesAnIdentityRecordedBefore() async {

    let registry = DeviceRegistry(catalog: Example.catalog)
    let updated = ReportedIdentity(category: 0x02, subcategory: 0x7A, firmwareVersion: 0x45)

    await registry.record(Example.plugIdentity, for: Example.plug)
    await registry.record(updated, for: Example.plug)

    #expect(await registry.device(Example.plug)?.identity == updated)
    #expect(await registry.devices.count == 1)

  }

  @Test func listsDevicesInAddressOrder() async {

    let registry = DeviceRegistry(catalog: Example.catalog)

    await registry.record(Example.lampIdentity, for: Example.lamp)
    await registry.record(Example.plugIdentity, for: Example.plug)
    await registry.record(Example.plugIdentity, for: Example.sensor)

    let addresses: [InsteonAddress] = await registry.devices.map(\.address)

    #expect(addresses == [Example.sensor, Example.plug, Example.lamp])

  }

  @Test func forgetsADevice() async {

    let registry = DeviceRegistry(catalog: Example.catalog)

    await registry.record(Example.plugIdentity, for: Example.plug)
    await registry.record(Example.lampIdentity, for: Example.lamp)

    let forgotten: RegisteredDevice? = await registry.forget(Example.plug)

    #expect(forgotten?.identity == Example.plugIdentity)
    #expect(await registry.device(Example.plug) == nil)
    #expect(await registry.devices.map(\.address) == [Example.lamp])
    #expect(await registry.forget(Example.plug) == nil)

  }

  @Test func describesEveryDeviceAgainWithAnotherCatalog() async {

    let registry = DeviceRegistry(catalog: Example.catalog)

    await registry.record(Example.plugIdentity, for: Example.plug)
    await registry.record(Example.lampIdentity, for: Example.lamp)

    let newer = DeviceCatalog(profiles: [Example.renamedPlugProfile, Example.lampProfile])

    await registry.setCatalog(newer)

    #expect(await registry.catalog == newer)
    #expect(await registry.device(Example.plug)?.deviceDescription.displayName == "Example Outlet 9002")
    #expect(await registry.device(Example.lamp)?.deviceDescription.displayName == "Example Lamp 9003")

    // A catalog without the identity keeps the device, with no profile.
    await registry.setCatalog(DeviceCatalog(profiles: []))

    #expect(await registry.device(Example.plug)?.identity == Example.plugIdentity)
    #expect(await registry.device(Example.plug)?.deviceDescription.profile == nil)

  }

  @Test func restoresItsDevicesFromASnapshot() async {

    let registry = DeviceRegistry(catalog: Example.catalog)

    await registry.record(Example.plugIdentity, for: Example.plug)
    await registry.record(Example.lampIdentity, for: Example.lamp)

    let snapshot: DeviceRegistrySnapshot = await registry.snapshot

    #expect(snapshot == DeviceRegistrySnapshot(identities: [Example.plug: Example.plugIdentity, Example.lamp: Example.lampIdentity]))

    let restored = DeviceRegistry(catalog: Example.catalog, snapshot: snapshot)

    #expect(await restored.devices == registry.devices)
    #expect(await restored.device(Example.plug)?.deviceDescription.profile == Example.plugProfile)

  }

  @Test func startsEmpty() async {

    let registry = DeviceRegistry(catalog: Example.catalog)

    #expect(await registry.devices.isEmpty)
    #expect(await registry.snapshot.isEmpty)

  }

}
