import Foundation
import Testing
import InsteonDeviceCatalog
import InsteonProtocol

/// The fields the catalog's format gives for linking to a Hub, product keys, a modem's record
/// data, group types' state patterns, outputs and arm modes, and the guards on flags and
/// commands, read from small made-up fixtures.
struct HubLinkingAndGuardTests {

  static let sensor = #"""
    {
      "model": "1",
      "name": "Test Sensor",
      "identities": [
        { "category": "0x10", "subcategory": "0x01", "productKey": "0x00001A" },
        { "category": "0x10", "subcategory": "0x02", "productKey": "none",
          "verification": { "status": "inferred", "note": "Read from a similar product." },
          "productKeyVerification": { "status": "conflicting", "note": "Two lists differ." } },
        { "category": "0x10", "subcategory": "0x03", "productKey": "0x00001a" }
      ],
      "batteryPowered": true,
      "groups": [
        { "number": "0x01", "name": "Open", "role": "controller" },
        { "number": "0x02", "name": "Closed", "role": "controller" }
      ],
      "capabilities": [],
      "lifecycle": {
        "fromHub": {
          "legs": [
            { "modem": "responder", "modemGroup": "0x01", "deviceGroup": "0x01",
              "allGroupsWhen": { "flag": "linkToAllGroups", "set": true } },
            { "modem": "responder", "modemGroup": "0x02", "deviceGroup": "0x02",
              "verification": { "status": "observed", "note": "Seen on a device.", "firmware": ["0x41"] } }
          ],
          "deviceFirst": true,
          "remoteEnterLinkingMode": { "works": "no", "verification": { "status": "documented", "note": "Its notes say so." } },
          "keepAwake": {
            "when": "afterLinked",
            "send": { "command": "stayAwake" },
            "release": { "flag": "stayAwake", "set": false },
            "seconds": 240,
            "verification": { "status": "inferred", "note": "Assembled from its steps." }
          },
          "verification": { "status": "inferred", "note": "No document describes adding it to a Hub." }
        }
      },
      "sources": ["A"]
    }
    """#

  static let modem = #"""
    {
      "model": "2",
      "name": "Test Modem",
      "identities": [{ "category": "0x03", "subcategory": "0x33" }],
      "capabilities": [
        { "kind": "modem", "linkData": {
          "controller": [
            { "byte": 1, "name": "data1", "description": "Always 0x01.", "value": "0x01" },
            { "byte": 2, "name": "subcategory", "description": "The responder's subcategory.", "identity": "subcategory",
              "verification": { "status": "observed", "note": "Seen on a modem.", "firmware": ["0xA5"] } },
            { "byte": 3, "name": "firmware", "description": "The responder's firmware version.", "identity": "firmware" }
          ],
          "responder": [
            { "byte": 1, "name": "newer", "description": "Something newer.", "identity": "somethingNewer" }
          ]
        } }
      ],
      "lifecycle": {
        "fromHub": {
          "legs": [{ "modem": "controller", "modemGroup": "0x00", "deviceGroup": "0x01" }],
          "deviceFirst": false,
          "remoteEnterLinkingMode": { "works": "yes" },
          "keepAwake": {
            "when": "beforeLinking",
            "send": { "command1": "0x20", "command2": "0x06", "extended": true, "integrity": "checksum",
                      "data": [{ "position": 1, "value": "0x01" }] },
            "release": { "somethingNewer": true }
          }
        }
      },
      "sources": ["A"]
    }
    """#

  static let commandSet = #"""
    {
      "id": "testGuarded",
      "name": "Test Guarded",
      "description": "A made-up command set with guards.",
      "operatingFlags": [
        { "name": "programmingLock", "description": "Locked.", "query": "0x00", "bit": "0x01", "on": "0x00", "off": "0x01", "guard": "neverSet" },
        { "name": "radioOff", "description": "Radio off.", "query": "0x00", "bit": "0x40", "on": "0x0C", "off": "0x0D", "guard": "keep" },
        { "name": "beep", "description": "Beeps.", "query": "0x00", "bit": "0x02", "on": "0x04", "off": "0x05" },
        { "name": "newer", "description": "Newer.", "query": "0x00", "bit": "0x08", "guard": "somethingNewer" },
        { "name": "other", "description": "Another query's.", "query": "0x05", "bit": "0x01" }
      ],
      "flagCommands": [
        { "name": "radioOffAgain", "description": "Turns the radio off.", "command2": "0x0C", "guard": "never" },
        { "name": "reset", "description": "Something harmless.", "command2": "0x30" }
      ],
      "standardCommands": [
        { "name": "lockOn", "description": "Locks.", "command1": "0x20", "command2": "0x00", "guard": "never" },
        { "name": "lightOn", "description": "On.", "command1": "0x11", "command2": "0xFF" }
      ],
      "extendedCommands": [
        { "name": "lockOnExtended", "description": "Locks.", "command1": "0x20", "command2": "0x00", "integrity": "checksum", "guard": "never" },
        { "name": "writeProperties", "description": "Writes flags.", "command1": "0x2E", "command2": "0x00",
          "parameters": [{ "name": "flags", "description": "The flags.", "byte": 3, "kind": "flags",
            "bits": [
              { "mask": "0x01", "name": "programmingLock", "guard": "neverSet" },
              { "mask": "0x40", "name": "radioOff", "guard": "keep" },
              { "mask": "0x02", "name": "beep" }
            ] }] }
      ],
      "extendedSettings": {
        "perButton": false,
        "values": [
          { "name": "configuration", "description": "The operating flags byte.", "byte": 3, "flagsQuery": "0x00" },
          { "name": "level", "description": "A level.", "byte": 4 }
        ]
      },
      "linkingChanges": [
        { "flag": "beep" },
        { "flag": "other", "verification": { "status": "observed", "note": "Seen on a device.", "firmware": ["0x41"] } }
      ],
      "groupTypes": [
        { "name": "zone2", "label": "Zone 2", "kind": "relay",
          "state": { "command": "readValveStatus", "onWhen": { "mask": "0x87", "value": "0x81",
            "verification": { "status": "inferred", "note": "Read from the status byte." } } } },
        { "name": "light", "label": "Light", "kind": "dimmer",
          "outputs": {
            "activeWhen": { "flag": "relayMode", "set": true },
            "bits": [
              { "mask": "0x01", "name": "relay1", "label": "Relay 1" },
              { "mask": "0x02", "name": "relay2", "label": "Relay 2" }
            ],
            "verification": { "status": "documented", "note": "Its notes say so." }
          } },
        { "name": "soundAway", "label": "Sound when armed away", "kind": "alarm", "armModes": ["away", "somethingNewer"] },
        { "name": "armAll", "label": "Arm", "kind": "arming", "armModes": ["home", "away"] },
        { "name": "blind", "label": "Blind", "kind": "windowCovering" }
      ],
      "sources": ["A"]
    }
    """#

  static func catalog(devices: [String] = [sensor, modem], commandSets: [String] = [commandSet]) throws -> DeviceCatalog {

    let json: String = #"{ "devices": [\#(devices.joined(separator: ","))], "commandSets": [\#(commandSets.joined(separator: ","))] }"#

    return try DeviceCatalog(json: Data(json.utf8))

  }

  static func commands() throws -> CommandSet {

    try #require(try catalog().commandSet(id: "testGuarded"))

  }

  // MARK: - Identities

  @Test func readsProductKeys() throws {

    let identities: [DeviceIdentity] = try #require(try Self.catalog().profile(model: "1")).identities

    #expect(identities[0].productKey == .key(ProductKey(0x00, 0x00, 0x1A)))
    #expect(identities[0].productKey?.productKey == ProductKey(0x00, 0x00, 0x1A))
    #expect(identities[0].productKeyVerification == nil)
    #expect(identities[1].productKey == .notReported)
    #expect(identities[1].productKey?.productKey == nil)
    #expect(identities[1].productKeyVerification == Verification(status: .conflicting, note: "Two lists differ."))
    // A key written another way is passed over rather than failing the catalog.
    #expect(identities[2].productKey == nil)

  }

  // MARK: - Linking from a Hub

  @Test func readsTheLegsOfLinkingFromAHub() throws {

    let fromHub = try #require(try Self.catalog().profile(model: "1")?.lifecycle?.fromHub)
    let inferred = Verification(status: .inferred, note: "No document describes adding it to a Hub.")

    #expect(fromHub.isDeviceFirst)
    #expect(fromHub.verification == inferred)
    #expect(fromHub.legs == [
      // A leg without a verification of its own takes the whole's.
      DeviceLifecycle.HubLinking.Leg(
        modemRole: .responder,
        modemGroup: 1,
        deviceGroup: 1,
        allGroupsWhen: DeviceProfile.Group.Condition(flag: "linkToAllGroups", isSet: true),
        verification: inferred
      ),
      DeviceLifecycle.HubLinking.Leg(
        modemRole: .responder,
        modemGroup: 2,
        deviceGroup: 2,
        verification: Verification(status: .observed, note: "Seen on a device.", firmware: [0x41])
      )
    ])
    #expect(fromHub.remoteEnterLinkingMode == DeviceLifecycle.HubLinking.RemoteEnterLinkingMode(works: .no, verification: Verification(status: .documented, note: "Its notes say so.")))

  }

  @Test func readsAKeepAwakeByCommandAndByFlag() throws {

    let keepAwake = try #require(try Self.catalog().profile(model: "1")?.lifecycle?.fromHub?.keepAwake)

    #expect(keepAwake.timing == .afterLinked)
    #expect(keepAwake.send == .command("stayAwake"))
    #expect(keepAwake.release == .flag(DeviceProfile.Group.Condition(flag: "stayAwake", isSet: false)))
    #expect(keepAwake.duration == .seconds(240))
    #expect(keepAwake.verification == Verification(status: .inferred, note: "Assembled from its steps."))

  }

  @Test func readsAKeepAwakeByItsBytes() throws {

    let fromHub = try #require(try Self.catalog().profile(model: "2")?.lifecycle?.fromHub)
    let keepAwake = try #require(fromHub.keepAwake)

    #expect(fromHub.isDeviceFirst == false)
    #expect(fromHub.remoteEnterLinkingMode?.works == .yes)
    #expect(fromHub.legs.map(\.modemRole) == [.controller])
    #expect(fromHub.legs.map(\.verification) == [.documented])
    #expect(keepAwake.timing == .beforeLinking)
    #expect(keepAwake.send == .bytes(DeviceLifecycle.HubLinking.RawMessage(
      command: Command(command1: 0x20, command2: 0x06),
      isExtended: true,
      fixedBytes: [FixedUserDataByte(position: 1, value: 0x01)],
      integrity: .checksum
    )))
    // A release in a form this package doesn't read is left out.
    #expect(keepAwake.release == nil)
    #expect(keepAwake.duration == nil)

  }

  @Test func passesOverLinkingValuesFromALaterVersion() throws {

    let profile = #"""
      {
        "model": "3",
        "name": "Newer",
        "identities": [{ "category": "0x01", "subcategory": "0x01" }],
        "capabilities": [],
        "lifecycle": { "fromHub": {
          "legs": [{ "modem": "somethingNewer", "modemGroup": "0x01", "deviceGroup": "0x01" }],
          "deviceFirst": false,
          "remoteEnterLinkingMode": { "works": "somethingNewer" },
          "keepAwake": { "when": "somethingNewer", "send": { "somethingNewer": "0x01" } }
        } },
        "sources": ["A"]
      }
      """#

    let fromHub = try #require(try Self.catalog(devices: [profile], commandSets: []).profiles.first?.lifecycle?.fromHub)

    #expect(fromHub.legs.map(\.modemRole) == [DeviceLifecycle.HubLinking.Role(rawValue: "somethingNewer")])
    #expect(fromHub.remoteEnterLinkingMode?.works == DeviceLifecycle.HubLinking.Answer(rawValue: "somethingNewer"))
    // A keep-awake whose message isn't in a form this package reads is left out.
    #expect(fromHub.keepAwake == nil)

  }

  @Test func readsAProfileWithoutTheNewerFields() throws {

    let profile = try #require(try DeviceCatalog(json: DeviceCatalogTests.json(DeviceCatalogTests.leakSensor)).profiles.first)

    #expect(profile.lifecycle?.fromHub == nil)
    #expect(profile.modemLinkData == nil)
    #expect(profile.identities.allSatisfy { $0.productKey == nil && $0.productKeyVerification == nil })

  }

  // MARK: - A modem's record data

  @Test func readsAModemsRecordData() throws {

    let linkData = try #require(try Self.catalog().profile(model: "2")?.modemLinkData)

    #expect(linkData.controller.map(\.position) == [1, 2, 3])
    #expect(linkData.controller.map(\.value) == [0x01, nil, nil])
    #expect(linkData.controller.map(\.identity) == [nil, .subcategory, .firmware])
    #expect(linkData.controller[1].verification == Verification(status: .observed, note: "Seen on a modem.", firmware: [0xA5]))
    #expect(linkData.controller.map { $0.byte(category: 0x02, subcategory: 0x38, firmwareVersion: 0x42) } == [0x01, 0x38, 0x42])
    // An identity byte from a later version keeps its name, and gives no value.
    #expect(linkData.responder.first?.identity == ModemLinkDataByte.IdentityByte(rawValue: "somethingNewer"))
    #expect(linkData.responder.first?.byte(category: 0x02, subcategory: 0x38, firmwareVersion: 0x42) == nil)

  }

  // MARK: - Describing a device

  @Test func describesADevicesLinkingProductKeyAndModemData() throws {

    let catalog: DeviceCatalog = try Self.catalog()
    let sensor: DeviceDescription = catalog.describe(category: 0x10, subcategory: 0x01, firmwareVersion: 0x41)
    let modem: DeviceDescription = catalog.describe(category: 0x03, subcategory: 0x33, firmwareVersion: 0xA5)
    let unknown: DeviceDescription = catalog.describe(category: 0x10, subcategory: 0x7F, firmwareVersion: 0x41)

    #expect(sensor.identity?.subcategory == 0x01)
    #expect(sensor.productKey == .key(ProductKey(0x00, 0x00, 0x1A)))
    #expect(sensor.hubLinkingLegs.map(\.deviceGroup) == [1, 2])
    #expect(sensor.hubLinking?.isDeviceFirst == true)
    #expect(sensor.modemLinkData == nil)
    #expect(modem.modemLinkData?.controller.count == 3)
    #expect(modem.productKey == nil)
    #expect(unknown.identity == nil)
    #expect(unknown.hubLinkingLegs.isEmpty)

  }

  // MARK: - Guards

  @Test func readsTheGuardsOfFlagsCommandsAndBits() throws {

    let commands: CommandSet = try Self.commands()

    #expect(commands.operatingFlags.map(\.writeGuard) == [.neverSet, .keep, nil, FlagGuard(rawValue: "somethingNewer"), nil])
    #expect(commands.flagCommands.map(\.sendGuard) == [.never, nil])
    #expect(commands.standardCommands.map(\.sendGuard) == [.never, nil])
    #expect(commands.extendedCommands.map(\.sendGuard) == [.never, nil])

    let parameter = try #require(commands.extendedCommand(named: "writeProperties")?.parameters.first)

    guard case let .flags(bits) = parameter.kind else {

      Issue.record("Expected a flags parameter, got \(parameter.kind).")

      return

    }

    #expect(bits.map(\.writeGuard) == [.neverSet, .keep, nil])

  }

  @Test func readsAValueThatHoldsOperatingFlags() throws {

    let commands: CommandSet = try Self.commands()
    let configuration = try #require(commands.extendedSettings?.value(named: "configuration"))
    let level = try #require(commands.extendedSettings?.value(named: "level"))

    #expect(configuration.flagsQuery == .operatingFlags)
    #expect(commands.flagsHeld(by: configuration).map(\.name) == ["programmingLock", "radioOff", "beep", "newer"])
    #expect(level.flagsQuery == nil)
    #expect(commands.flagsHeld(by: level).isEmpty)

  }

  @Test func readsTheFlagsLinkingChanges() throws {

    let commands: CommandSet = try Self.commands()

    #expect(commands.linkingChanges == [
      LinkingChange(flag: "beep"),
      LinkingChange(flag: "other", verification: Verification(status: .observed, note: "Seen on a device.", firmware: [0x41]))
    ])

  }

  // MARK: - Group types

  @Test func readsAStatePatternOutputsAndArmModes() throws {

    let commands: CommandSet = try Self.commands()
    let zone = try #require(commands.groupType(named: "zone2"))
    let light = try #require(commands.groupType(named: "light"))
    let alarm = try #require(commands.groupType(named: "soundAway"))
    let arming = try #require(commands.groupType(named: "armAll"))
    let onWhen = try #require(zone.state?.onWhen)

    #expect(onWhen == GroupType.State.OnWhen(mask: 0x87, value: 0x81, verification: Verification(status: .inferred, note: "Read from the status byte.")))
    #expect(onWhen.isOn(command2: 0x81))
    #expect(onWhen.isOn(command2: 0xF9))
    #expect(!onWhen.isOn(command2: 0x01))
    #expect(!onWhen.isOn(command2: 0x82))
    #expect(zone.outputs == nil)
    #expect(zone.armModes.isEmpty)
    #expect(light.outputs == GroupType.Outputs(
      activeWhen: DeviceProfile.Group.Condition(flag: "relayMode", isSet: true),
      bits: [
        GroupType.Outputs.Output(mask: 0x01, name: "relay1", label: "Relay 1"),
        GroupType.Outputs.Output(mask: 0x02, name: "relay2", label: "Relay 2")
      ],
      verification: Verification(status: .documented, note: "Its notes say so.")
    ))
    #expect(light.state == nil)
    #expect(alarm.kind == .alarm)
    // A mode from a later version keeps its name.
    #expect(alarm.armModes == [.away, GroupType.ArmMode(rawValue: "somethingNewer")])
    #expect(arming.kind == .arming)
    #expect(arming.armModes == [.home, .away])
    #expect(commands.groupType(named: "blind")?.kind == .windowCovering)

  }

  // MARK: - Versions

  @Test func readsTheBundledCatalog() throws {

    let catalog: DeviceCatalog = try DeviceCatalog.bundled()

    #expect(!catalog.profiles.isEmpty)
    #expect(!catalog.commandSets.isEmpty)

  }

  @Test func readsOnlyTheBundledMajorAndMinor() throws {

    let bundled: DeviceCatalogVersion = try DeviceCatalog.bundledVersion()
    let nextMinor = DeviceCatalogVersion(major: bundled.major, minor: bundled.minor + 1, patch: 0)

    #expect(!nextMinor.isCompatible(with: bundled))

  }

}
