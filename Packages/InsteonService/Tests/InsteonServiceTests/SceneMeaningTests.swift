import Foundation
import InsteonCore
import InsteonDeviceCatalog
import InsteonLinkingTestSupport
import InsteonProtocol
import Testing
@testable import InsteonService

/// What a scene member's link data bytes mean to the service: the catalog's words for the identity it
/// has recorded for the device, from a made-up catalog.
@Suite(.timeLimit(.minutes(1)))
struct SceneMeaningTests {

  let device = InsteonAddress(0x1A, 0x2B, 0x3C)
  let stranger = InsteonAddress(0x4D, 0x5E, 0x6F)

  private static let catalog: DeviceCatalog = {

    let load = GroupType(
      name: "load",
      label: "Load",
      kind: .dimmer,
      linkData: GroupType.LinkData(responder: [
        LinkDataByte(position: 1, name: "onLevel", label: "On-level", summary: "The on-level.", verification: Verification(status: .observed))
      ])
    )
    let commands = CommandSet(id: "madeUpDimmer", name: "Made-Up Dimmer", summary: "A made-up command set.", groupTypes: [load])
    let profile = DeviceProfile(
      model: "9001",
      name: "Example Dimmer",
      identities: [DeviceIdentity(category: 0x01, subcategory: 0x7D)],
      commandSets: [CommandSetEntry(commandSet: "madeUpDimmer", category: 0x01, subcategory: 0x7D)],
      role: .responder,
      groups: [.init(number: 1, name: "Load", role: .responder, type: "load")]
    )

    return DeviceCatalog(profiles: [profile], commandSets: [commands])

  }()

  private func service(catalog: DeviceCatalog?) -> InsteonService {

    let identity = ReportedIdentity(category: 0x01, subcategory: 0x7D, firmwareVersion: 0x45)
    let network = DeviceNetwork(modem: InMemoryModem(), catalog: catalog, snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [device: identity])), now: { Date(timeIntervalSince1970: 1_800_000_000) })

    return InsteonService(network: network)

  }

  @Test func namesTheBytesFromTheCatalogForTheIdentityTheServiceRecorded() async throws {

    let meaning = try #require(await service(catalog: Self.catalog).meaning(ofMemberData: [0xFF, 0x1F, 0x01], of: device, group: 3))

    #expect(meaning.bytes.map(\.name) == ["onLevel"])
    #expect(meaning.bytes.first?.verification == "observed")

  }

  @Test func hasNoMeaningForADeviceWithNoRecordedIdentity() async {

    #expect(await service(catalog: Self.catalog).meaning(ofMemberData: [0xFF, 0x1F, 0x01], of: stranger, group: 3) == nil)

  }

  @Test func hasNoMeaningWhenThereIsNoCatalog() async {

    #expect(await service(catalog: nil).meaning(ofMemberData: [0xFF, 0x1F, 0x01], of: device, group: 3) == nil)

  }

  @Test func sendsNothingToTheModemToNameABytesMeaning() async {

    let modem = InMemoryModem()
    let network = DeviceNetwork(modem: modem, catalog: Self.catalog, snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [device: ReportedIdentity(category: 0x01, subcategory: 0x7D, firmwareVersion: 0x45)])), now: { Date(timeIntervalSince1970: 1_800_000_000) })

    _ = await InsteonService(network: network).meaning(ofMemberData: [0xFF, 0x1F, 0x01], of: device, group: 3)

    #expect(await modem.writes.isEmpty)
    #expect(await modem.linkingSteps.isEmpty)
    #expect(await modem.modemDatabaseReads == 0)

  }

}
