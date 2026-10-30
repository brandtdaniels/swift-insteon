import Foundation
import Testing
import InsteonCore
import InsteonLinking
import InsteonProtocol

/// Applying what one process changed to a snapshot another process saved since.
struct NetworkSnapshotMergeTests {

  static let earlier: Date = Date(timeIntervalSince1970: 1_800_000_000)

  static let later: Date = Date(timeIntervalSince1970: 1_800_000_060)

  static let latest: Date = Date(timeIntervalSince1970: 1_800_000_120)

  static let link = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 0x01, address: InsteonAddress(0x11, 0x22, 0x33), data1: 0xFF, data2: 0x1C, data3: 0x01)

  static let otherLink = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x00, address: Example.plug, data1: 0x02, data2: 0x7A, data3: 0x41)

  static func database(delta: UInt8, _ record: AllLinkRecord) -> AllLinkDatabaseCopy {

    AllLinkDatabaseCopy(delta: delta, records: [AllLinkRecordResponse(sender: Example.plug, address: 0x0FFF, record: record)])

  }

  @Test func keepsADeviceAnotherProcessUpdatedThatThisOneDidntChange() {

    let start = NetworkSnapshot(
      registry: DeviceRegistrySnapshot(identities: [Example.plug: Example.plugIdentity]),
      devices: [Example.plug: NetworkDeviceState(allLinkDatabase: Self.database(delta: 0x01, Self.link), level: 0x00, lastSeen: Self.earlier)]
    )
    var current: NetworkSnapshot = start
    current.devices[Example.plug] = NetworkDeviceState(allLinkDatabase: Self.database(delta: 0x02, Self.otherLink), level: 0xFF, lastSeen: Self.later)

    // This process learned only about the lamp.
    var end: NetworkSnapshot = start
    end.devices[Example.lamp] = NetworkDeviceState(level: 0x80, lastSeen: Self.latest)

    let merged: NetworkSnapshot = current.merging(changesFrom: start, to: end)

    #expect(merged.devices[Example.plug] == current.devices[Example.plug])
    #expect(merged.devices[Example.lamp] == NetworkDeviceState(level: 0x80, lastSeen: Self.latest))
    #expect(merged.registry == start.registry)

  }

  @Test func takesWhatThisProcessChangedOverWhatAnotherSaved() {

    let start = NetworkSnapshot(devices: [Example.plug: NetworkDeviceState(engine: .i2, level: 0x00, lastSeen: Self.earlier)])
    var current: NetworkSnapshot = start
    current.devices[Example.plug] = NetworkDeviceState(engine: .i2, level: 0x40, lastSeen: Self.later)
    current.registry.identities[Example.plug] = Example.lampIdentity

    var end: NetworkSnapshot = start
    end.devices[Example.plug] = NetworkDeviceState(engine: .i2cs, level: 0xFF, lastSeen: Self.latest)
    end.registry.identities[Example.plug] = Example.plugIdentity

    let merged: NetworkSnapshot = current.merging(changesFrom: start, to: end)

    #expect(merged.devices[Example.plug] == NetworkDeviceState(engine: .i2cs, level: 0xFF, lastSeen: Self.latest))
    #expect(merged.registry.identities == [Example.plug: Example.plugIdentity])

  }

  @Test func writesBackOnlyTheFieldsThisProcessChanged() {

    let start = NetworkSnapshot(devices: [Example.plug: NetworkDeviceState(engine: .i2, allLinkDatabase: Self.database(delta: 0x01, Self.link), level: 0x00, lastSeen: Self.earlier)])
    var current: NetworkSnapshot = start
    current.devices[Example.plug] = NetworkDeviceState(engine: .i2cs, allLinkDatabase: Self.database(delta: 0x02, Self.otherLink), level: 0x40, lastSeen: Self.later)

    // This process changed only the level and when the device last answered.
    var end: NetworkSnapshot = start
    end.devices[Example.plug]?.level = 0xFF
    end.devices[Example.plug]?.lastSeen = Self.latest

    let merged: NetworkSnapshot = current.merging(changesFrom: start, to: end)
    let state: NetworkDeviceState? = merged.devices[Example.plug]

    #expect(state?.engine == .i2cs)
    #expect(state?.allLinkDatabase == Self.database(delta: 0x02, Self.otherLink))
    #expect(state?.level == 0xFF)
    #expect(state?.lastSeen == Self.latest)

  }

  @Test func removesWhatThisProcessRemoved() {

    let start = NetworkSnapshot(
      registry: DeviceRegistrySnapshot(identities: [Example.plug: Example.plugIdentity]),
      devices: [Example.plug: NetworkDeviceState(allLinkDatabase: Self.database(delta: 0x01, Self.link))]
    )

    // A linker changed the plug's database, so the network forgot its copy, and nothing else
    // is known about the device.
    var end: NetworkSnapshot = start
    end.devices[Example.plug] = nil
    end.registry.identities[Example.plug] = nil

    let merged: NetworkSnapshot = start.merging(changesFrom: start, to: end)

    #expect(merged.devices[Example.plug] == nil)
    #expect(merged.registry.identities[Example.plug] == nil)

  }

  @Test func keepsTheModemsDatabaseAndTheHubThisProcessDidntChange() {

    let start = NetworkSnapshot(modemDatabase: [Self.link], hub: HubLocation(host: "192.0.2.10", port: 25105))
    var current: NetworkSnapshot = start
    current.modemDatabase = [Self.link, Self.otherLink]
    current.hub = HubLocation(host: "192.0.2.10", port: 25105, insteonID: InsteonAddress(0x44, 0x55, 0x66))

    var end: NetworkSnapshot = start
    end.devices[Example.lamp] = NetworkDeviceState(lastSeen: Self.latest)

    let merged: NetworkSnapshot = current.merging(changesFrom: start, to: end)

    #expect(merged.modemDatabase == [Self.link, Self.otherLink])
    #expect(merged.hub == HubLocation(host: "192.0.2.10", port: 25105, insteonID: InsteonAddress(0x44, 0x55, 0x66)))

  }

  @Test func takesTheModemsDatabaseAndTheHubThisProcessChanged() {

    let start = NetworkSnapshot(modemDatabase: [Self.link], hub: HubLocation(host: "192.0.2.10", port: 25105))
    var current: NetworkSnapshot = start
    current.modemDatabase = [Self.link, Self.otherLink]
    current.hub = HubLocation(host: "192.0.2.11", port: 25105)

    var end: NetworkSnapshot = start
    end.modemDatabase = [Self.otherLink]
    end.hub = HubLocation(host: "192.0.2.10", port: 25105, insteonID: InsteonAddress(0x11, 0x22, 0x33))

    let merged: NetworkSnapshot = current.merging(changesFrom: start, to: end)

    #expect(merged.modemDatabase == [Self.otherLink])
    #expect(merged.hub == HubLocation(host: "192.0.2.10", port: 25105, insteonID: InsteonAddress(0x11, 0x22, 0x33)))

  }

  @Test func changesNothingWhenThisProcessChangedNothing() {

    let start = NetworkSnapshot(devices: [Example.plug: NetworkDeviceState(level: 0x00)], modemDatabase: [Self.link])
    let current = NetworkSnapshot(
      registry: DeviceRegistrySnapshot(identities: [Example.lamp: Example.lampIdentity]),
      devices: [Example.plug: NetworkDeviceState(level: 0xFF)],
      modemDatabase: nil,
      hub: HubLocation(host: "192.0.2.10", port: 25105)
    )

    #expect(current.merging(changesFrom: start, to: start) == current)

  }

}
