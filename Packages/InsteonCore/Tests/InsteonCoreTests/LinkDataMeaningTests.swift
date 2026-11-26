import Testing
import InsteonDeviceCatalog
import InsteonProtocol
@testable import InsteonCore

/// What a scene member's link data bytes mean, from a made-up catalog whose models and identities no
/// real product has.
struct LinkDataMeaningTests {

  private enum MadeUp {

    static let load = GroupType(
      name: "load",
      label: "Load",
      kind: .dimmer,
      linkData: GroupType.LinkData(responder: [
        LinkDataByte(position: 1, name: "onLevel", label: "On-level", summary: "The on-level.", table: "level", verification: Verification(status: .observed)),
        LinkDataByte(position: 2, name: "rampRate", label: "Ramp rate", summary: "The ramp rate."),
        LinkDataByte(position: 3, name: "group", summary: "The responder's own group.", isPerGroup: false, verification: Verification(status: .inferred))
      ])
    )

    static let commands = CommandSet(
      id: "madeUpDimmer",
      name: "Made-Up Dimmer",
      summary: "A made-up command set.",
      groupTypes: [load],
      valueTables: [ValueTable(name: "level", entries: [.init(value: 0x00, label: "Off"), .init(value: 0xFF, label: "On")])]
    )

    static let profile = DeviceProfile(
      model: "9001",
      name: "Example Dimmer",
      identities: [DeviceIdentity(category: 0x01, subcategory: 0x7A)],
      commandSets: [CommandSetEntry(commandSet: "madeUpDimmer", category: 0x01, subcategory: 0x7A)],
      role: .responder,
      groups: [.init(number: 1, name: "Load", role: .responder, type: "load")]
    )

    static let catalog = DeviceCatalog(profiles: [profile], commandSets: [commands])

  }

  private func info(category: UInt8 = 0x01, subcategory: UInt8 = 0x7A) -> DeviceInfo {

    DeviceInfo(MadeUp.catalog.describe(category: DeviceCategory(rawValue: category), subcategory: DeviceSubcategory(rawValue: subcategory), firmwareVersion: 0x41))

  }

  @Test func namesTheBytesOfAResponderRecordWithTheCatalogsLabelsAndValueNames() throws {

    let meaning = try #require(info().meaning(ofResponderData: [0xFF, 0x1F, 0x01], group: 3))

    #expect(meaning.bytes.map(\.position) == [1, 2, 3])
    #expect(meaning.bytes[0].name == "onLevel")
    #expect(meaning.bytes[0].label == "On-level")
    #expect(meaning.bytes[0].value == 0xFF)
    #expect(meaning.bytes[0].valueName == "On")
    #expect(meaning.bytes[1].label == "Ramp rate")
    #expect(meaning.bytes[1].valueName == nil)

  }

  @Test func saysHowSureTheCatalogIsOfEachByte() throws {

    let meaning = try #require(info().meaning(ofResponderData: [0xFF, 0x1F, 0x01], group: 3))

    #expect(meaning.bytes.map(\.verification) == ["observed", "documented", "inferred"])

  }

  @Test func hasNoMeaningForADeviceTheCatalogDoesNotDescribe() {

    #expect(info(category: 0x0F, subcategory: 0x0F).meaning(ofResponderData: [0xFF, 0x1F, 0x01], group: 3) == nil)

  }

  @Test func hasNoMeaningForDataThatIsNotThreeBytes() {

    #expect(info().meaning(ofResponderData: [0xFF], group: 3) == nil)
    #expect(info().meaning(ofResponderData: [], group: 3) == nil)

  }

}
