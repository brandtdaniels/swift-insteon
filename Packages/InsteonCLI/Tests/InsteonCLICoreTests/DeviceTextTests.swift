import Foundation
import Testing
import InsteonCLICore
import InsteonDeviceCatalog
import InsteonProtocol

/// A made-up catalog with one on/off plug, whose model and identity no real product has.
enum ExampleCatalog {

  static let identity = KnownIdentity(category: 0x02, subcategory: 0x7A, firmwareVersion: 0x41)

  static let load = GroupType(
    name: "load",
    label: "Load",
    kind: .relay,
    linkData: GroupType.LinkData(responder: [
      LinkDataByte(position: 1, name: "onLevel", label: "On-level", summary: "The on-level.", table: "onOff"),
      LinkDataByte(position: 2, name: "rampRate", label: "Ramp rate", summary: "The ramp rate."),
    ])
  )

  static let commands = CommandSet(
    id: "examplePlug",
    name: "Example Plug",
    summary: "A made-up command set.",
    groupTypes: [load],
    valueTables: [ValueTable(name: "onOff", entries: [.init(value: 0x00, label: "Off"), .init(value: 0xFF, label: "On")])]
  )

  static let plug = DeviceProfile(
    model: "9001",
    name: "Example Plug",
    aliases: ["ExampleLinc"],
    identities: [DeviceIdentity(category: 0x02, subcategory: 0x7A)],
    commandSets: [CommandSetEntry(commandSet: "examplePlug", category: 0x02, subcategory: 0x7A)],
    role: .responder,
    groups: [.init(number: 1, name: "Load", role: .responder, type: "load")],
    lifecycle: DeviceLifecycle(
      linking: DeviceLifecycle.Procedure(steps: [.init(text: "Hold the SET button until it beeps.", expectation: "LED blinks green")]),
      unlinking: DeviceLifecycle.Procedure(steps: [
        .init(text: "Press the Hub's button.", isOnOtherDevice: true),
        .init(text: "Hold the SET button until it beeps."),
        .init(text: "Hold it again until it beeps again.", expectation: "LED blinks red"),
      ])
    )
  )

  static let catalog = DeviceCatalog(profiles: [plug], commandSets: [commands])

}

struct DeviceTextTests {

  let plug = InsteonAddress(0x1A, 0x2B, 0x3C)

  // MARK: - Wording

  @Test func countsInTheSingularOnlyForOne() {

    #expect(Wording.count(0, "record") == "0 records")
    #expect(Wording.count(1, "record") == "1 record")
    #expect(Wording.count(2, "record") == "2 records")
    #expect(Wording.count(1, "entry", plural: "entries") == "1 entry")
    #expect(Wording.count(3, "entry", plural: "entries") == "3 entries")

  }

  // MARK: - The identity cache

  @Test func keepsTheIdentityCacheInTheCacheDirectory() {

    #expect(IdentityCache.path(environment: ["HOME": "/home/example"]) == "/home/example/.cache/insteon/identities.json")
    #expect(
      IdentityCache.path(environment: ["HOME": "/home/example", "XDG_CACHE_HOME": "/var/cache/example/"])
        == "/var/cache/example/insteon/identities.json"
    )
    // A relative XDG_CACHE_HOME is ignored, as the XDG Base Directory Specification asks.
    #expect(IdentityCache.path(environment: ["HOME": "/home/example", "XDG_CACHE_HOME": "cache"]) == "/home/example/.cache/insteon/identities.json")
    #expect(IdentityCache.path(environment: [:]) == nil)

  }

  @Test func roundTripsTheIdentityCache() throws {

    var cache = IdentityCache()
    cache[plug] = ExampleCatalog.identity
    cache[InsteonAddress(0x4D, 0x5E, 0x6F)] = KnownIdentity(category: 0x01, subcategory: 0x20, firmwareVersion: nil)

    let json = try cache.json()

    #expect(try IdentityCache(json: json) == cache)
    #expect(String(decoding: json, as: UTF8.self).contains("\"1A.2B.3C\""))

  }

  @Test func leavesOutCacheEntriesItCantRead() throws {

    let json = Data("""
      {"devices": {
        "1A.2B.3C": {"category": "0x02", "subcategory": "0x7A", "firmwareVersion": "0x41"},
        "not an address": {"category": "0x02", "subcategory": "0x7A"},
        "4D.5E.6F": {"category": "2", "subcategory": "0x7A"}
      }}
      """.utf8)

    #expect(try IdentityCache(json: json) == IdentityCache(identities: [plug: ExampleCatalog.identity]))

    #expect(throws: (any Error).self) {

      try IdentityCache(json: Data("not json".utf8))

    }

  }

  @Test func readsAnIdentityFromALinkOnlyWhenTheModemReportedOne() {

    let controller = AllLinkingCompleted(linkCode: 0x01, group: 0, address: plug, category: 0x02, subcategory: 0x7A, firmwareVersion: 0x41)
    let responder = AllLinkingCompleted(linkCode: 0x00, group: 1, address: plug, category: nil, subcategory: nil, firmwareVersion: nil)

    #expect(KnownIdentity(controller) == ExampleCatalog.identity)
    #expect(KnownIdentity(responder) == nil)

  }

  // MARK: - Known devices

  @Test func looksADeviceUpInTheCatalog() {

    let device = KnownDevice(identity: ExampleCatalog.identity, catalog: ExampleCatalog.catalog)

    #expect(device.productName == "Example Plug 9001 (ExampleLinc)")
    #expect(device.mainGroupType?.kind == .relay)
    #expect(device.responderGroupType(forRecordData: [0xFF, 0x1F, 0x01])?.name == "load")
    #expect(device.canControl == false)

    let unknown = KnownDevice(identity: KnownIdentity(category: 0x07, subcategory: 0x00, firmwareVersion: nil), catalog: ExampleCatalog.catalog)

    #expect(unknown.productName == nil)
    #expect(unknown.mainGroupType == nil)

    // Without the catalog, nothing is known about the product.
    #expect(KnownDevice(identity: ExampleCatalog.identity, catalog: nil).productName == nil)

  }

  // MARK: - Control

  @Test func turnsARelayFullyOnWhateverLevelIsAsked() {

    #expect(ControlText.level(percent: 50, kind: .relay) == 0xFF)
    #expect(ControlText.level(percent: 50, kind: .dimmer) == 0x80)
    #expect(ControlText.level(percent: 50, kind: nil) == 0x80)
    #expect(ControlText.level(percent: nil, kind: nil) == 0xFF)

    #expect(ControlText.turnedOn(plug, percent: 50, kind: .relay) == "1A.2B.3C is on/off only; turned it on.")
    #expect(ControlText.turnedOn(plug, percent: 100, kind: .relay) == "Turned 1A.2B.3C on.")
    #expect(ControlText.turnedOn(plug, percent: nil, kind: .dimmer) == "Turned 1A.2B.3C on.")
    #expect(ControlText.turnedOn(plug, percent: 50, kind: nil) == "Turned 1A.2B.3C on at 50%.")

  }

  @Test func readsARelaysStatusAsOnOrOff() {

    #expect(ControlText.status(plug, level: 0xFF, kind: .relay) == "1A.2B.3C is on.")
    #expect(ControlText.status(plug, level: 0x00, kind: .relay) == "1A.2B.3C is off.")
    #expect(ControlText.status(plug, level: 0x80, kind: nil) == "1A.2B.3C is on at 50% (level 0x80).")
    #expect(ControlText.status(plug, level: 0x00, kind: .dimmer) == "1A.2B.3C is off (level 0x00).")

  }

  // MARK: - Record data

  @Test func explainsARecordsDataWithTheGroupType() {

    let text = LinkDataText.explanation(
      data: [0xFF, 0x1F, 0x01],
      bytes: ExampleCatalog.load.linkData.responder,
      tables: ExampleCatalog.commands.valueTables
    )

    #expect(text == "On-level 0xFF (On), Ramp rate 0x1F")
    #expect(LinkDataText.explanation(data: [0xFF, 0x1F, 0x01], bytes: [], tables: []) == nil)

  }

  // MARK: - Linking instructions

  @Test func givesTheDevicesOwnStepsOnly() throws {

    let unlinking = try #require(ExampleCatalog.plug.lifecycle?.unlinking)

    #expect(LinkingInstructions.steps(of: unlinking) == [
      "Hold the SET button until it beeps.",
      "Hold it again until it beeps again. [LED blinks red]",
    ])

  }

  // The device is the controller when the modem responds, so it goes first, then Return
  // starts the modem: one instruction, not two.
  @Test func asksForTheDeviceFirstWhenTheModemResponds() {

    let lines = LinkingInstructions.deviceFirst(
      .unlinking,
      device: "1A.2B.3C",
      steps: ["Hold the SET button until it beeps.", "Hold it again until it beeps again."],
      waitsForReturn: true
    )

    #expect(lines == [
      "First put 1A.2B.3C into unlinking mode:",
      "  1. Hold the SET button until it beeps.",
      "  2. Hold it again until it beeps again.",
      "Then press Return, and the modem joins as its responder.",
    ])

    let generic = LinkingInstructions.deviceFirst(.linking, device: nil, steps: [], waitsForReturn: false)

    #expect(generic.count == 2)
    #expect(generic[0].hasPrefix("First put the device into linking mode"))
    #expect(generic.filter { $0.contains("SET button") }.count == 1)

  }

  @Test func asksForTheSETButtonOnceTheModemIsReady() {

    let lines = LinkingInstructions.modemFirst(.linking, group: 0, seconds: 240, device: nil, steps: [])

    #expect(lines == [
      "The modem is in linking mode for group 0.",
      "Now press and hold the SET button of the device until it beeps or its light blinks.",
      "Waiting up to 240 seconds; Control-C stops.",
    ])

  }

  // MARK: - Unexpected links

  @Test func explainsADeviceInTheWrongMode() throws {

    let relinked = AllLinkingCompleted(linkCode: 0x00, group: 1, address: plug, category: nil, subcategory: nil, firmwareVersion: nil)
    let removed = AllLinkingCompleted(linkCode: 0xFF, group: 0, address: plug, category: nil, subcategory: nil, firmwareVersion: nil)

    let wrongMode = try #require(LinkOutcome.mismatch(relinked, mode: .unlinking, device: nil))

    #expect(wrongMode.contains("it was in linking mode, not unlinking mode"))
    #expect(try #require(LinkOutcome.mismatch(removed, mode: .linking, device: plug)).contains("it was in unlinking mode"))
    #expect(LinkOutcome.mismatch(removed, mode: .unlinking, device: plug) == nil)
    #expect(LinkOutcome.mismatch(relinked, mode: .linking, device: nil) == nil)

  }

  @Test func refusesALinkWithAnotherDevice() throws {

    let other = AllLinkingCompleted(linkCode: 0x01, group: 0, address: InsteonAddress(0x4D, 0x5E, 0x6F), category: nil, subcategory: nil, firmwareVersion: nil)
    let message = try #require(LinkOutcome.mismatch(other, mode: .linking, device: plug))

    #expect(message.hasPrefix("The modem reported 4D.5E.6F, not 1A.2B.3C"))

  }

  // MARK: - watch

  @Test func namesSETButtonPressed() {

    let pressed = SetButtonPressed(sender: plug, role: .responder, category: 0x02, subcategory: 0x7A, firmwareVersion: 0x41)

    #expect(
      WatchText.setButtonPressed(pressed, productName: "Example Plug 9001")
        == "1A.2B.3C SET button pressed (cmd1 0x01, links as a responder); identified as Example Plug 9001"
    )
    #expect(WatchText.setButtonPressed(pressed, productName: nil).hasSuffix("identified as category 0x02, subcategory 0x7A, firmware 0x41"))

  }

  @Test func printsAMessagesFrame() throws {

    let standard = ReceivedMessage(
      sender: plug,
      destination: InsteonAddress(0x02, 0x7A, 0x41),
      flags: MessageFlags(rawValue: 0x8F),
      command: Command(command1: 0x01, command2: 0x00)
    )

    #expect(RawFrame.text(of: standard) == "0250 1A2B3C 027A41 8F 01 00")

    var extended = standard
    extended.flags = MessageFlags(rawValue: 0x1F)
    extended.userData = try UserData([UInt8](repeating: 0x00, count: 13) + [0xD2])

    #expect(RawFrame.bytes(of: extended).count == 25)
    #expect(RawFrame.text(of: extended).hasPrefix("0251 1A2B3C 027A41 1F 01 00 0000"))
    #expect(RawFrame.text(of: extended).hasSuffix("D2"))

  }

  // MARK: - discover

  @Test func namesHowAHubWasFound() {

    #expect(DiscoveryMethod.local.label == "local network")
    #expect(DiscoveryMethod.insteonConnect.label == "Insteon Connect")
    #expect(DiscoveryMethod.insteonConnect.rawValue == "insteonConnect")

  }

}
