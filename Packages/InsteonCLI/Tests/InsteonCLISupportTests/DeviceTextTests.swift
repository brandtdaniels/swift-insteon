import Foundation
import Testing
import InsteonCLISupport
@_spi(Catalog) import InsteonCore
import InsteonDeviceCatalog
import InsteonProtocol

/// A made-up catalog with one on/off plug, whose model and identity no real product has.
enum ExampleCatalog {

  static let identity = ReportedIdentity(category: 0x02, subcategory: 0x7A, firmwareVersion: 0x41)

  static let load = GroupType(
    name: "load",
    label: "Load",
    kind: .relay,
    linkData: GroupType.LinkData(responder: [
      LinkDataByte(position: 1, name: "onLevel", label: "On-level", summary: "The on-level.", value: 0xFF, table: "onOff"),
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

  // MARK: - Described devices

  @Test func describesAKnownIdentityWithTheCatalog() {

    let identity = ExampleCatalog.identity
    let device = DeviceDescription(category: identity.category, subcategory: identity.subcategory, firmwareVersion: identity.firmwareVersion, catalog: ExampleCatalog.catalog)

    #expect(device.displayName == "Example Plug 9001 (ExampleLinc)")
    #expect(device.mainGroupType?.kind == .relay)

  }

  // MARK: - Control

  // These pin the command's wording, which people and scripts read.

  @Test func pinsTheWordingOfTurningOn() {

    #expect(DeviceText.turnedOn(plug, result: DeviceTurnOnResult(group: 1, level: nil, ignoredLevel: 50)) == "1A.2B.3C is on/off only; turned it on.")
    #expect(DeviceText.turnedOn(plug, result: DeviceTurnOnResult(group: 1, level: nil, ignoredLevel: 100)) == "Turned 1A.2B.3C on.")
    #expect(DeviceText.turnedOn(plug, result: DeviceTurnOnResult(group: 1, level: nil, ignoredLevel: nil)) == "Turned 1A.2B.3C on.")
    #expect(DeviceText.turnedOn(plug, result: DeviceTurnOnResult(group: 1, level: 50, ignoredLevel: nil)) == "Turned 1A.2B.3C on at 50%.")

  }

  @Test func pinsTheWordingOfTurningOff() {

    #expect(DeviceText.turnedOff(plug) == "Turned 1A.2B.3C off.")

  }

  @Test func pinsTheWordingOfAnInstantChange() {

    #expect(DeviceText.changedInstantly(plug, result: DeviceInstantChangeResult(group: 1, level: 50, isOnOffOnly: false, isCommandDescribed: true)) == "Changed 1A.2B.3C to 50% at once.")
    #expect(DeviceText.changedInstantly(plug, result: DeviceInstantChangeResult(group: 1, level: 0, isOnOffOnly: true, isCommandDescribed: true)) == "Turned 1A.2B.3C off.")
    #expect(DeviceText.changedInstantly(plug, result: DeviceInstantChangeResult(group: 1, level: 100, isOnOffOnly: true, isCommandDescribed: true)) == "Turned 1A.2B.3C on.")
    #expect(DeviceText.changedInstantly(plug, result: DeviceInstantChangeResult(group: 1, level: 40, isOnOffOnly: true, isCommandDescribed: true)) == "1A.2B.3C is on/off only; turned it on.")
    #expect(DeviceText.undescribedCommandNote("Light On Fast") == "The Insteon device catalog doesn't describe this device's commands; sending Light On Fast anyway.")

  }

  @Test func pinsTheWordingOfStatus() {

    let on = DeviceStatus(group: 1, value: 0xFF, allLinkDatabaseDelta: 0x00, reading: .onOff(true), isOn: true)
    let off = DeviceStatus(group: 1, value: 0x00, allLinkDatabaseDelta: 0x00, reading: .onOff(false), isOn: false)
    let half = DeviceStatus(group: 1, value: 0x80, allLinkDatabaseDelta: 0x00, reading: .percent(50), isOn: true)
    let dark = DeviceStatus(group: 1, value: 0x00, allLinkDatabaseDelta: 0x00, reading: .percent(0), isOn: false)

    #expect(DeviceText.status(plug, status: on) == "1A.2B.3C is on.")
    #expect(DeviceText.status(plug, status: off) == "1A.2B.3C is off.")
    #expect(DeviceText.status(plug, status: half) == "1A.2B.3C is on at 50% (level 0x80).")
    #expect(DeviceText.status(plug, status: dark) == "1A.2B.3C is off (level 0x00).")

  }

  @Test func pinsTheWordingOfBeep() {

    #expect(DeviceText.beeped(plug) == "1A.2B.3C beeped.")
    #expect(DeviceText.unlistedBeepNote == "The Insteon device catalog doesn't list Beep for this device; sending anyway.")
    #expect(DeviceText.beepRejected(plug, reason: .notLinked) == "1A.2B.3C rejected Beep (NAK): it isn't linked to the modem.")
    #expect(DeviceText.beepUnanswered(plug) == "1A.2B.3C didn't answer Beep. Check that it's powered and in range.")

  }

  @Test func wordsADeviceThatIsntLinkedAsTheModemsNAKIs() {

    #expect(DeviceText.failure(.notLinked, device: plug) == "Device 1A.2B.3C rejected the command: it isn't linked to the modem.")
    #expect(DeviceText.failure(.unsupported(.turnOnFast, product: "Example Plug 9001"), device: plug) == "The Insteon device catalog doesn't list Light On Fast for Example Plug 9001.")

  }

  // MARK: - Record data

  @Test func writesARecordsMeaning() throws {

    let identity = ExampleCatalog.identity
    let device = DeviceInfo(catalogDescription: ExampleCatalog.catalog.describe(category: identity.category, subcategory: identity.subcategory, firmwareVersion: identity.firmwareVersion))
    let record = LinkRecord(isController: false, isInUse: true, group: 0, address: plug, data: [0xFF, 0x1F, 0x01])
    let explanation = try #require(device.meaning(of: record))

    #expect(LinkDataText.meaning(of: explanation) == "On-level 0xFF (On), Ramp rate 0x1F")

    // A byte without a label goes by its name, and the responder's own group says so.
    let perGroup = LinkDataMeaning(bytes: [LinkDataField(position: 3, name: "button", value: 0x03, isPerGroup: true)])

    #expect(LinkDataText.meaning(of: perGroup) == "button 0x03 (its group 3)")

  }

  @Test func saysWhenARecordsByteDiffersFromTheDocuments() throws {

    let identity = ExampleCatalog.identity
    let device = DeviceInfo(catalogDescription: ExampleCatalog.catalog.describe(category: identity.category, subcategory: identity.subcategory, firmwareVersion: identity.firmwareVersion))
    let record = LinkRecord(isController: false, isInUse: true, group: 0, address: plug, data: [0x00, 0x1F, 0x01])
    let explanation: LinkDataMeaning = try #require(device.meaning(of: record))

    #expect(explanation.bytes[0].documentedValue == 0xFF)
    #expect(explanation.bytes[1].documentedValue == nil)
    #expect(LinkDataText.meaning(of: explanation) == "On-level 0x00 (Off; the catalog gives 0xFF), Ramp rate 0x1F")

    // A byte without a table gives the documented value alone.
    let untabled = LinkDataMeaning(bytes: [LinkDataField(position: 1, name: "onLevel", label: "On-level", value: 0x00, documentedValue: 0xFE)])

    #expect(LinkDataText.meaning(of: untabled) == "On-level 0x00 (the catalog gives 0xFE)")

  }

  @Test func saysAControllerRecordIsNotDocumented() {

    #expect(LinkDataText.column(meaning: "Ramp rate 0x1F", isController: false, isDeviceInCatalog: true) == "Ramp rate 0x1F")
    #expect(LinkDataText.column(meaning: nil, isController: true, isDeviceInCatalog: true) == "not documented")
    #expect(LinkDataText.column(meaning: nil, isController: true, isDeviceInCatalog: false) == "")
    #expect(LinkDataText.column(meaning: nil, isController: false, isDeviceInCatalog: true) == "")

  }

  // MARK: - scene

  @Test func trustsTheModemsCleanupReportWithoutAcknowledgments() {

    let other = InsteonAddress(0x4D, 0x5E, 0x6F)

    #expect(SceneText.cleanup(acknowledged: [], unacknowledged: [], isComplete: true) == [
      "The modem reports every responder answered its cleanup.",
    ])
    #expect(SceneText.cleanup(acknowledged: [plug, other], unacknowledged: [], isComplete: true) == [
      "2 devices acknowledged the cleanup.",
    ])
    #expect(SceneText.cleanup(acknowledged: [], unacknowledged: [other], isComplete: true) == [
      "The modem reports every other responder answered its cleanup.",
      "Didn't acknowledge: 4D.5E.6F.",
    ])
    #expect(SceneText.cleanup(acknowledged: [plug], unacknowledged: [other], isComplete: false) == [
      "1 device acknowledged the cleanup.",
      "Didn't acknowledge: 4D.5E.6F.",
      "The modem says it didn't reach every responder.",
    ])
    // With no responders listed, the modem's report says nothing about them.
    #expect(SceneText.cleanup(acknowledged: [], unacknowledged: [], isComplete: true, responderCount: 0) == [])
    #expect(SceneText.cleanup(acknowledged: [], unacknowledged: [], isComplete: false) == [
      "The modem says it didn't reach every responder.",
    ])

  }

  // MARK: - Linking instructions

  @Test func givesTheDevicesOwnStepsOnly() {

    let unlinking = Instructions(steps: [
      InstructionStep(text: "Press the Hub's button.", isOnOtherDevice: true),
      InstructionStep(text: "Hold the SET button until it beeps."),
      InstructionStep(text: "Hold it again until it beeps again.", expectation: "LED blinks red"),
    ])

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

  @Test func namesADeviceByItsProductsNameAndModel() {

    let info = DeviceInfo(catalogDescription: ExampleCatalog.catalog.describe(category: 0x02, subcategory: 0x7A, firmwareVersion: nil))

    #expect(LinkingInstructions.deviceLabel(plug, info: info) == "1A.2B.3C (Example Plug 9001)")
    #expect(LinkingInstructions.deviceLabel(plug, info: nil) == "1A.2B.3C")

    let lines: [String] = LinkingInstructions.modemFirst(
      .unlinking,
      group: 1,
      seconds: 240,
      device: LinkingInstructions.deviceLabel(plug, info: info),
      steps: ["Hold the SET button until it beeps."]
    )

    #expect(lines[1] == "Now, on 1A.2B.3C (Example Plug 9001):")

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
      WatchText.setButtonPressed(DeviceSetButtonPress(pressed, productName: "Example Plug 9001"))
        == "1A.2B.3C SET button pressed (cmd1 0x01, links as a responder); identified as Example Plug 9001"
    )
    #expect(
      WatchText.setButtonPressed(DeviceSetButtonPress(pressed, productName: nil))
        .hasSuffix("identified as category 0x02, subcategory 0x7A, firmware 0x41")
    )

  }

  @Test func printsAMessagesFrame() throws {

    let standard = ReceivedMessage(
      sender: plug,
      destination: InsteonAddress(0x02, 0x7A, 0x41),
      flags: MessageFlags(rawValue: 0x8F),
      command: Command(command1: 0x01, command2: 0x00)
    )

    #expect(RawFrame.text(of: standard.modemFrame) == "0250 1A2B3C 027A41 8F 01 00")

    var extended = standard
    extended.flags = MessageFlags(rawValue: 0x1F)
    extended.userData = try UserData([UInt8](repeating: 0x00, count: 13) + [0xD2])

    #expect(RawFrame.text(of: extended.modemFrame).hasPrefix("0251 1A2B3C 027A41 1F 01 00 0000"))
    #expect(RawFrame.text(of: extended.modemFrame).hasSuffix("D2"))
    #expect(RawFrame.text(of: [0x02, 0x50, 0x1A]) == "0250 1A")

  }

  @Test func printsWhatTheMonitorHeard() {

    let modem = InsteonAddress(0x11, 0x22, 0x33)
    let wet = DeviceGroupCommand(device: plug, group: 2, command1: 0x11, commandName: "Light On", event: "wet", isOn: true, productName: nil)
    let unnamed = DeviceGroupCommand(device: plug, group: 1, command1: 0x13, commandName: "Light Off", event: nil, isOn: false, productName: nil)
    let acknowledgment = ReceivedMessage(
      sender: plug,
      destination: modem,
      flags: MessageFlags(messageType: .directAcknowledgment),
      command: Command(command1: 0x11, command2: 0xFF)
    )

    let events: [DeviceMonitorEvent] = [
      .identified(plug, productName: "Example Plug 9001"),
      .identified(plug, productName: nil),
      .groupCommand(wet),
      .groupCommand(unnamed),
      .heartbeat(plug, group: 4),
      .heartbeatBroadcast(plug, batteryLevel: 0x5A),
      .statusChanged(plug),
      .message(DeviceMessageSummary(acknowledgment)),
      .modem(.allLinkingCompleted(plug, group: 1, modemRole: "controller")),
      .modem(.allLinkingCompleted(plug, group: 1, modemRole: nil)),
      .modem(.userReset),
      .modem(.allLinkCleanupFailed(plug, group: 3)),
      .rawMessage([0x02, 0x50, 0x1A, 0x2B, 0x3C, 0x11, 0x22, 0x33, 0x2F, 0x11, 0xFF]),
      .rawReply(kind: "ALL-Link record")
    ]
    let lines: [String] = events.map { (event: DeviceMonitorEvent) -> String in WatchText.line(for: event) }

    #expect(lines == [
      "1A.2B.3C identified as Example Plug 9001",
      "1A.2B.3C reported an identity the Insteon device catalog doesn't have",
      "1A.2B.3C group 2: wet",
      "1A.2B.3C group 1: cmd1 0x13 (Light Off)",
      "1A.2B.3C heartbeat, group 4",
      "1A.2B.3C heartbeat, battery level 0x5A",
      "1A.2B.3C status changed; ask with 'insteon device 1A.2B.3C status'",
      "1A.2B.3C to 11.22.33: ACK, cmd1 0x11 (Light On) cmd2 0xFF",
      "ALL-Linking completed with 1A.2B.3C in group 1, modem controller",
      "ALL-Linking completed with 1A.2B.3C in group 1, modem unknown",
      "The modem was reset to factory defaults with its SET button",
      "1A.2B.3C didn't acknowledge the ALL-Link cleanup for group 3",
      "raw  0250 1A2B3C 112233 2F 11 FF",
      "raw  modem reply: ALL-Link record"
    ])

  }

  // MARK: - discover

  @Test func namesHowAHubWasFound() {

    #expect(DiscoveryMethod.local.label == "local network")
    #expect(DiscoveryMethod.insteonConnect.label == "Insteon Connect")
    #expect(DiscoveryMethod.insteonConnect.rawValue == "insteonConnect")

  }

}
