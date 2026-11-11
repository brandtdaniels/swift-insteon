import Foundation
import Testing
@testable import InsteonCore
import InsteonDeviceCatalog
import InsteonLinkingTestSupport
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// Control from a made-up catalog in the catalog's own JSON: a zone's state from the bits its
/// `onWhen` names, one output of a load switched on its own, and arm modes. No name, identity
/// or flag here is a real product's.
struct CatalogControlTests {

  let clock: TestClock = TestClock()

  /// A sprinkler whose eight zones share one valve status byte, a dimmer whose load is two
  /// relays while its output mode flag is set, and an alarm whose groups sound or arm in home
  /// and away modes.
  static let json = #"""
    {
      "devices": [{
        "model": "9601",
        "name": "Example Sprinkler",
        "identities": [{ "category": "0x04", "subcategory": "0x7A" }],
        "commandSets": [{ "commandSet": "exampleSprinkler", "category": "0x04", "subcategory": "0x7A" }],
        "groups": [
          { "number": "0x01", "name": "Zone 1", "role": "responder", "type": "zone1" },
          { "number": "0x02", "name": "Zone 2", "role": "responder", "type": "zone2" },
          { "number": "0x03", "name": "Zone 3", "role": "responder", "type": "zone3" },
          { "number": "0x04", "name": "Zone 4", "role": "responder", "type": "zone4" },
          { "number": "0x05", "name": "Zone 5", "role": "responder", "type": "zone5" },
          { "number": "0x06", "name": "Zone 6", "role": "responder", "type": "zone6" },
          { "number": "0x07", "name": "Zone 7", "role": "responder", "type": "zone7" },
          { "number": "0x08", "name": "Zone 8", "role": "responder", "type": "zone8" }
        ],
        "capabilities": [{ "kind": "onOff" }],
        "sources": ["A"]
      }, {
        "model": "9602",
        "name": "Example Two-Relay Dimmer",
        "identities": [{ "category": "0x01", "subcategory": "0x7A" }],
        "commandSets": [{ "commandSet": "exampleTwoRelay", "category": "0x01", "subcategory": "0x7A" }],
        "groups": [{ "number": "0x01", "name": "Load", "role": "both", "type": "light" }],
        "capabilities": [{ "kind": "dimmable" }],
        "sources": ["A"]
      }, {
        "model": "9603",
        "name": "Example Alarm",
        "identities": [{ "category": "0x07", "subcategory": "0x7A" }],
        "commandSets": [{ "commandSet": "exampleAlarm", "category": "0x07", "subcategory": "0x7A" }],
        "groups": [
          { "number": "0x01", "name": "Sound when armed away", "role": "both", "type": "soundAway" },
          { "number": "0x02", "name": "Arm away", "role": "responder", "type": "armAway" },
          { "number": "0x03", "name": "Sound when armed home", "role": "responder", "type": "soundHome" },
          { "number": "0x04", "name": "Arm home", "role": "responder", "type": "armHome" },
          { "number": "0x05", "name": "Sound when armed", "role": "responder", "type": "soundArmed" },
          { "number": "0x06", "name": "Arm home and away", "role": "responder", "type": "armHomeAndAway" }
        ],
        "capabilities": [],
        "sources": ["A"]
      }],
      "commandSets": [{
        "id": "exampleSprinkler",
        "name": "Example sprinkler",
        "description": "Eight zones in one valve status byte: bits 0 to 2 the active valve, bit 7 whether a valve is on.",
        "standardCommands": [
          { "name": "valveOn", "description": "Turns on the valve in cmd2.", "command1": "0x40",
            "parameter": { "name": "valve", "description": "The valve.", "range": { "from": 0, "through": 7 } }, "effect": "actuation", "idempotent": true },
          { "name": "valveOff", "description": "Turns off the valve in cmd2.", "command1": "0x41",
            "parameter": { "name": "valve", "description": "The valve.", "range": { "from": 0, "through": 7 } }, "effect": "actuation", "idempotent": true },
          { "name": "readValveStatus", "description": "Reads the valve status byte.", "command1": "0x44", "command2": "0x02",
            "reply": { "name": "valveStatus", "description": "The valve status byte.", "kind": "flags",
              "bits": [{ "mask": "0x07", "name": "activeValve", "description": "The active valve." }, { "mask": "0x80", "name": "anyValveOn", "description": "A valve is on." }] }, "effect": "actuation", "idempotent": true }
        ],
        "groupTypes": [
          { "name": "zone1", "label": "Zone 1", "kind": "relay",
            "state": { "command": "readValveStatus", "onWhen": { "mask": "0x87", "value": "0x80" } },
            "actions": [{ "name": "on", "label": "On", "command": "valveOn", "value": "0x00" }, { "name": "off", "label": "Off", "command": "valveOff", "value": "0x00" }] },
          { "name": "zone2", "label": "Zone 2", "kind": "relay",
            "state": { "command": "readValveStatus", "onWhen": { "mask": "0x87", "value": "0x81" } },
            "actions": [{ "name": "on", "label": "On", "command": "valveOn", "value": "0x01" }, { "name": "off", "label": "Off", "command": "valveOff", "value": "0x01" }] },
          { "name": "zone3", "label": "Zone 3", "kind": "relay",
            "state": { "command": "readValveStatus", "onWhen": { "mask": "0x87", "value": "0x82" } },
            "actions": [{ "name": "on", "label": "On", "command": "valveOn", "value": "0x02" }, { "name": "off", "label": "Off", "command": "valveOff", "value": "0x02" }] },
          { "name": "zone4", "label": "Zone 4", "kind": "relay",
            "state": { "command": "readValveStatus", "onWhen": { "mask": "0x87", "value": "0x83" } },
            "actions": [{ "name": "on", "label": "On", "command": "valveOn", "value": "0x03" }, { "name": "off", "label": "Off", "command": "valveOff", "value": "0x03" }] },
          { "name": "zone5", "label": "Zone 5", "kind": "relay",
            "state": { "command": "readValveStatus", "onWhen": { "mask": "0x87", "value": "0x84" } },
            "actions": [{ "name": "on", "label": "On", "command": "valveOn", "value": "0x04" }, { "name": "off", "label": "Off", "command": "valveOff", "value": "0x04" }] },
          { "name": "zone6", "label": "Zone 6", "kind": "relay",
            "state": { "command": "readValveStatus", "onWhen": { "mask": "0x87", "value": "0x85" } },
            "actions": [{ "name": "on", "label": "On", "command": "valveOn", "value": "0x05" }, { "name": "off", "label": "Off", "command": "valveOff", "value": "0x05" }] },
          { "name": "zone7", "label": "Zone 7", "kind": "relay",
            "state": { "command": "readValveStatus", "onWhen": { "mask": "0x87", "value": "0x86" } },
            "actions": [{ "name": "on", "label": "On", "command": "valveOn", "value": "0x06" }, { "name": "off", "label": "Off", "command": "valveOff", "value": "0x06" }] },
          { "name": "zone8", "label": "Zone 8", "kind": "relay",
            "state": { "command": "readValveStatus", "onWhen": { "mask": "0x87", "value": "0x87" } },
            "actions": [{ "name": "on", "label": "On", "command": "valveOn", "value": "0x07" }, { "name": "off", "label": "Off", "command": "valveOff", "value": "0x07" }] }
        ],
        "sources": ["A"]
      }, {
        "id": "exampleTwoRelay",
        "name": "Example two-relay dimmer",
        "description": "A dimmer whose load is two relays in output mode.",
        "operatingFlags": [
          { "name": "outputMode", "description": "The load is two relays.", "query": "0x05", "bit": "0x80", "on": "0x1F", "off": "0x1E", "label": "Output mode" }
        ],
        "standardCommands": [
          { "name": "lightOn", "description": "Turns the load on.", "command1": "0x11", "parameter": { "name": "onLevel", "description": "The level, or the relays." }, "effect": "actuation", "idempotent": true },
          { "name": "lightOff", "description": "Turns the load off.", "command1": "0x13", "parameter": { "name": "relays", "description": "The relays." }, "effect": "actuation", "idempotent": true },
          { "name": "readStatus", "description": "Reads the level.", "command1": "0x19", "command2": "0x00",
            "reply": { "name": "onLevel", "description": "The level.", "scale": 0.392157, "unit": "percent" }, "effect": "readOnly", "idempotent": true }
        ],
        "groupTypes": [{
          "name": "light",
          "label": "Light",
          "kind": "dimmer",
          "state": { "command": "readStatus" },
          "actions": [{ "name": "on", "label": "On", "command": "lightOn" }, { "name": "off", "label": "Off", "command": "lightOff" }],
          "outputs": { "activeWhen": { "flag": "outputMode", "set": true },
            "bits": [{ "mask": "0x01", "name": "relay1", "label": "Relay 1" }, { "mask": "0x02", "name": "relay2", "label": "Relay 2" }] }
        }],
        "sources": ["A"]
      }, {
        "id": "exampleAlarm",
        "name": "Example alarm",
        "description": "Groups that sound or arm in home and away modes.",
        "groupTypes": [
          { "name": "soundAway", "label": "Sound when armed away", "kind": "alarm", "armModes": ["away"] },
          { "name": "armAway", "label": "Arm away", "kind": "arming", "armModes": ["away"] },
          { "name": "soundHome", "label": "Sound when armed home", "kind": "alarm", "armModes": ["home"] },
          { "name": "armHome", "label": "Arm home", "kind": "arming", "armModes": ["home"] },
          { "name": "soundArmed", "label": "Sound when armed", "kind": "alarm", "armModes": ["home", "away"] },
          { "name": "armHomeAndAway", "label": "Arm home and away", "kind": "arming", "armModes": ["home", "away"] }
        ],
        "sources": ["A"]
      }]
    }
    """#

  static func catalog() throws -> DeviceCatalog {

    try DeviceCatalog(json: Data(json.utf8))

  }

  /// The sprinkler's control model.
  func sprinkler() throws -> DeviceControlModel {

    DeviceControlModel.make(try Self.catalog().describe(category: 0x04, subcategory: 0x7A, firmwareVersion: nil))

  }

  /// The two-relay dimmer on a modem whose operating flags are `flags`.
  func makeTwoRelay(flags: UInt8) throws -> (Device, SettingsModem) {

    let address = InsteonAddress(0x6C, 0x7D, 0x01)
    let modem = SettingsModem(device: address, flags: flags, values: [:])
    let network = DeviceNetwork(
      modem: modem,
      catalog: try Self.catalog(),
      snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [address: ReportedIdentity(category: 0x01, subcategory: 0x7A, firmwareVersion: 0x41)])),
      clock: clock,
      now: { () -> Date in Date(timeIntervalSince1970: 1_800_000_000) }
    )

    return (network.device(address), modem)

  }

  // MARK: - onWhen

  @Test func readsZoneOneOffWhileAnotherZoneRuns() throws {

    let model: DeviceControlModel = try sprinkler()
    let zone1: DeviceControlModel.Group = try #require(model.group(1))
    let zone3: DeviceControlModel.Group = try #require(model.group(3))

    // Bit 7: a valve is on; bits 0 to 2: zone 3, the active valve.
    #expect(Device.reading(of: 0x82, group: zone1, in: model, reply: nil).reading == .onOff(false))
    #expect(!Device.reading(of: 0x82, group: zone1, in: model, reply: nil).isOn)
    #expect(Device.reading(of: 0x82, group: zone3, in: model, reply: nil).reading == .onOff(true))
    // Zone 1 is the active valve but every valve is off.
    #expect(Device.reading(of: 0x00, group: zone1, in: model, reply: nil).reading == .onOff(false))

  }

  @Test func readsZoneOneOnWhenItsBitsMatch() throws {

    let model: DeviceControlModel = try sprinkler()
    let zone1: DeviceControlModel.Group = try #require(model.group(1))

    #expect(Device.reading(of: 0x80, group: zone1, in: model, reply: nil).reading == .onOff(true))
    // Bits the pattern doesn't name don't matter.
    #expect(Device.reading(of: 0xF8, group: zone1, in: model, reply: nil).isOn)

  }

  @Test func readsEveryZoneFromTheSharedValveStatus() throws {

    let model: DeviceControlModel = try sprinkler()

    #expect(model.groups.map(\.number.rawValue) == [1, 2, 3, 4, 5, 6, 7, 8])

    for group in model.groups {

      // Each zone has its own pattern, so the shared reply says which zone is on.
      #expect(model.canRead(group), "zone \(group.number)")

      let active: UInt8 = 0x80 | (group.number.rawValue - 1)

      #expect(Device.reading(of: active, group: group, in: model, reply: nil).isOn, "zone \(group.number)")

      for other in model.groups where other.number != group.number {

        #expect(!Device.reading(of: active, group: other, in: model, reply: nil).isOn, "zone \(other.number) while \(group.number) runs")

      }

    }

    // None of them is the device's level.
    #expect(model.groups.allSatisfy { (group: DeviceControlModel.Group) -> Bool in !model.reportsDeviceLevel(group) })

  }

  // MARK: - Outputs

  @Test(.timeLimit(.minutes(1))) func switchesOneRelayOfTheDimmerInOutputMode() async throws {

    // Output mode's bit, 0x80 of the Get Operating Flags 0x05 reply, is set; the modem
    // reports the same byte for every query.
    let (dimmer, modem): (Device, SettingsModem) = try makeTwoRelay(flags: 0x80)

    let result: DeviceTurnOnResult = try await dimmer.turnOn(outputs: ["relay2"])

    #expect(result.group == 1)
    #expect(result.level == nil)
    // Get Operating Flags 0x05, whose reply holds output mode, then Light On with relay 2's bit.
    #expect(await modem.standardCommands == [Command(command1: 0x1F, command2: 0x05), Command(command1: 0x11, command2: 0x02)])

  }

  @Test(.timeLimit(.minutes(1))) func switchesBothRelaysByTheirBitsORedTogether() async throws {

    let (dimmer, modem): (Device, SettingsModem) = try makeTwoRelay(flags: 0x80)

    _ = try await dimmer.turnOn(outputs: ["Relay 1", "relay2"])
    try await dimmer.turnOff(outputs: ["relay1"])

    #expect(await modem.standardCommands.filter { (command: Command) -> Bool in command.command1 != 0x1F } == [
      Command(command1: 0x11, command2: 0x03),
      Command(command1: 0x13, command2: 0x01)
    ])

  }

  @Test(.timeLimit(.minutes(1))) func switchesNoOutputOutsideOutputMode() async throws {

    let (dimmer, modem): (Device, SettingsModem) = try makeTwoRelay(flags: 0x00)

    do {

      _ = try await dimmer.turnOn(outputs: ["relay1"])
      Issue.record("Expected outputsInactive.")

    } catch let DeviceControlError.outputsInactive(group, _) {

      #expect(group == 1)

    }

    // Only output mode's flags byte was read.
    #expect(await modem.standardCommands == [Command(command1: 0x1F, command2: 0x05)])

  }

  @Test(.timeLimit(.minutes(1))) func refusesAnOutputTheGroupDoesntHave() async throws {

    let (dimmer, modem): (Device, SettingsModem) = try makeTwoRelay(flags: 0x80)

    do {

      _ = try await dimmer.turnOn(outputs: ["relay3"])
      Issue.record("Expected noSuchOutput.")

    } catch let DeviceControlError.noSuchOutput(name, group, _) {

      #expect(name == "relay3")
      #expect(group == 1)

    }

    #expect(await modem.standardCommands.isEmpty)

  }

  @Test(.timeLimit(.minutes(1))) func listsTheDimmersOutputs() async throws {

    let (dimmer, _): (Device, SettingsModem) = try makeTwoRelay(flags: 0x80)

    let load: DeviceGroup = try #require(try await dimmer.capabilities().group(1))

    #expect(load.outputs == [DeviceOutput(key: "relay1", label: "Relay 1"), DeviceOutput(key: "relay2", label: "Relay 2")])
    #expect(load.outputsActiveWhen == DeviceFlagCondition(flag: "outputMode", isSet: true))
    #expect(load.armModes.isEmpty)

  }

  // MARK: - Arm modes

  @Test(.timeLimit(.minutes(1))) func exposesTheAlarmsArmModes() async throws {

    let address = InsteonAddress(0x6C, 0x7D, 0x02)
    let network = DeviceNetwork(
      modem: InMemoryModem(),
      catalog: try Self.catalog(),
      snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [address: ReportedIdentity(category: 0x07, subcategory: 0x7A, firmwareVersion: 0x41)])),
      clock: clock,
      now: { () -> Date in Date(timeIntervalSince1970: 1_800_000_000) }
    )

    let capabilities: DeviceCapabilities = try await network.device(address).capabilities()
    let modes: [Int: [String]] = Dictionary(uniqueKeysWithValues: capabilities.groups.map { (group: DeviceGroup) -> (Int, [String]) in (group.number, group.armModes) })

    #expect(modes == [1: ["away"], 2: ["away"], 3: ["home"], 4: ["home"], 5: ["home", "away"], 6: ["home", "away"]])
    #expect(capabilities.groups.first?.kind == .alarm)
    #expect(capabilities.groups.dropFirst().first?.kind == .arming)

  }

}

extension DeviceCapabilities {

  /// The group with a number, if the device has it.
  func group(_ number: Int) -> DeviceGroup? {

    groups.first { (group: DeviceGroup) -> Bool in group.number == number }

  }

}
