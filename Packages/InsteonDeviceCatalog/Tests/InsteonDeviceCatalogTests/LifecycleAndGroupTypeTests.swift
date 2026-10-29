import Foundation
import Testing
import InsteonDeviceCatalog
import InsteonProtocol

struct LifecycleAndGroupTypeTests {

  static let profile = #"""
    {
      "model": "1",
      "name": "Test Keypad",
      "identities": [{ "category": "0x01", "subcategory": "0x7A" }],
      "groups": [
        { "number": "0x01", "name": "Load", "role": "both", "type": "load" },
        { "number": "0x09", "name": "Detached load", "role": "responder", "type": "load",
          "activeWhen": { "flag": "detachedLoad", "set": true } }
      ],
      "capabilities": [],
      "lifecycle": {
        "installation": { "steps": [{ "action": "plugIn", "text": "Plug it in." }] },
        "linking": {
          "steps": [{ "action": "hold", "control": "SET button", "seconds": 3, "expect": "Beep", "text": "Hold the SET button." }],
          "notes": ["A note."],
          "verification": { "status": "inferred", "note": "Read from a similar product." },
          "alternatives": [{
            "description": "From software",
            "steps": [
              { "action": "send", "device": "other", "command": "Start ALL-Linking", "text": "Start ALL-Linking." },
              { "action": "tap", "count": 2, "text": "Tap twice." },
              { "action": "somethingNewer", "device": "somewhereNewer", "text": "Do something newer." }
            ]
          }]
        },
        "linkingTimeoutSeconds": 240,
        "waking": { "steps": [{ "action": "wait", "seconds": 0.5, "text": "Wait." }] },
        "awakeSeconds": 180,
        "resetErases": ["links", "somethingNewer"]
      },
      "sources": ["A"]
    }
    """#

  static let commandSet = #"""
    {
      "id": "testKeypad",
      "name": "Test Keypad",
      "description": "A made-up command set.",
      "valueTables": [{
        "name": "rate",
        "description": "Made-up rates.",
        "values": [
          { "value": "0x00", "label": "Slow", "seconds": 90 },
          { "value": "0x1F", "label": "At once" }
        ]
      }],
      "groupTypes": [
        {
          "name": "load",
          "label": "Load",
          "kind": "dimmer",
          "state": { "command": "readLevel", "ranges": [{ "from": "0x00", "through": "0x7F", "label": "Low" }] },
          "actions": [
            { "name": "on", "label": "On", "command": "loadOn", "value": "0xC0" },
            { "name": "off", "label": "Off", "command": "loadOff", "schedulable": false }
          ],
          "linkData": {
            "responder": [
              { "byte": 1, "name": "onLevel", "label": "Level", "description": "The level.",
                "range": { "from": "0x00", "through": "0xFF" }, "unit": "percent", "scale": 0.5,
                "verification": { "status": "conflicting", "note": "Two documents differ." } },
              { "byte": 2, "name": "rate", "description": "The rate.", "table": "rate" },
              { "byte": 3, "name": "button", "description": "The button.", "perGroup": true, "value": "0x01", "unit": "somethingNewer" }
            ],
            "controller": [{ "byte": 3, "name": "group", "description": "The group." }]
          }
        },
        { "name": "remote", "label": "Remote", "kind": "somethingNewer", "state": { "command": "readStatus", "bitPerGroup": true } }
      ],
      "sources": ["A"]
    }
    """#

  static func catalog(profile: String = LifecycleAndGroupTypeTests.profile, commandSet: String = LifecycleAndGroupTypeTests.commandSet) throws -> DeviceCatalog {

    try DeviceCatalog(json: Data(#"{ "devices": [\#(profile)], "commandSets": [\#(commandSet)] }"#.utf8))

  }

  @Test func readsALifecycle() throws {

    let lifecycle = try #require(try Self.catalog().profiles.first?.lifecycle)
    let linking = try #require(lifecycle.linking)

    #expect(lifecycle.installation == DeviceLifecycle.Procedure(steps: [.init(text: "Plug it in.", action: .plugIn)]))
    #expect(linking.steps == [.init(text: "Hold the SET button.", action: .hold, control: "SET button", duration: .seconds(3), expectation: "Beep")])
    #expect(linking.notes == ["A note."])
    #expect(linking.verification == Verification(status: .inferred, note: "Read from a similar product."))
    #expect(linking.alternatives.map(\.summary) == ["From software"])
    #expect(lifecycle.linkingTimeout == .seconds(240))
    #expect(lifecycle.waking?.steps.first?.duration == .milliseconds(500))
    #expect(lifecycle.awakeDuration == .seconds(180))
    #expect(lifecycle.reset == nil)
    // What a reset erases from a later version of the catalog is passed over.
    #expect(lifecycle.resetErases == [.links])

  }

  @Test func readsAnAlternativesSteps() throws {

    let alternative = try #require(try Self.catalog().profiles.first?.lifecycle?.linking?.alternatives.first)

    #expect(alternative.steps == [
      .init(text: "Start ALL-Linking.", isOnOtherDevice: true, action: .send, command: "Start ALL-Linking"),
      .init(text: "Tap twice.", action: .tap, count: 2),
      // An action from a later version keeps its name, and a device from one reads as this one.
      .init(text: "Do something newer.", action: DeviceLifecycle.Step.Action(rawValue: "somethingNewer")),
    ])
    #expect(alternative.verification == .documented)

  }

  @Test func readsAProfileWithoutALifecycle() throws {

    let profile = try #require(try DeviceCatalog(json: DeviceCatalogTests.json(DeviceCatalogTests.leakSensor)).profiles.first)

    #expect(profile.lifecycle == nil)

  }

  @Test(arguments: ["-1", "31622401"])
  func refusesSecondsOutOfRange(_ seconds: String) {

    let profile = #"{ "model": "1", "name": "A", "identities": [{ "category": "0x01", "subcategory": "0x01" }], "capabilities": [], "lifecycle": { "awakeSeconds": \#(seconds) }, "sources": ["A"] }"#

    #expect(throws: DecodingError.self) {

      try DeviceCatalog(json: DeviceCatalogTests.json(profile))

    }

  }

  @Test func readsAGroupsTypeAndWhenItsInUse() throws {

    let groups = try #require(try Self.catalog().profiles.first?.groups)

    #expect(groups == [
      .init(number: 0x01, name: "Load", role: .both, type: "load"),
      .init(number: 0x09, name: "Detached load", role: .responder, type: "load", activeWhen: DeviceProfile.Group.Condition(flag: "detachedLoad", isSet: true)),
    ])

  }

  @Test func readsAGroupType() throws {

    let commands = try #require(try Self.catalog().commandSet(id: "testKeypad"))
    let load = try #require(commands.groupType(named: "load"))

    #expect(load.label == "Load")
    #expect(load.kind == .dimmer)
    #expect(load.state == GroupType.State(command: "readLevel", ranges: [.init(values: 0x00...0x7F, label: "Low")]))
    #expect(load.actions == [
      .init(name: "on", label: "On", command: "loadOn", value: 0xC0),
      .init(name: "off", label: "Off", command: "loadOff", isSchedulable: false),
    ])
    #expect(load.action(named: "off")?.isSchedulable == false)
    #expect(load.verification == .documented)

    // A kind from a later version keeps its name.
    let remote = try #require(commands.groupType(named: "remote"))
    #expect(remote.kind.rawValue == "somethingNewer")
    #expect(remote.state?.isBitPerGroup == true)
    #expect(remote.actions.isEmpty)
    #expect(remote.linkData == GroupType.LinkData())
    #expect(commands.groupType(named: "fan") == nil)

  }

  @Test func readsAGroupTypesLinkData() throws {

    let load = try #require(try Self.catalog().commandSet(id: "testKeypad")?.groupType(named: "load"))

    #expect(load.linkData.responder == [
      LinkDataByte(
        position: 1,
        name: "onLevel",
        label: "Level",
        summary: "The level.",
        range: 0x00...0xFF,
        unit: .percent,
        scale: 0.5,
        verification: Verification(status: .conflicting, note: "Two documents differ.")
      ),
      LinkDataByte(position: 2, name: "rate", summary: "The rate.", table: "rate"),
      // A unit from a later version reads as none.
      LinkDataByte(position: 3, name: "button", summary: "The button.", value: 0x01, isPerGroup: true),
    ])
    #expect(load.linkData.controller == [LinkDataByte(position: 3, name: "group", summary: "The group.")])

  }

  @Test func readsAValueTable() throws {

    let commands = try #require(try Self.catalog().commandSet(id: "testKeypad"))
    let rate = try #require(commands.valueTable(named: "rate"))

    #expect(rate.summary == "Made-up rates.")
    #expect(rate.entries == [.init(value: 0x00, label: "Slow", duration: .seconds(90)), .init(value: 0x1F, label: "At once")])
    #expect(rate.entry(for: 0x1F)?.label == "At once")
    #expect(rate.entry(for: 0x01) == nil)
    #expect(commands.valueTable(named: "speed") == nil)

  }

  @Test(arguments: [
    #"{ "byte": 4, "name": "a", "description": "A." }"#,
    #"{ "byte": 0, "name": "a", "description": "A." }"#,
    #"{ "byte": 1, "name": "a", "description": "A.", "range": { "from": "0x10", "through": "0x0F" } }"#,
    #"{ "byte": 1, "name": "a", "description": "A.", "scale": 0 }"#,
  ])
  func refusesALinkDataByteThatCantBe(_ byte: String) {

    let commandSet = #"{ "id": "a", "name": "A", "description": "A.", "groupTypes": [{ "name": "a", "label": "A", "kind": "relay", "linkData": { "responder": [\#(byte)] } }], "sources": ["A"] }"#

    #expect(throws: DecodingError.self) {

      try Self.catalog(commandSet: commandSet)

    }

  }

  @Test func refusesAStateRangeThatEndsBeforeItStarts() {

    let commandSet = #"{ "id": "a", "name": "A", "description": "A.", "groupTypes": [{ "name": "a", "label": "A", "kind": "fan", "state": { "command": "a", "ranges": [{ "from": "0x80", "through": "0x7F", "label": "A" }] } }], "sources": ["A"] }"#

    #expect(throws: DecodingError.self) {

      try Self.catalog(commandSet: commandSet)

    }

  }

  @Test func readsTheBundledLifecyclesAndLinkData() throws {

    let catalog = try DeviceCatalog.bundled()

    // The dimmer switch's linking: the SET button, or from a Hub.
    let dimmer = try #require(catalog.profile(model: "2477D"))
    let lifecycle = try #require(dimmer.lifecycle)
    let linking = try #require(lifecycle.linking)
    #expect(linking.steps.first?.action == .hold)
    #expect(linking.steps.first?.control == "SET button")
    let fromHub = try #require(linking.alternatives.first)
    #expect(fromHub.steps.first?.action == .send)
    #expect(fromHub.steps.first?.isOnOtherDevice == true)
    #expect(lifecycle.installation?.steps.isEmpty == false)
    let reset = try #require(lifecycle.reset)
    #expect(reset.steps.contains(where: { $0.action == .wait && $0.duration == .seconds(10) }))
    #expect(lifecycle.resetErases == [.links, .settings])

    // Its load's records: the on-level in Data 1 and the ramp rate, by the ramp rate table, in
    // Data 2.
    let commands = try #require(catalog.commandSet(category: 0x01, subcategory: 0x20, firmwareVersion: 0x41))
    let typeName = try #require(dimmer.groups.first { $0.number == 0x01 }?.type)
    let light = try #require(commands.groupType(named: typeName))
    #expect(light.kind == .dimmer)
    #expect(light.action(named: "on")?.command == "lightOn")

    let onLevel = try #require(light.linkData.responder.first { $0.position == 1 })
    #expect(onLevel.name == "onLevel")
    #expect(onLevel.range?.lowerBound == 0x00)
    #expect(onLevel.range?.upperBound == 0xFF)
    #expect(onLevel.unit == .percent)

    let rampRate = try #require(light.linkData.responder.first { $0.position == 2 })
    let table = try #require(rampRate.table.flatMap { commands.valueTable(named: $0) })
    #expect(table.entry(for: 0x00)?.duration == .seconds(2))

    // Every group type a profile's group names is in each command set its identities use.
    for profile in catalog.profiles {

      for group in profile.groups {

        guard let type = group.type else {

          continue

        }

        for entry in profile.commandSets {

          #expect(catalog.commandSet(id: entry.commandSet)?.groupType(named: type) != nil, "\(profile.model) group \(group.number)")

        }

      }

    }

  }

}
