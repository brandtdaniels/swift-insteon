import Testing
import InsteonDeviceCatalog
import InsteonProtocol

/// A made-up catalog with an on/off plug and a keypad, whose models and identities no real
/// product has.
private enum MadeUp {

  static let load = GroupType(
    name: "load",
    label: "Load",
    kind: .relay,
    linkData: GroupType.LinkData(responder: [
      LinkDataByte(position: 2, name: "rampRate", label: "Ramp rate", summary: "The ramp rate."),
      LinkDataByte(position: 1, name: "onLevel", label: "On-level", summary: "The on-level.", table: "onOff"),
    ])
  )

  static let plugCommands = CommandSet(
    id: "madeUpPlug",
    name: "Made-Up Plug",
    summary: "A made-up command set.",
    groupTypes: [load],
    valueTables: [ValueTable(name: "onOff", entries: [.init(value: 0x00, label: "Off"), .init(value: 0xFF, label: "On")])]
  )

  static let plug = DeviceProfile(
    model: "9001",
    name: "Example Plug",
    aliases: ["ExampleLinc"],
    identities: [DeviceIdentity(category: 0x02, subcategory: 0x7A)],
    engines: [DeviceEngine(engine: .i2cs, category: 0x02, subcategory: 0x7A)],
    commandSets: [CommandSetEntry(commandSet: "madeUpPlug", category: 0x02, subcategory: 0x7A)],
    role: .responder,
    groups: [.init(number: 1, name: "Load", role: .responder, type: "load")]
  )

  // The keypad's light keeps the responder's own group in Data 3; its buttons keep what they
  // know of a responder in a controller record.
  static let light = GroupType(
    name: "light",
    label: "Light",
    kind: .dimmer,
    linkData: GroupType.LinkData(responder: [
      LinkDataByte(position: 1, name: "onLevel", label: "On-level", summary: "The on-level."),
      LinkDataByte(position: 3, name: "button", summary: "The responder's own group.", isPerGroup: true, verification: Verification(status: .inferred)),
    ])
  )

  static let button = GroupType(
    name: "button",
    label: "Button",
    kind: .button,
    linkData: GroupType.LinkData(
      responder: [LinkDataByte(position: 1, name: "ledLevel", label: "LED level", summary: "The LED's level.")],
      controller: [LinkDataByte(position: 3, name: "responderGroup", label: "Responder's group", summary: "The responder's group.")]
    )
  )

  static let keypadCommands = CommandSet(
    id: "madeUpKeypad",
    name: "Made-Up Keypad",
    summary: "A made-up command set.",
    groupTypes: [light, button]
  )

  static let keypad = DeviceProfile(
    model: "9002",
    name: "Example Keypad",
    identities: [DeviceIdentity(category: 0x01, subcategory: 0x7B)],
    commandSets: [CommandSetEntry(commandSet: "madeUpKeypad", category: 0x01, subcategory: 0x7B)],
    role: .both,
    groups: [
      .init(number: 1, name: "Light", role: .both, type: "light"),
      .init(number: 3, name: "Button C", role: .controller, type: "button"),
      .init(number: 4, name: "Button D", role: .responder),
    ]
  )

  // A remote whose profile says it controls but lists no groups.
  static let remote = DeviceProfile(
    model: "9003",
    name: "Example Remote",
    identities: [DeviceIdentity(category: 0x00, subcategory: 0x7C)],
    role: .controller
  )

  static let catalog = DeviceCatalog(profiles: [plug, keypad, remote], commandSets: [plugCommands, keypadCommands])

}

struct DeviceDescriptionTests {

  let other = InsteonAddress(0x4D, 0x5E, 0x6F)

  @Test func looksADeviceUpInTheCatalog() {

    let device: DeviceDescription = MadeUp.catalog.describe(category: 0x02, subcategory: 0x7A, firmwareVersion: 0x41)

    #expect(device.profile?.model == "9001")
    #expect(device.commandSet?.id == "madeUpPlug")
    #expect(device.displayName == "Example Plug 9001 (ExampleLinc)")
    #expect(device.engine == .i2cs)
    #expect(device.mainGroup?.number == 1)
    #expect(device.mainGroupType?.kind == .relay)
    #expect(device.groupType(forGroup: 1)?.name == "load")
    #expect(device.groupType(forGroup: 2) == nil)
    #expect(device.responderGroupType(forRecordData: [0xFF, 0x1F, 0x01])?.name == "load")
    #expect(device.controllerGroups.isEmpty)

    let unknown: DeviceDescription = MadeUp.catalog.describe(category: 0x07, subcategory: 0x00, firmwareVersion: nil)

    #expect(unknown.profile == nil)
    #expect(unknown.displayName == nil)
    #expect(unknown.engine == nil)
    #expect(unknown.mainGroup == nil)
    #expect(unknown.mainGroupType == nil)
    #expect(unknown.controllerGroups.isEmpty)

    // Without the catalog, the device is described by its identity alone.
    let alone = DeviceDescription(category: 0x02, subcategory: 0x7A, firmwareVersion: 0x41, catalog: nil)

    #expect(alone.category == 0x02)
    #expect(alone.firmwareVersion == 0x41)
    #expect(alone.displayName == nil)
    #expect(alone.mainGroupType == nil)

  }

  @Test func findsTheGroupsADeviceControls() {

    let keypad: DeviceDescription = MadeUp.catalog.describe(category: 0x01, subcategory: 0x7B, firmwareVersion: nil)
    let numbers: [AllLinkGroupNumber] = keypad.controllerGroups.map(\.number)

    #expect(numbers == [1, 3])
    #expect(keypad.displayName == "Example Keypad 9002")

    // The remote's product controls, though it lists no groups.
    let remote: DeviceDescription = MadeUp.catalog.describe(category: 0x00, subcategory: 0x7C, firmwareVersion: nil)

    #expect(remote.controllerGroups.isEmpty)
    #expect(remote.profile?.role?.includesController == true)
    #expect(DeviceProfile.LinkRole.responder.includesController == false)

  }

  @Test func explainsARecordsDataWithTheGroupType() throws {

    let device: DeviceDescription = MadeUp.catalog.describe(category: 0x02, subcategory: 0x7A, firmwareVersion: 0x41)
    let record = AllLinkRecord(flags: [.inUse], group: 0, address: other, data1: 0xFF, data2: 0x1F, data3: 0x01)
    let explanation = try #require(device.explain(record, isController: false))

    #expect(explanation.groupType.name == "load")
    #expect(explanation.bytes.map(\.position) == [1, 2])
    #expect(explanation.bytes[0] == RecordDataExplanation.DataByte(
      position: 1,
      name: "onLevel",
      label: "On-level",
      value: 0xFF,
      tableEntry: ValueTable.Entry(value: 0xFF, label: "On")
    ))
    #expect(explanation.bytes[1].label == "Ramp rate")
    #expect(explanation.bytes[1].value == 0x1F)
    #expect(explanation.bytes[1].tableEntry == nil)

    // The plug's type says nothing of a controller record's bytes.
    #expect(device.explain(record, isController: true) == nil)

    // Without a profile, nothing explains the record.
    let unknown: DeviceDescription = MadeUp.catalog.describe(category: 0x07, subcategory: 0x00, firmwareVersion: nil)

    #expect(unknown.explain(record, isController: false) == nil)

  }

  @Test func readsTheRespondersOwnGroupFromAPerGroupByte() throws {

    let keypad: DeviceDescription = MadeUp.catalog.describe(category: 0x01, subcategory: 0x7B, firmwareVersion: nil)

    // Data 3 names button C, group 3, so its type explains the record.
    let toButton = AllLinkRecord(flags: [.inUse], group: 5, address: other, data1: 0x7F, data2: 0x00, data3: 0x03)
    let button = try #require(keypad.explain(toButton, isController: false))

    #expect(button.groupType.name == "button")
    #expect(button.bytes.map(\.name) == ["ledLevel"])

    // Data 3 names the light, group 1, whose per-group byte is explained as such.
    let toLight = AllLinkRecord(flags: [.inUse], group: 5, address: other, data1: 0xFF, data2: 0x00, data3: 0x01)
    let light = try #require(keypad.explain(toLight, isController: false))

    #expect(light.groupType.name == "light")
    #expect(light.bytes.count == 2)
    #expect(light.bytes[1].isPerGroup)
    #expect(light.bytes[1].value == 0x01)
    #expect(light.bytes[1].verification.status == .inferred)

    // A group with no type, or none at all, falls back on the main group's type.
    let toUntyped = AllLinkRecord(flags: [.inUse], group: 5, address: other, data1: 0xFF, data2: 0x00, data3: 0x04)

    #expect(keypad.responderGroupType(forRecordData: [0xFF, 0x00, 0x04])?.name == "light")
    #expect(keypad.explain(toUntyped, isController: false)?.groupType.name == "light")

    // A controller record's group is the keypad's own.
    let fromButton = AllLinkRecord(flags: [.inUse, .controller], group: 3, address: other, data1: 0x00, data2: 0x00, data3: 0x01)
    let controller = try #require(keypad.explain(fromButton, isController: true))

    #expect(controller.groupType.name == "button")
    #expect(controller.bytes.map(\.position) == [3])

  }

  @Test func fallsBackOnTheCategoryForAKind() {

    #expect(GroupType.Kind.fallback(for: .dimmableLightingControl) == .dimmer)
    #expect(GroupType.Kind.fallback(for: 0x01) == .dimmer)
    #expect(GroupType.Kind.fallback(for: 0x02) == .relay)
    #expect(GroupType.Kind.fallback(for: 0x07) == nil)
    #expect(GroupType.Kind.fallback(for: 0x00) == nil)

  }

}
