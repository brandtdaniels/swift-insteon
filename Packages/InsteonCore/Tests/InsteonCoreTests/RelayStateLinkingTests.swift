import Foundation
import Testing
@testable import InsteonCore
import InsteonDeviceCatalog
import InsteonLinking
import InsteonLinkingTestSupport
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// Made-up devices to link with a chosen relay state: a relay whose catalog lets linking change
/// its made-up pulse flag, one whose catalog doesn't, and a dimmer, whose main group isn't a
/// relay. No name, category or flag here is a real product's.
enum RelayExample {

  static let module = InsteonAddress(0x4A, 0x5B, 0x01)

  static let fixedModule = InsteonAddress(0x4A, 0x5B, 0x02)

  static let dimmer = InsteonAddress(0x4A, 0x5B, 0x03)

  static let stranger = InsteonAddress(0x4A, 0x5B, 0x04)

  /// A module whose catalog gives a command that turns pulse off but none that turns it
  /// back on.
  static let oneWayModule = InsteonAddress(0x4A, 0x5B, 0x05)

  static let oneWayModuleIdentity = ReportedIdentity(category: 0x7A, subcategory: 0x63, firmwareVersion: 0x41)

  /// A module whose relay group type gives no Off.
  static let noOffModule = InsteonAddress(0x4A, 0x5B, 0x06)

  static let noOffModuleIdentity = ReportedIdentity(category: 0x7A, subcategory: 0x64, firmwareVersion: 0x41)

  /// A module whose relay group type gives no On.
  static let noOnModule = InsteonAddress(0x4A, 0x5B, 0x07)

  static let noOnModuleIdentity = ReportedIdentity(category: 0x7A, subcategory: 0x65, firmwareVersion: 0x41)

  /// A module whose catalog gives a command that turns pulse on but none that turns it
  /// off, so clearing it is refused before anything is sent.
  static let noClearModule = InsteonAddress(0x4A, 0x5B, 0x08)

  static let noClearModuleIdentity = ReportedIdentity(category: 0x7A, subcategory: 0x66, firmwareVersion: 0x41)

  static let moduleIdentity = ReportedIdentity(category: 0x7A, subcategory: 0x60, firmwareVersion: 0x41)

  static let fixedModuleIdentity = ReportedIdentity(category: 0x7A, subcategory: 0x61, firmwareVersion: 0x41)

  static let dimmerIdentity = ReportedIdentity(category: 0x7B, subcategory: 0x62, firmwareVersion: 0x41)

  /// The pulse flag's bit, and its Set Operating Flags cmd2 values. While it's on, the relay
  /// doesn't hold a state.
  static let pulse: (bit: UInt8, on: UInt8, off: UInt8) = (0x08, 0x06, 0x07)

  /// The flag that, with pulse on, makes both On and Off only pulse the relay.
  static let pulseBoth: (bit: UInt8, on: UInt8, off: UInt8) = (0x10, 0x12, 0x13)

  static let operatingFlags: [OperatingFlag] = [
    OperatingFlag(name: "pulse", summary: "The relay closes, then returns to off by itself.", query: .operatingFlags, bit: pulse.bit, on: pulse.on, off: pulse.off, label: "Pulse"),
    OperatingFlag(
      name: "pulseBoth",
      summary: "Both On and Off pulse the relay.",
      query: .operatingFlags,
      bit: pulseBoth.bit,
      on: pulseBoth.on,
      off: pulseBoth.off,
      label: "Pulse on both"
    )
  ]

  static let readStatus = DeviceStandardCommand(
    name: "readStatus",
    summary: "Reads whether the relay is on.",
    command1: 0x19,
    command2: .fixed(0x00),
    reply: MessageField(name: "relayState", summary: "0x00 when off.", location: .command2),
    effect: .readOnly, isIdempotent: true
  )

  static let relay = GroupType(
    name: "relay",
    label: "Relay",
    kind: .relay,
    state: GroupType.State(
      command: "readStatus",
      ranges: [
        GroupType.State.Range(values: 0x00...0x00, label: "Off"),
        GroupType.State.Range(values: 0x01...0xFF, label: "On")
      ]
    ),
    actions: [
      GroupType.Action(name: "on", label: "On", command: "lightOn", value: 0xFF),
      GroupType.Action(name: "off", label: "Off", command: "lightOff")
    ],
    stateHolding: holding
  )

  /// How the relay holds a state: pulse keeps it from holding one, it returns to off, and with
  /// pulseBoth on too, every On and Off only pulses it.
  static let holding = GroupType.StateHolding(releasedBy: ["pulse"], restState: "off", pulsesOnEveryCommandWhen: [["pulse", "pulseBoth"]])

  static func moduleCommands(id: CommandSetID, linkingChanges: [LinkingChange], flags: [OperatingFlag] = operatingFlags, relayType: GroupType = relay) -> CommandSet {

    CommandSet(
      id: id,
      name: "Example pulse relay",
      summary: "A relay that can pulse.",
      operatingFlags: flags,
      standardCommands: [ControlExample.lightOn, ControlExample.lightOff, readStatus],
      groupTypes: [relayType],
      linkingChanges: linkingChanges
    )

  }

  static let commands: CommandSet = moduleCommands(id: "exampleIO", linkingChanges: [LinkingChange(flag: "pulse")])

  static let fixedCommands: CommandSet = moduleCommands(id: "exampleFixedIO", linkingChanges: [])

  static let oneWayCommands: CommandSet = moduleCommands(
    id: "exampleOneWayIO",
    linkingChanges: [LinkingChange(flag: "pulse")],
    flags: [OperatingFlag(name: "pulse", summary: "The relay closes, then returns to off by itself.", query: .operatingFlags, bit: pulse.bit, off: pulse.off, label: "Pulse"), operatingFlags[1]]
  )

  /// The relay group type with only the action named.
  static func relay(onlyAction name: SettingName) -> GroupType {

    var type: GroupType = relay

    type.actions = relay.actions.filter { (action: GroupType.Action) -> Bool in action.name == name }

    return type

  }

  static let noOffCommands: CommandSet = moduleCommands(id: "exampleNoOffIO", linkingChanges: [LinkingChange(flag: "pulse")], relayType: relay(onlyAction: "on"))

  static let noOnCommands: CommandSet = moduleCommands(id: "exampleNoOnIO", linkingChanges: [LinkingChange(flag: "pulse")], relayType: relay(onlyAction: "off"))

  static let noClearCommands: CommandSet = moduleCommands(
    id: "exampleNoClearIO",
    linkingChanges: [LinkingChange(flag: "pulse")],
    flags: [OperatingFlag(name: "pulse", summary: "The relay closes, then returns to off by itself.", query: .operatingFlags, bit: pulse.bit, on: pulse.on, label: "Pulse"), operatingFlags[1]]
  )

  static let dimmerCommands = CommandSet(
    id: "exampleRelayDimmer",
    name: "Example dimmer",
    summary: "A dimmer.",
    standardCommands: [ControlExample.lightOn, ControlExample.lightOff, ControlExample.readLevel],
    groupTypes: [ControlExample.light]
  )

  static func profile(_ model: ProductModel, _ identity: ReportedIdentity, commands: CommandSet, type: SettingName, lifecycle: DeviceLifecycle? = nil) -> DeviceProfile {

    DeviceProfile(
      model: model,
      name: "Example \(model)",
      identities: [DeviceIdentity(category: identity.category, subcategory: identity.subcategory)],
      engines: [DeviceEngine(engine: .i2cs, category: identity.category, subcategory: identity.subcategory)],
      commandSets: [CommandSetEntry(commandSet: commands.id, category: identity.category, subcategory: identity.subcategory)],
      groups: [DeviceProfile.Group(number: 1, name: "Sensor and relay", role: .both, type: type)],
      lifecycle: lifecycle
    )

  }

  /// A relay like the module whose catalog also gives its links to a Hub: the modem controls
  /// its group 1 in group 0, and responds to it in group 1.
  static let leggedModuleIdentity = ReportedIdentity(category: 0x7A, subcategory: 0x67, firmwareVersion: 0x41)

  static let hubLegs = DeviceLifecycle(fromHub: DeviceLifecycle.HubLinking(legs: [
    DeviceLifecycle.HubLinking.Leg(modemRole: .controller, modemGroup: 0x00, deviceGroup: 0x01),
    DeviceLifecycle.HubLinking.Leg(modemRole: .responder, modemGroup: 0x01, deviceGroup: 0x01)
  ]))

  static let catalog = DeviceCatalog(
    profiles: [
      profile("9601", moduleIdentity, commands: commands, type: "relay"),
      profile("9602", fixedModuleIdentity, commands: fixedCommands, type: "relay"),
      profile("9603", dimmerIdentity, commands: dimmerCommands, type: "light"),
      profile("9604", oneWayModuleIdentity, commands: oneWayCommands, type: "relay"),
      profile("9605", noOffModuleIdentity, commands: noOffCommands, type: "relay"),
      profile("9606", noOnModuleIdentity, commands: noOnCommands, type: "relay"),
      profile("9607", noClearModuleIdentity, commands: noClearCommands, type: "relay"),
      profile("9608", leggedModuleIdentity, commands: commands, type: "relay", lifecycle: hubLegs)
    ],
    commandSets: [commands, fixedCommands, dimmerCommands, oneWayCommands, noOffCommands, noOnCommands, noClearCommands]
  )

  static let identities: [InsteonAddress: ReportedIdentity] = [
    module: moduleIdentity,
    fixedModule: fixedModuleIdentity,
    dimmer: dimmerIdentity,
    oneWayModule: oneWayModuleIdentity,
    noOffModule: noOffModuleIdentity,
    noOnModule: noOnModuleIdentity,
    noClearModule: noClearModuleIdentity
  ]

}

/// Linking a relay with a chosen state, on an in-memory modem.
@Suite(.timeLimit(.minutes(1)))
struct RelayStateLinkingTests {

  let clock: TestClock = TestClock()

  let times: FixedTimes = FixedTimes()

  let module: InsteonAddress = RelayExample.module

  func network(
    _ modem: InMemoryModem,
    catalog: DeviceCatalog = RelayExample.catalog,
    identities: [InsteonAddress: ReportedIdentity] = RelayExample.identities
  ) -> DeviceNetwork {

    let times: FixedTimes = self.times

    return DeviceNetwork(
      modem: modem,
      catalog: catalog,
      snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: identities)),
      clock: clock,
      now: { () -> Date in times.now() }
    )

  }

  /// A modem whose device carries out its flag commands, with the flags and relay given.
  func modem(_ device: InsteonAddress = RelayExample.module, flags: UInt8, relay level: UInt8 = 0x00) async -> InMemoryModem {

    let modem = InMemoryModem()

    await modem.setEngine(.i2cs, of: device)
    await modem.setOperatingFlags(flags, of: device)
    await modem.setLevel(level, of: device)

    for flag in [RelayExample.pulse, RelayExample.pulseBoth] {

      await modem.setOperatingFlagCommand(flag.on, bit: flag.bit, isSet: true, of: device)
      await modem.setOperatingFlagCommand(flag.off, bit: flag.bit, isSet: false, of: device)

    }

    await modem.setPulsingBit(RelayExample.pulse.bit, of: device)

    return modem

  }

  func step(_ command1: UInt8, _ command2: UInt8, extended: Bool = false, to device: InsteonAddress = RelayExample.module) -> InMemoryModem.LinkingStep {

    .device(device, Command(command1: command1, command2: command2), isExtended: extended)

  }

  /// The commands that change a relay or a flag, or link: none of them may be sent when a
  /// relay state is refused.
  func changes(in steps: [InMemoryModem.LinkingStep]) -> [InMemoryModem.LinkingStep] {

    steps.filter { (step: InMemoryModem.LinkingStep) -> Bool in

      switch step {
      case let .device(_, command, _):
        return [0x11, 0x13, 0x20, 0x09].contains(command.command1)
      case .modem, .cancel:
        return true
      }

    }

  }

  /// Whether a step sends Set Operating Flags.
  func writesFlags(_ steps: [InMemoryModem.LinkingStep]) -> Bool {

    steps.contains { (step: InMemoryModem.LinkingStep) -> Bool in

      if case let .device(_, command, _) = step {

        return command.command1 == 0x20

      }

      return false

    }

  }

  /// The steps that put the relay back and set the pulse flag back, in order.
  var returnAndRestore: [InMemoryModem.LinkingStep] {

    [step(0x13, 0x00), step(0x20, RelayExample.pulse.on, extended: true), step(0x1F, 0x00)]

  }

  /// A status request: the one the network's cache sends for the database delta before it
  /// reads the relay's database to check its record, the last step of a link that checks it,
  /// and the one that checks a relay before it's switched back.
  var statusRequest: InMemoryModem.LinkingStep {

    step(0x19, 0x00)

  }

  /// Links the module with a relay state.
  func linkRelay(
    _ modem: InMemoryModem,
    _ state: RelayState,
    device: InsteonAddress = RelayExample.module,
    observer: LinkingRecorder = LinkingRecorder()
  ) async throws -> DeviceLinkingResult {

    try await network(modem).linking.linkRelay(device, recording: state, group: 2, twoWay: .never, observer: observer)

  }

  /// Expects a relay state error that `matches` accepts.
  func expectRefusal(
    _ body: () async throws -> Void,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ matches: (RelayStateLinkingError) -> Bool
  ) async {

    do {

      try await body()
      Issue.record("Expected a relay state error", sourceLocation: sourceLocation)

    } catch let error as RelayStateLinkingError {

      #expect(matches(error), "\(error)", sourceLocation: sourceLocation)

    } catch {

      Issue.record("Expected a relay state error, got \(error)", sourceLocation: sourceLocation)

    }

  }

  // MARK: - Linking with a relay state

  @Test func clearsPulseSetsTheRelayLinksVerifiesAndPutsItAllBack() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.pulse.bit)
    let recorder = LinkingRecorder()

    let result: DeviceLinkingResult = try await linkRelay(modem, .on, observer: recorder)

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    // The flags and status are read, the flag cleared and read back, the relay set and
    // confirmed, then the link is made, the relay put back and the flag set back.
    #expect(Array(steps.prefix(6)) == [
      step(0x1F, 0x00),
      step(0x19, 0x00),
      step(0x20, RelayExample.pulse.off, extended: true),
      step(0x1F, 0x00),
      step(0x11, 0xFF),
      step(0x19, 0x00)
    ])
    #expect(steps.dropFirst(6).dropLast(3).contains(.modem(.controller, 0x02)))
    // The record is checked after everything is put back.
    #expect(Array(steps.suffix(4)) == returnAndRestore + [statusRequest])
    // The device recorded on, and the relay is off again, as it was.
    #expect(await modem.databases[module]?.values.first?.data1 == 0xFF)
    #expect(await modem.levels[module] == 0x00)
    #expect(await modem.operatingFlags[module] == RelayExample.pulse.bit)
    #expect(result.links.map(\.mode) == [.controller])

    let link: RelayStateLink? = result.relayState

    #expect(link?.groupOn == .on)
    #expect(link?.groupOff == .off)
    #expect(link?.recordedData1 == 0xFF)
    #expect(link?.recordFailure == nil)
    #expect(link?.clearedFlags.map(\.name) == ["pulse"])
    #expect(link?.isRestored == true)
    #expect(link?.holding.holdsState == false)
    #expect(link?.restoreFailures.isEmpty == true)
    #expect(await recorder.lines == [
      "relay state: clearing pulse \(module)",
      "relay state: setting \(module) on",
      "relay state: \(module) confirmed on",
      "linking remotely \(module) as controller",
      "linked \(module) group 2 controller first",
      "relay state: returning \(module) off",
      "relay state: restoring pulse \(module)",
      "relay state: restored pulse \(module)",
      "relay state: group on gives on, off gives off, holds false, ignores false"
    ])

  }

  @Test func sendsNothingAndWritesNoFlagForAPulsingRelayAlreadyOff() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.pulse.bit)
    let recorder = LinkingRecorder()

    let result: DeviceLinkingResult = try await linkRelay(modem, .off, observer: recorder)

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    #expect(Array(steps.prefix(2)) == [step(0x1F, 0x00), step(0x19, 0x00)])
    #expect(!writesFlags(steps))
    #expect(!steps.contains(step(0x13, 0x00)))
    #expect(!steps.contains(step(0x11, 0xFF)))
    #expect(result.relayState?.clearedFlags.isEmpty == true)
    #expect(result.relayState?.isRestored == nil)
    #expect(result.relayState?.recordedData1 == 0x00)
    #expect(Array(await recorder.lines.prefix(1)) == ["relay state: \(module) already off"])

  }

  @Test func recordsOffSoAGroupOffTurnsTheRelayOn() async throws {

    let modem: InMemoryModem = await modem(flags: 0x00, relay: 0xFF)

    let result: DeviceLinkingResult = try await linkRelay(modem, .off)

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    #expect(steps.contains(step(0x13, 0x00)))
    #expect(!writesFlags(steps))
    // A relay that holds a state keeps the state it was linked in.
    #expect(await modem.levels[module] == 0x00)
    #expect(await modem.databases[module]?.values.first?.data1 == 0x00)
    #expect(result.relayState?.groupOn == .off)
    #expect(result.relayState?.groupOff == .on)
    #expect(result.relayState?.holding.holdsState == true)

  }

  @Test func skipsTheCommandForARelayAlreadyInTheStateButConfirmsIt() async throws {

    let modem: InMemoryModem = await modem(flags: 0x00, relay: 0xFF)
    let recorder = LinkingRecorder()

    _ = try await linkRelay(modem, .on, observer: recorder)

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    #expect(Array(steps.prefix(2)) == [step(0x1F, 0x00), step(0x19, 0x00)])
    #expect(!steps.contains(step(0x11, 0xFF)))
    #expect(Array(await recorder.lines.prefix(1)) == ["relay state: \(module) already on"])

  }

  @Test func linksWithoutSwitchingAnythingWhenEveryCommandPulses() async throws {

    let flags: UInt8 = RelayExample.pulse.bit | RelayExample.pulseBoth.bit
    let modem: InMemoryModem = await modem(flags: flags)
    // Its pulse flag, whatever its name, doesn't make this relay pulse.
    await modem.setPulsingBit(0x80, of: module)
    let recorder = LinkingRecorder()

    let result: DeviceLinkingResult = try await linkRelay(modem, .on, observer: recorder)

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    // Only reads are sent besides the link: the mode ignores the state.
    #expect(Array(steps.prefix(2)) == [step(0x1F, 0x00), step(0x19, 0x00)])
    #expect(changes(in: steps).allSatisfy { (step: InMemoryModem.LinkingStep) -> Bool in

      if case let .device(_, command, _) = step {

        return command.command1 == 0x09

      }

      return true

    })
    #expect(await modem.operatingFlags[module] == flags)
    #expect(result.relayState?.ignoresState == true)
    #expect(result.relayState?.ignoresState == true)
    // The state wasn't applied, so nothing claims what a group On or Off does.
    #expect(result.relayState?.groupOn == nil)
    #expect(result.relayState?.groupOff == nil)
    #expect(result.relayState?.clearedFlags.isEmpty == true)
    #expect(result.relayState?.recordFailure == nil)
    #expect(Array(await recorder.lines.prefix(1)) == ["relay state: \(module) ignores the state, pulse and pulseBoth on"])

  }

  // MARK: - Planning

  @Test func plansWhatItWillSwitchAndSendsOnlyReads() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.pulse.bit)
    let linking: DeviceLinkingCoordinator = network(modem).linking

    let plan: RelayLinkPlan = try await linking.planRelayLink(module, recording: .on, observer: LinkingRecorder())

    #expect(plan.state == .on)
    #expect(plan.before == .off)
    #expect(plan.switchesRelay)
    #expect(plan.clearedFlags.map(\.name) == ["pulse"])
    #expect(plan.returnsToRestAfterLinking)
    #expect(!plan.switchesBackOnFailure)
    #expect(!plan.ignoresState)
    #expect(await modem.linkingSteps == [step(0x1F, 0x00), step(0x19, 0x00)])

  }

  @Test func refusesToLinkWhenTheRelayChangedSinceThePlan() async throws {

    let modem: InMemoryModem = await modem(flags: 0x00)
    let linking: DeviceLinkingCoordinator = network(modem).linking
    let plan: RelayLinkPlan = try await linking.planRelayLink(module, recording: .on, observer: LinkingRecorder())

    // Someone switches it on between the plan and the link.
    await modem.setLevel(0xFF, of: module)

    await expectRefusal({ _ = try await linking.linkRelay(plan, group: 2, twoWay: .never, observer: LinkingRecorder()) }) { (error: RelayStateLinkingError) -> Bool in

      guard case let .planChanged(old, new) = error else {

        return false

      }

      return old == plan && new.before == .on && !new.switchesRelay

    }

    #expect(await modem.linkingSteps == [step(0x1F, 0x00), step(0x19, 0x00), step(0x1F, 0x00), step(0x19, 0x00)])

  }

  @Test func refusesToSwitchARelayWhosePlanAskedNothing() async throws {

    let modem: InMemoryModem = await modem(flags: 0x00, relay: 0xFF)
    let linking: DeviceLinkingCoordinator = network(modem).linking
    let plan: RelayLinkPlan = try await linking.planRelayLink(module, recording: .on, observer: LinkingRecorder())

    #expect(!plan.switchesRelay)

    // Someone switches it off, so the link would switch a relay no one was asked about.
    await modem.setLevel(0x00, of: module)

    await expectRefusal({ _ = try await linking.linkRelay(plan, group: 2, twoWay: .never, observer: LinkingRecorder()) }) { (error: RelayStateLinkingError) -> Bool in

      if case .planChanged = error {

        return true

      }

      return false

    }

    #expect(changes(in: await modem.linkingSteps).isEmpty)

  }

  @Test func linksWithThePlanItWasGivenWhenNothingChanged() async throws {

    let modem: InMemoryModem = await modem(flags: 0x00)
    let linking: DeviceLinkingCoordinator = network(modem).linking
    let plan: RelayLinkPlan = try await linking.planRelayLink(module, recording: .on, observer: LinkingRecorder())

    let result: DeviceLinkingResult = try await linking.linkRelay(plan, group: 2, twoWay: .never, observer: LinkingRecorder())

    #expect(result.relayState?.recordedData1 == 0xFF)

  }

  @Test func plansNothingToSwitchForARelayAlreadyInTheStateOrOneThatOnlyPulses() async throws {

    let still: RelayLinkPlan = try await network(await modem(flags: 0x00, relay: 0xFF)).linking.planRelayLink(module, recording: .on, observer: LinkingRecorder())
    let latching: RelayLinkPlan = try await network(await modem(flags: 0x00)).linking.planRelayLink(module, recording: .on, observer: LinkingRecorder())
    let pulsing: RelayLinkPlan = try await network(await modem(flags: RelayExample.pulse.bit | RelayExample.pulseBoth.bit)).linking.planRelayLink(module, recording: .on, observer: LinkingRecorder())

    #expect(!still.switchesRelay)
    #expect(latching.switchesRelay)
    #expect(latching.switchesBackOnFailure)
    #expect(latching.clearedFlags.isEmpty)
    #expect(pulsing.ignoresState)
    #expect(!pulsing.switchesRelay)
    #expect(pulsing.clearedFlags.isEmpty)

    #expect(pulsing.holding.pulsingFlags.map(\.name) == ["pulse", "pulseBoth"])

  }

  // MARK: - A flag set that isn't one of the catalog's pulsing sets

  @Test func switchesARelayWithOnlyPulseBothOnAsOneThatHoldsItsState() async throws {

    // pulseBoth alone is no set the catalog says pulses, and no flag that releases the relay
    // is on, so it's an ordinary relay that holds its state.
    let modem: InMemoryModem = await modem(flags: RelayExample.pulseBoth.bit)
    let recorder = LinkingRecorder()
    let plan: RelayLinkPlan = try await network(modem).linking.planRelayLink(module, recording: .on, observer: LinkingRecorder())

    #expect(!plan.ignoresState)
    #expect(plan.holding.holdsState)
    #expect(plan.switchesRelay)
    #expect(plan.switchesBackOnFailure)
    #expect(plan.clearedFlags.isEmpty)

    let result: DeviceLinkingResult = try await linkRelay(modem, .on, observer: recorder)

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    #expect(steps.contains(step(0x11, 0xFF)))
    #expect(!writesFlags(steps))
    #expect(await modem.levels[module] == 0xFF)
    #expect(await modem.operatingFlags[module] == RelayExample.pulseBoth.bit)
    #expect(result.relayState?.groupOn == .on)
    #expect(result.relayState?.groupOff == .off)
    #expect(result.relayState?.recordFailure == nil)
    #expect(await recorder.lines.last == "relay state: group on gives on, off gives off, holds true, ignores false")

  }

  // MARK: - What the catalog doesn't say

  /// A catalog whose relay's type is the given one, at the module's identity.
  func catalog(relayType: GroupType, flags: [OperatingFlag] = RelayExample.operatingFlags) -> DeviceCatalog {

    let commands: CommandSet = RelayExample.moduleCommands(id: "exampleUndescribedRelay", linkingChanges: [LinkingChange(flag: "pulse")], flags: flags, relayType: relayType)

    return DeviceCatalog(profiles: [RelayExample.profile("9611", RelayExample.moduleIdentity, commands: commands, type: "relay")], commandSets: [commands])

  }

  /// The relay group type with how it holds a state replaced.
  func relay(holding: GroupType.StateHolding?) -> GroupType {

    var type: GroupType = RelayExample.relay

    type.stateHolding = holding

    return type

  }

  /// What a catalog that doesn't say how its relay holds a state is refused with.
  enum Undescribed: CaseIterable, Sendable {

    /// The catalog says nothing.
    case absent

    /// A rest state that isn't one of the relay's actions.
    case restState

    /// A flag the command set doesn't give.
    case flag

    /// A relay nothing releases whose pulsing set names a flag the command set doesn't give.
    case pulsingFlag

    /// A relay nothing releases whose rest state isn't one of its actions.
    case restStateOfAHoldingRelay

    var holding: GroupType.StateHolding? {

      switch self {
      case .absent:
        return nil
      case .restState:
        return GroupType.StateHolding(releasedBy: ["pulse"], restState: "closed")
      case .flag:
        return GroupType.StateHolding(releasedBy: ["pulse", "hum"], restState: "off")
      case .pulsingFlag:
        return GroupType.StateHolding(releasedBy: [], restState: "off", pulsesOnEveryCommandWhen: [["pulse", "hum"]])
      case .restStateOfAHoldingRelay:
        return GroupType.StateHolding(releasedBy: [], restState: "closed")
      }

    }

    func matches(_ error: RelayStateLinkingError) -> Bool {

      switch (self, error) {
      case let (.absent, .stateHoldingNotDescribed(device, product)):
        return device == RelayExample.module && product == "Example 9611 9611"
      case let (.restState, .restStateUnknown(device, action)):
        return device == RelayExample.module && action == "closed"
      case let (.flag, .stateHoldingFlagUnknown(device, flag)), let (.pulsingFlag, .stateHoldingFlagUnknown(device, flag)):
        return device == RelayExample.module && flag == "hum"
      case let (.restStateOfAHoldingRelay, .restStateUnknown(device, action)):
        return device == RelayExample.module && action == "closed"
      default:
        return false
      }

    }

  }

  @Test(arguments: Undescribed.allCases)
  func refusesARelayTheCatalogDoesntSayHowItHoldsAState(_ undescribed: Undescribed) async throws {

    let modem: InMemoryModem = await modem(flags: 0x00)
    let linking: DeviceLinkingCoordinator = network(modem, catalog: catalog(relayType: relay(holding: undescribed.holding))).linking

    await expectRefusal({ _ = try await linking.planRelayLink(module, recording: .on, observer: LinkingRecorder()) }, undescribed.matches)
    await expectRefusal({ _ = try await linking.linkRelay(module, recording: .on, group: 2, twoWay: .never, observer: LinkingRecorder()) }, undescribed.matches)

    // Nothing is sent, not even a read of the flags or the relay.
    #expect(await modem.linkingSteps.isEmpty)
    #expect(await modem.operatingFlags[module] == 0x00)

  }

  @Test func linksARelayNothingReleasesAsOneThatHoldsItsState() async throws {

    // No flag releases the relay, so its pulsing set doesn't apply even with both flags on,
    // and no flag is read.
    let holding = GroupType.StateHolding(releasedBy: [], restState: "off", pulsesOnEveryCommandWhen: [["pulse", "pulseBoth"]])
    let flags: UInt8 = RelayExample.pulse.bit | RelayExample.pulseBoth.bit
    let modem: InMemoryModem = await modem(flags: flags)
    // Its pulse flag, whatever its name, doesn't make this relay pulse.
    await modem.setPulsingBit(0x80, of: module)
    let linking: DeviceLinkingCoordinator = network(modem, catalog: catalog(relayType: relay(holding: holding))).linking

    let plan: RelayLinkPlan = try await linking.planRelayLink(module, recording: .on, observer: LinkingRecorder())

    #expect(await modem.linkingSteps == [statusRequest])
    #expect(plan.holding.flagsOn.isEmpty)
    #expect(plan.holding.holdsState)
    #expect(!plan.ignoresState)
    #expect(plan.switchesRelay)
    #expect(plan.clearedFlags.isEmpty)
    #expect(plan.switchesBackOnFailure)

    let result: DeviceLinkingResult = try await linking.linkRelay(plan, group: 2, twoWay: .never, observer: LinkingRecorder())

    #expect(!writesFlags(await modem.linkingSteps))
    #expect(await modem.operatingFlags[module] == flags)
    #expect(await modem.levels[module] == 0xFF)
    #expect(result.relayState?.groupOn == .on)
    #expect(result.relayState?.recordedData1 == 0xFF)

  }

  @Test func returnsARelayThatRestsOnToOnAfterRecordingOff() async throws {

    // The relay rests on: while pulse is on, it returns to on by itself.
    let holding = GroupType.StateHolding(releasedBy: ["pulse"], restState: "on")
    let modem: InMemoryModem = await modem(flags: RelayExample.pulse.bit, relay: 0xFF)
    await modem.setPulsingBit(RelayExample.pulse.bit, restLevel: 0xFF, of: module)
    let linking: DeviceLinkingCoordinator = network(modem, catalog: catalog(relayType: relay(holding: holding))).linking

    let result: DeviceLinkingResult = try await linking.linkRelay(module, recording: .off, group: 2, twoWay: .never, observer: LinkingRecorder())

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    // Pulse is turned off and the relay switched off, so it records off; then it's switched
    // back on, its rest state, before pulse is turned back on.
    #expect(Array(steps.prefix(6)) == [
      step(0x1F, 0x00),
      statusRequest,
      step(0x20, RelayExample.pulse.off, extended: true),
      step(0x1F, 0x00),
      step(0x13, 0x00),
      statusRequest
    ])
    #expect(Array(steps.suffix(4)) == [step(0x11, 0xFF), step(0x20, RelayExample.pulse.on, extended: true), step(0x1F, 0x00), statusRequest])
    #expect(await modem.databases[module]?.values.first?.data1 == 0x00)
    #expect(await modem.levels[module] == 0xFF)
    #expect(await modem.operatingFlags[module] == RelayExample.pulse.bit)
    #expect(result.relayState?.groupOn == .off)
    #expect(result.relayState?.holding.restState == .on)

    // Asked for on, its rest state, it isn't switched and no flag is written.
    let rests: RelayLinkPlan = try await linking.planRelayLink(module, recording: .on, observer: LinkingRecorder())

    #expect(!rests.switchesRelay)
    #expect(rests.clearedFlags.isEmpty)

  }

  @Test func readsOnlyTheFlagsTheCatalogNames() async throws {

    // A relay that releases only by a flag named hold, with pulse and pulseBoth not named.
    let flags: [OperatingFlag] = RelayExample.operatingFlags + [
      OperatingFlag(name: "hold", summary: "A made-up flag in another request.", query: OperatingFlagsRequest(rawValue: 0x05), bit: 0x01, on: 0x30, off: 0x31)
    ]
    let modem: InMemoryModem = await modem(flags: RelayExample.pulse.bit)
    let linking: DeviceLinkingCoordinator = network(modem, catalog: catalog(relayType: relay(holding: GroupType.StateHolding(releasedBy: ["hold"], restState: "off")), flags: flags)).linking

    let plan: RelayLinkPlan = try await linking.planRelayLink(module, recording: .on, observer: LinkingRecorder())

    // Only hold's request is read, so pulse, though on, is no part of the plan.
    #expect(await modem.linkingSteps == [step(0x1F, 0x05), step(0x19, 0x00)])
    #expect(plan.holding.flagsOn.isEmpty)
    #expect(plan.holding.holdsState)

  }

  /// The made-up hold flag, a second flag that releases the relay, in the request given.
  func hold(in query: OperatingFlagsRequest = .operatingFlags) -> OperatingFlag {

    OperatingFlag(name: "hold", summary: "A made-up flag that also releases the relay.", query: query, bit: 0x01, on: 0x30, off: 0x31, label: "Hold")

  }

  /// A network on which the module is released by pulse and hold, both of which linking may
  /// change.
  func twoFlagNetwork(_ modem: InMemoryModem, holdQuery: OperatingFlagsRequest = .operatingFlags) -> DeviceNetwork {

    let commands: CommandSet = RelayExample.moduleCommands(
      id: "exampleTwoFlagRelay",
      linkingChanges: [LinkingChange(flag: "pulse"), LinkingChange(flag: "hold")],
      flags: RelayExample.operatingFlags + [hold(in: holdQuery)],
      relayType: relay(holding: GroupType.StateHolding(releasedBy: ["pulse", "hold"], restState: "off"))
    )

    return network(modem, catalog: DeviceCatalog(profiles: [RelayExample.profile("9612", RelayExample.moduleIdentity, commands: commands, type: "relay")], commandSets: [commands]))

  }

  /// A modem whose module has pulse and hold on, and carries out hold's commands unless told
  /// not to turn it off.
  func twoFlagModem(turnsHoldOff: Bool = true) async -> InMemoryModem {

    let modem: InMemoryModem = await modem(flags: RelayExample.pulse.bit | 0x01)
    await modem.setOperatingFlagCommand(0x30, bit: 0x01, isSet: true, of: module)

    if turnsHoldOff {

      await modem.setOperatingFlagCommand(0x31, bit: 0x01, isSet: false, of: module)

    }

    return modem

  }

  /// The steps that turn pulse back on and read it back.
  var restorePulse: [InMemoryModem.LinkingStep] {

    [step(0x20, RelayExample.pulse.on, extended: true), step(0x1F, 0x00)]

  }

  @Test func clearsAndRestoresEachFlagThatReleasesTheRelay() async throws {

    let modem: InMemoryModem = await twoFlagModem()
    let recorder = LinkingRecorder()

    let result: DeviceLinkingResult = try await twoFlagNetwork(modem).linking.linkRelay(module, recording: .on, group: 2, twoWay: .never, observer: recorder)

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    // Both flags are turned off, each read back, before the relay is switched.
    #expect(Array(steps.prefix(7)) == [
      step(0x1F, 0x00),
      statusRequest,
      step(0x20, RelayExample.pulse.off, extended: true),
      step(0x1F, 0x00),
      step(0x20, 0x31, extended: true),
      step(0x1F, 0x00),
      step(0x11, 0xFF)
    ])
    // Then returned to rest, and both set back in the same order.
    #expect(Array(steps.suffix(6)) == [step(0x13, 0x00)] + restorePulse + [step(0x20, 0x30, extended: true), step(0x1F, 0x00), statusRequest])
    #expect(await modem.operatingFlags[module] == RelayExample.pulse.bit | 0x01)
    #expect(await modem.databases[module]?.values.first?.data1 == 0xFF)
    #expect(result.relayState?.clearedFlags.map(\.name) == ["pulse", "hold"])
    #expect(result.relayState?.isRestored == true)
    #expect(result.relayState?.restoreFailures.isEmpty == true)
    #expect(result.relayState?.holding.releasingFlags.map(\.name) == ["pulse", "hold"])

  }

  @Test func readsAndRestoresReleasingFlagsInDifferentRequests() async throws {

    // hold is in another Get Operating Flags request, so each request is read and compared.
    let modem: InMemoryModem = await twoFlagModem()
    await modem.setOperatingFlagsMask(0xFE, forQuery: 0x00, of: module)
    await modem.setOperatingFlagsMask(0x01, forQuery: 0x05, of: module)

    let result: DeviceLinkingResult = try await twoFlagNetwork(modem, holdQuery: OperatingFlagsRequest(rawValue: 0x05)).linking.linkRelay(module, recording: .on, group: 2, twoWay: .never, observer: LinkingRecorder())

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    #expect(Array(steps.prefix(7)) == [
      step(0x1F, 0x00),
      step(0x1F, 0x05),
      statusRequest,
      step(0x20, RelayExample.pulse.off, extended: true),
      step(0x1F, 0x00),
      step(0x20, 0x31, extended: true),
      step(0x1F, 0x05)
    ])
    #expect(Array(steps.suffix(6)) == [step(0x13, 0x00)] + restorePulse + [step(0x20, 0x30, extended: true), step(0x1F, 0x05), statusRequest])
    #expect(await modem.operatingFlags[module] == RelayExample.pulse.bit | 0x01)
    #expect(result.relayState?.restoreFailures.isEmpty == true)

  }

  @Test func reportsAnotherFlagThatChangedInTheSecondRequestsByte() async throws {

    // Setting hold back on also sets another bit of its byte, which only its own request
    // reports.
    let modem: InMemoryModem = await twoFlagModem()
    await modem.setOperatingFlagCommand(0x30, bit: 0x03, isSet: true, of: module)
    await modem.setOperatingFlagsMask(0xFC, forQuery: 0x00, of: module)
    await modem.setOperatingFlagsMask(0x03, forQuery: 0x05, of: module)

    let result: DeviceLinkingResult = try await twoFlagNetwork(modem, holdQuery: OperatingFlagsRequest(rawValue: 0x05)).linking.linkRelay(module, recording: .on, group: 2, twoWay: .never, observer: LinkingRecorder())

    let failures: [RelayStateLinkingError] = result.relayState?.restoreFailures ?? []

    #expect(failures.count == 1)

    guard case let .otherFlagsChanged(device, before, after)? = failures.first else {

      Issue.record("Expected another flag that changed, got \(failures)")

      return

    }

    #expect(device == module)
    #expect(before == 0x01)
    #expect(after == 0x03)

  }

  @Test func putsTheFirstFlagBackWhenTheSecondDoesntReadBackOff() async throws {

    // The module acknowledges turning hold off but doesn't, so hold still reads on.
    let modem: InMemoryModem = await twoFlagModem(turnsHoldOff: false)

    await expectRefusal({ _ = try await twoFlagNetwork(modem).linking.linkRelay(module, recording: .on, group: 2, twoWay: .never, observer: LinkingRecorder()) }) { (error: RelayStateLinkingError) -> Bool in

      guard case let .flagNotChanged(device, flag, isSet) = error else {

        return false

      }

      return device == module && flag.name == "hold" && !isSet

    }

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    // The relay is never switched, nothing is linked, and pulse goes back on before hold is
    // written back on.
    #expect(!steps.contains(step(0x11, 0xFF)))
    #expect(!steps.contains { (step: InMemoryModem.LinkingStep) -> Bool in

      if case .modem = step {

        return true

      }

      return false

    })
    #expect(Array(steps.suffix(4)) == restorePulse + [step(0x20, 0x30, extended: true), step(0x1F, 0x00)])
    #expect(await modem.operatingFlags[module] == RelayExample.pulse.bit | 0x01)

  }

  /// A made-up error the modem throws for one message.
  struct WriteFailed: Error {}

  @Test func putsTheFirstFlagBackWhenTheSecondsWriteFails() async throws {

    let modem: InMemoryModem = await twoFlagModem()
    let module: InsteonAddress = self.module
    let failures = RestoreWatch()

    // The first write that turns hold off fails, as a modem's error after the message left.
    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      if case let .extendedRequest(message) = operation, message.destination == module, message.command == Command(command1: 0x20, command2: 0x31) {

        if await failures.attempts == 0 {

          await failures.count()

          throw WriteFailed()

        }

      }

    }

    await #expect(throws: WriteFailed.self) {

      _ = try await self.twoFlagNetwork(modem).linking.linkRelay(module, recording: .on, group: 2, twoWay: .never, observer: LinkingRecorder())

    }

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    // hold may have reached the device, so both are set back, pulse first; the relay is never
    // switched.
    #expect(!steps.contains(step(0x11, 0xFF)))
    #expect(Array(steps.suffix(4)) == restorePulse + [step(0x20, 0x30, extended: true), step(0x1F, 0x00)])
    #expect(await modem.operatingFlags[module] == RelayExample.pulse.bit | 0x01)

  }

  @Test func putsTheFirstFlagBackWhenCanceledBetweenFlags() async throws {

    let modem: InMemoryModem = await twoFlagModem()
    let module: InsteonAddress = self.module

    // The linking task is canceled as hold is about to be turned off, after pulse was; the
    // modem then refuses the message, as a canceled task's.
    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      if case let .extendedRequest(message) = operation, message.destination == module, message.command == Command(command1: 0x20, command2: 0x31) {

        withUnsafeCurrentTask { (task: UnsafeCurrentTask?) -> Void in task?.cancel() }

      }

    }

    let network: DeviceNetwork = twoFlagNetwork(modem)
    let linking = Task { () async throws -> DeviceLinkingResult in

      try await network.linking.linkRelay(module, recording: .on, group: 2, twoWay: .never, observer: LinkingRecorder())

    }

    await #expect(throws: CancellationError.self) {

      _ = try await linking.value

    }

    #expect(linking.isCancelled)

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    // pulse is set back to its end; hold, whose message may have left, is written back too.
    #expect(!steps.contains(step(0x11, 0xFF)))
    #expect(Array(steps.suffix(4)) == restorePulse + [step(0x20, 0x30, extended: true), step(0x1F, 0x00)])
    #expect(await modem.operatingFlags[module] == RelayExample.pulse.bit | 0x01)

  }

  // MARK: - Verifying the record

  @Test func reportsARecordThatHoldsAnotherStateAndKeepsTheLink() async throws {

    let modem: InMemoryModem = await modem(flags: 0x00)
    let module: InsteonAddress = self.module
    // Something turns the relay off between the check and the link.
    let recorder = LinkingRecorder(reacting: { (event: LinkingEvent) async -> Void in

      if case .linkingRemotely = event {

        await modem.setLevel(0x00, of: module)

      }

    })

    let result: DeviceLinkingResult = try await linkRelay(modem, .on, observer: recorder)

    #expect(result.links.map(\.mode) == [.controller])
    #expect(result.relayState?.recordedData1 == 0x00)

    guard case let .recordedOtherState(device, group, data1, requested)? = result.relayState?.recordFailure else {

      Issue.record("Expected the record to hold another state, got \(String(describing: result.relayState?.recordFailure))")

      return

    }

    #expect(device == module)
    #expect(group == 2)
    #expect(data1 == 0x00)
    #expect(requested == .on)

  }

  // MARK: - Putting things back

  @Test func putsTheRelayAndFlagBackAndLinksNothingWhenTheRelayIsntConfirmed() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.pulse.bit)
    // The relay pulses whatever linking clears, so it never reads on.
    await modem.setPulsingBit(0x80, of: module)
    await modem.setOperatingFlags(RelayExample.pulse.bit | 0x80, of: module)
    let recorder = LinkingRecorder()

    await expectRefusal({ _ = try await linkRelay(modem, .on, observer: recorder) }) { (error: RelayStateLinkingError) -> Bool in

      guard case let .relayNotConfirmed(device, requested) = error else {

        return false

      }

      return device == module && requested == .on

    }

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    #expect(!steps.contains(.modem(.controller, 0x02)))
    #expect(Array(steps.suffix(3)) == returnAndRestore)
    #expect(await modem.operatingFlags[module] == RelayExample.pulse.bit | 0x80)

  }

  @Test func putsEverythingBackWhenTheLinkIsCanceled() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.pulse.bit)
    await modem.setSilent(module)
    let network: DeviceNetwork = self.network(modem)
    let module: InsteonAddress = self.module
    let linking = Task { () async throws -> DeviceLinkingResult in

      try await network.linking.linkRelay(module, recording: .on, group: 2, twoWay: .never, observer: LinkingRecorder())

    }

    await clock.waitForSleeper(until: Linker.defaultRemoteLinkingTimeout)
    linking.cancel()

    await #expect(throws: CancellationError.self) {

      _ = try await linking.value

    }

    #expect(Array(await modem.linkingSteps.suffix(3)) == returnAndRestore)
    #expect(await modem.operatingFlags[module] == RelayExample.pulse.bit)
    #expect(await modem.levels[module] == 0x00)

  }

  @Test func setsTheFlagBackWhenCanceledWhileItsCleared() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.pulse.bit)
    let clear = Command(command1: 0x20, command2: RelayExample.pulse.off)
    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      if case let .extendedRequest(message) = operation, message.command == clear {

        throw CancellationError()

      }

    }

    await #expect(throws: CancellationError.self) {

      _ = try await linkRelay(modem, .on)

    }

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    // The relay was never switched, so only the flag is set back.
    #expect(!steps.contains(step(0x11, 0xFF)))
    #expect(Array(steps.suffix(2)) == [step(0x20, RelayExample.pulse.on, extended: true), step(0x1F, 0x00)])
    #expect(await modem.operatingFlags[module] == RelayExample.pulse.bit)

  }

  @Test func putsEverythingBackWhenAnotherDeviceLinks() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.pulse.bit)
    let other = InsteonAddress(0x4A, 0x5B, 0x09)
    // Another device is waiting in linking mode when the modem starts.
    await modem.pressSetButton(of: other)

    await #expect(throws: LinkMismatch.self) {

      _ = try await linkRelay(modem, .on)

    }

    #expect(Array(await modem.linkingSteps.suffix(3)) == returnAndRestore)
    #expect(await modem.operatingFlags[module] == RelayExample.pulse.bit)

  }

  @Test func refusesTheSETButtonWhenEnterLinkingModeFails() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.pulse.bit)
    let module: InsteonAddress = self.module
    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      switch operation {
      case let .standardRequest(message) where message.command.command1 == 0x09:
        throw ModemError.deviceTimedOut(module)
      case let .extendedRequest(message) where message.command.command1 == 0x09:
        throw ModemError.deviceTimedOut(module)
      default:
        break
      }

    }
    let recorder = LinkingRecorder()

    await expectRefusal({ _ = try await linkRelay(modem, .on, observer: recorder) }) { (error: RelayStateLinkingError) -> Bool in

      guard case let .remoteLinkingFailed(device, _) = error else {

        return false

      }

      return device == module

    }

    // No SET button prompt: a link made that way records whatever state the relay is in then.
    #expect(await recorder.prompts.isEmpty)
    #expect(Array(await modem.linkingSteps.suffix(3)) == returnAndRestore)

  }

  @Test func retriesARestoreThatFailsThenReportsItAndKeepsTheLink() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.pulse.bit)
    let module: InsteonAddress = self.module
    let restore = Command(command1: 0x20, command2: RelayExample.pulse.on)
    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      if case let .extendedRequest(message) = operation, message.command == restore {

        throw ModemError.deviceTimedOut(module)

      }

    }
    let recorder = LinkingRecorder()

    let result: DeviceLinkingResult = try await linkRelay(modem, .on, observer: recorder)

    #expect(result.links.map(\.mode) == [.controller])
    #expect(await modem.operatingFlags[module] == 0x00)
    #expect(result.relayState?.isRestored == false)
    #expect(result.relayState?.holding.holdsState == true)

    guard case let .flagNotRestored(device, flag, reason)? = result.relayState?.restoreFailures.first else {

      Issue.record("Expected the flag not to be restored, got \(String(describing: result.relayState?.restoreFailures))")

      return

    }

    #expect(device == module)
    #expect(flag.name == "pulse")
    #expect(reason is ModemError)
    #expect(await recorder.lines.contains("relay state: failed \(module)"))

  }

  @Test func saysARestoreThatWasWrittenButNotReadBackIsUnconfirmed() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.pulse.bit)
    let module: InsteonAddress = self.module
    let restore = Command(command1: 0x20, command2: RelayExample.pulse.on)
    let restoring = RestoreWatch()
    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      switch operation {
      case let .extendedRequest(message) where message.command == restore:
        await restoring.begin()
      case let .standardRequest(message) where message.command.command1 == 0x1F:
        if await restoring.hasBegun {

          throw ModemError.deviceTimedOut(module)

        }
      default:
        break
      }

    }

    let result: DeviceLinkingResult = try await linkRelay(modem, .on)

    // It was written, twice, and never read back.
    #expect(await modem.operatingFlags[module] == RelayExample.pulse.bit)
    #expect(await modem.linkingSteps.filter { $0 == step(0x20, RelayExample.pulse.on, extended: true) }.count == 2)

    guard case let .flagRestoreUnconfirmed(device, flag, _)? = result.relayState?.restoreFailures.first else {

      Issue.record("Expected the restore to be unconfirmed, got \(String(describing: result.relayState?.restoreFailures))")

      return

    }

    #expect(device == module)
    #expect(flag.name == "pulse")

  }

  @Test func reportsAnotherFlagThatChangedWhileItLinked() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.pulse.bit)
    let module: InsteonAddress = self.module
    let recorder = LinkingRecorder(reacting: { (event: LinkingEvent) async -> Void in

      if case .linkingRemotely = event {

        await modem.setOperatingFlags(0x02, of: module)

      }

    })

    let result: DeviceLinkingResult = try await linkRelay(modem, .on, observer: recorder)

    #expect(result.relayState?.isRestored == true)

    guard case let .otherFlagsChanged(device, before, after)? = result.relayState?.restoreFailures.first else {

      Issue.record("Expected another flag to have changed, got \(String(describing: result.relayState?.restoreFailures))")

      return

    }

    #expect(device == module)
    #expect(before == RelayExample.pulse.bit)
    #expect(after == RelayExample.pulse.bit | 0x02)

  }

  // MARK: - A pulsing relay read mid-pulse

  @Test func leavesAPulsingRelayReadOnMidPulseOpenWhenRecordingOff() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.pulse.bit, relay: 0xFF)

    let result: DeviceLinkingResult = try await linkRelay(modem, .off)

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    // Switched to its rest state, it stays there by itself, so no flag is turned off.
    #expect(!steps.contains(step(0x11, 0xFF)))
    #expect(steps.contains(step(0x13, 0x00)))
    #expect(!writesFlags(steps))
    #expect(result.relayState?.clearedFlags.isEmpty == true)
    #expect(await modem.levels[module] == 0x00)
    #expect(await modem.operatingFlags[module] == RelayExample.pulse.bit)
    #expect(result.relayState?.recordedData1 == 0x00)

  }

  @Test func opensAPulsingRelayReadOnMidPulseAfterRecordingOn() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.pulse.bit, relay: 0xFF)

    let result: DeviceLinkingResult = try await linkRelay(modem, .on)

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    // On once, to hold it, and Off once the link is made: never On again.
    #expect(steps.filter { $0 == step(0x11, 0xFF) }.count == 1)
    #expect(Array(steps.suffix(4)) == returnAndRestore + [statusRequest])
    #expect(await modem.levels[module] == 0x00)
    #expect(await modem.operatingFlags[module] == RelayExample.pulse.bit)
    #expect(result.relayState?.recordedData1 == 0xFF)

  }

  // MARK: - A latching relay

  @Test func switchesALatchingRelayBackWhenTheLinkFails() async throws {

    let modem: InMemoryModem = await modem(flags: 0x00)
    let module: InsteonAddress = self.module
    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      if case let .extendedRequest(message) = operation, message.command.command1 == 0x09 {

        throw ModemError.deviceTimedOut(module)

      }

    }

    await expectRefusal({ _ = try await linkRelay(modem, .on) }) { (error: RelayStateLinkingError) -> Bool in

      if case .remoteLinkingFailed = error {

        return true

      }

      return false

    }

    #expect(await modem.linkingSteps.last == step(0x13, 0x00))
    #expect(await modem.levels[module] == 0x00)

  }

  @Test func switchesALatchingRelayBackWhenTheLinkIsCanceled() async throws {

    let modem: InMemoryModem = await modem(flags: 0x00)
    await modem.setSilent(module)
    let network: DeviceNetwork = self.network(modem)
    let module: InsteonAddress = self.module
    let linking = Task { () async throws -> DeviceLinkingResult in

      try await network.linking.linkRelay(module, recording: .on, group: 2, twoWay: .never, observer: LinkingRecorder())

    }

    await clock.waitForSleeper(until: Linker.defaultRemoteLinkingTimeout)
    linking.cancel()

    await #expect(throws: CancellationError.self) {

      _ = try await linking.value

    }

    // Its status is read inside the put back, and it still reads on, so it's switched back.
    #expect(Array(await modem.linkingSteps.suffix(2)) == [statusRequest, step(0x13, 0x00)])
    #expect(await modem.levels[module] == 0x00)

  }

  @Test func keepsALatchingRelayInTheStateItRecorded() async throws {

    let modem: InMemoryModem = await modem(flags: 0x00)

    _ = try await linkRelay(modem, .on)

    #expect(await modem.levels[module] == 0xFF)
    #expect(!(await modem.linkingSteps.contains(step(0x13, 0x00))))

  }

  // MARK: - Checking the record

  @Test func reportsARecordThatIsntThere() async throws {

    let modem: InMemoryModem = await modem(flags: 0x00)
    let module: InsteonAddress = self.module
    let recorder = LinkingRecorder(reacting: { (event: LinkingEvent) async -> Void in

      if case .linked = event {

        await modem.setDatabase([:], of: module)

      }

    })

    let result: DeviceLinkingResult = try await linkRelay(modem, .on, observer: recorder)

    guard case let .recordNotFound(device, group)? = result.relayState?.recordFailure else {

      Issue.record("Expected no record, got \(String(describing: result.relayState?.recordFailure))")

      return

    }

    #expect(device == module)
    #expect(group == 2)
    #expect(result.relayState?.recordedData1 == nil)

  }

  @Test func reportsADatabaseThatCantBeRead() async throws {

    let modem: InMemoryModem = await modem(flags: 0x00)
    let module: InsteonAddress = self.module
    let recorder = LinkingRecorder(reacting: { (event: LinkingEvent) async -> Void in

      if case .linked = event {

        await modem.setUnlinked(module)

      }

    })

    let result: DeviceLinkingResult = try await linkRelay(modem, .on, observer: recorder)

    guard case .recordNotRead? = result.relayState?.recordFailure else {

      Issue.record("Expected the database not to be read, got \(String(describing: result.relayState?.recordFailure))")

      return

    }

    #expect(result.links.map(\.mode) == [.controller])

  }

  @Test func checksTheRecordAfterPuttingTheRelayBackAndStopsWhenCanceledThere() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.pulse.bit)
    let restore = Command(command1: 0x20, command2: RelayExample.pulse.on)
    let restoring = RestoreWatch()
    // Canceled once everything is put back, as the record check asks for the status.
    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      switch operation {
      case let .extendedRequest(message) where message.command == restore:
        await restoring.begin()
      case let .standardRequest(message) where message.command.command1 == 0x19:
        if await restoring.hasBegun {

          withUnsafeCurrentTask { (task: UnsafeCurrentTask?) -> Void in task?.cancel() }

        }
      default:
        break
      }

    }

    await #expect(throws: CancellationError.self) {

      _ = try await linkRelay(modem, .on)

    }

    // The relay was opened and the flag set back before the record was read.
    // The canceled status request was never sent.
    #expect(Array(await modem.linkingSteps.suffix(3)) == returnAndRestore)
    #expect(await modem.levels[module] == 0x00)
    #expect(await modem.operatingFlags[module] == RelayExample.pulse.bit)
    #expect(await modem.databaseReads[module] == nil)

  }

  @Test func retriesTheRelaysReturnThenReportsIt() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.pulse.bit)
    let module: InsteonAddress = self.module
    let linked = RestoreWatch()
    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      switch operation {
      case let .extendedRequest(message) where message.command.command1 == 0x09:
        await linked.begin()
      case let .standardRequest(message) where message.command.command1 == 0x13:
        if await linked.hasBegun {

          await linked.count()

          throw ModemError.deviceTimedOut(module)

        }
      default:
        break
      }

    }

    let result: DeviceLinkingResult = try await linkRelay(modem, .on)

    #expect(await linked.attempts == 2)
    #expect(await modem.operatingFlags[module] == RelayExample.pulse.bit)

    guard case let .relayNotReturned(device, state, _)? = result.relayState?.restoreFailures.first else {

      Issue.record("Expected the relay not to be returned, got \(String(describing: result.relayState?.restoreFailures))")

      return

    }

    #expect(device == module)
    #expect(state == .off)

  }

  @Test func saysARestoreIsUnconfirmedWhenAnyWriteWasAcknowledged() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.pulse.bit)
    let module: InsteonAddress = self.module
    let restore = Command(command1: 0x20, command2: RelayExample.pulse.on)
    let restoring = RestoreWatch()
    // The first write is acknowledged and its read back times out; the second write times out.
    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      switch operation {
      case let .extendedRequest(message) where message.command == restore:
        await restoring.count()

        if await restoring.attempts == 2 {

          throw ModemError.deviceTimedOut(module)

        }
      case let .standardRequest(message) where message.command.command1 == 0x1F:
        if await restoring.attempts > 0 {

          throw ModemError.deviceTimedOut(module)

        }
      default:
        break
      }

    }

    let result: DeviceLinkingResult = try await linkRelay(modem, .on)

    #expect(await modem.operatingFlags[module] == RelayExample.pulse.bit)

    guard case .flagRestoreUnconfirmed? = result.relayState?.restoreFailures.first else {

      Issue.record("Expected the restore to be unconfirmed, got \(String(describing: result.relayState?.restoreFailures))")

      return

    }

  }

  @Test func refusesBeforeClearingAFlagItCouldntSetBack() async throws {

    let device: InsteonAddress = RelayExample.oneWayModule
    let modem: InMemoryModem = await modem(device, flags: RelayExample.pulse.bit)

    // The flag can't be turned back on, so the relay can't be made to hold a state.
    await expectRefusal({ _ = try await linkRelay(modem, .on, device: device) }) { (error: RelayStateLinkingError) -> Bool in

      guard case let .flagNotWritable(refused, flag, _) = error else {

        return false

      }

      return refused == device && flag == RelayFlag(name: "pulse", label: "Pulse")

    }

    #expect(await modem.linkingSteps == [step(0x1F, 0x00, to: device), step(0x19, 0x00, to: device)])
    #expect(await modem.operatingFlags[device] == RelayExample.pulse.bit)

  }

  @Test func leavesALatchingRelayAloneWhenItsStatusDisagrees() async throws {

    let modem: InMemoryModem = await modem(flags: 0x80)
    // The relay opens again, though no flag the catalog names for it is on.
    await modem.setPulsingBit(0x80, of: module)
    let recorder = LinkingRecorder()

    await expectRefusal({ _ = try await linkRelay(modem, .on, observer: recorder) }) { (error: RelayStateLinkingError) -> Bool in

      if case .relayNotConfirmed = error {

        return true

      }

      return false

    }

    // After On, only the status that disagreed: nothing switches it again.
    #expect(await modem.linkingSteps == [step(0x1F, 0x00), step(0x19, 0x00), step(0x11, 0xFF), statusRequest])
    #expect(await recorder.lines.last == "relay state: \(module) left off")

  }

  @Test func leavesALatchingRelaySomeoneElseSwitchedWhenTheLinkFails() async throws {

    let modem: InMemoryModem = await modem(flags: 0x00)
    let module: InsteonAddress = self.module
    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      if case let .extendedRequest(message) = operation, message.command.command1 == 0x09 {

        // Someone switches the relay off as the link fails.
        await modem.setLevel(0x00, of: module)

        throw ModemError.deviceTimedOut(module)

      }

    }
    let recorder = LinkingRecorder()

    await expectRefusal({ _ = try await linkRelay(modem, .on, observer: recorder) }) { (error: RelayStateLinkingError) -> Bool in

      if case .remoteLinkingFailed = error {

        return true

      }

      return false

    }

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    #expect(steps.last == statusRequest)
    #expect(!steps.contains(step(0x13, 0x00)))
    #expect(await recorder.lines.last == "relay state: \(module) left off")

  }

  @Test func switchesALatchingRelayBackAndSaysSoWhenItsStatusCantBeRead() async throws {

    let modem: InMemoryModem = await modem(flags: 0x00)
    let module: InsteonAddress = self.module
    let linking = RestoreWatch()
    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      switch operation {
      case let .extendedRequest(message) where message.command.command1 == 0x09:
        await linking.begin()

        throw ModemError.deviceTimedOut(module)
      case let .standardRequest(message) where message.command.command1 == 0x19:
        if await linking.hasBegun {

          throw ModemError.deviceTimedOut(module)

        }
      default:
        break
      }

    }
    let reported = ReportedFailures()
    let recorder = LinkingRecorder(reacting: { (event: LinkingEvent) async -> Void in

      if case let .relayState(.restoreFailed(_, failure)) = event {

        await reported.append(failure)

      }

    })

    await expectRefusal({ _ = try await linkRelay(modem, .on, observer: recorder) }) { (error: RelayStateLinkingError) -> Bool in

      if case .remoteLinkingFailed = error {

        return true

      }

      return false

    }

    #expect(await modem.linkingSteps.last == step(0x13, 0x00))
    #expect(await recorder.lines.suffix(2) == ["relay state: returning \(module) off", "relay state: failed \(module)"])

    // Reported, not thrown: the link's own failure is what's thrown.
    guard case let .relayReturnUnconfirmed(device, state, _)? = await reported.failures.first else {

      Issue.record("Expected an unconfirmed return, got \(await reported.failures)")

      return

    }

    #expect(device == module)
    #expect(state == .off)

  }

  @Test func refusesBeforeChangingAnythingWhenTheRelayCantBeOpenedAfterward() async throws {

    let device: InsteonAddress = RelayExample.noOffModule
    let pulsing: InMemoryModem = await modem(device, flags: RelayExample.pulse.bit)

    await #expect(throws: DeviceControlError.self) {

      _ = try await linkRelay(pulsing, .on, device: device)

    }

    #expect(await pulsing.linkingSteps == [step(0x1F, 0x00, to: device), step(0x19, 0x00, to: device)])

    let latching: InMemoryModem = await modem(device, flags: 0x00)

    await #expect(throws: DeviceControlError.self) {

      _ = try await linkRelay(latching, .on, device: device)

    }

    #expect(await latching.linkingSteps == [step(0x1F, 0x00, to: device), step(0x19, 0x00, to: device)])

  }

  @Test func refusesBeforeChangingAnythingWhenTheRelayCantBeSwitched() async throws {

    let device: InsteonAddress = RelayExample.noOnModule
    let modem: InMemoryModem = await modem(device, flags: 0x00)

    await #expect(throws: DeviceControlError.self) {

      _ = try await linkRelay(modem, .on, device: device)

    }

    #expect(await modem.linkingSteps == [step(0x1F, 0x00, to: device), step(0x19, 0x00, to: device)])

  }

  @Test func setsNothingBackWhenClearingTheFlagIsRefused() async throws {

    let device: InsteonAddress = RelayExample.noClearModule
    let modem: InMemoryModem = await modem(device, flags: RelayExample.pulse.bit)

    // The flag can't be turned off, so the relay can't be made to hold a state, and that's
    // found before anything but reads is sent.
    await expectRefusal({ _ = try await linkRelay(modem, .on, device: device) }) { (error: RelayStateLinkingError) -> Bool in

      guard case let .flagNotWritable(refused, flag, _) = error else {

        return false

      }

      return refused == device && flag.name == "pulse"

    }

    #expect(await modem.linkingSteps == [step(0x1F, 0x00, to: device), step(0x19, 0x00, to: device)])
    #expect(!writesFlags(await modem.linkingSteps))
    #expect(await modem.operatingFlags[device] == RelayExample.pulse.bit)

  }

  // MARK: - Refusing a relay state

  @Test func refusesAPulseFlagTheCatalogDoesntLetLinkingChange() async throws {

    let device: InsteonAddress = RelayExample.fixedModule
    let modem: InMemoryModem = await modem(device, flags: RelayExample.pulse.bit)
    let network: DeviceNetwork = self.network(modem)

    await expectRefusal({ _ = try await network.linking.linkRelay(device, recording: .on, group: 2, observer: LinkingRecorder()) }) { (error: RelayStateLinkingError) -> Bool in

      guard case let .flagNotChangeable(refused, flag) = error else {

        return false

      }

      return refused == device && flag.name == "pulse"

    }

    // The flags and status were read, and nothing else was sent.
    #expect(await modem.linkingSteps == [step(0x1F, 0x00, to: device), step(0x19, 0x00, to: device)])
    #expect(await modem.operatingFlags[device] == RelayExample.pulse.bit)

  }

  @Test func refusesAnUnlinkedDeviceAndSaysToLinkItFirst() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.pulse.bit)
    // An i2CS device rejects the modem's direct commands until it holds a link to it.
    await modem.setUnlinked(module)

    await expectRefusal({ _ = try await linkRelay(modem, .on) }) { (error: RelayStateLinkingError) -> Bool in

      guard case let .notLinkedToModem(device) = error else {

        return false

      }

      return device == module

    }

    #expect(await modem.linkingSteps == [step(0x1F, 0x00)])
    #expect(await modem.operatingFlags[module] == RelayExample.pulse.bit)

  }

  @Test func refusesADeviceWhoseMainGroupIsntARelay() async throws {

    let modem = InMemoryModem()
    let dimmer: InsteonAddress = RelayExample.dimmer

    await expectRefusal({ _ = try await linkRelay(modem, .on, device: dimmer) }) { (error: RelayStateLinkingError) -> Bool in

      guard case let .notARelay(device, _) = error else {

        return false

      }

      return device == dimmer

    }

    #expect(await modem.linkingSteps.isEmpty)
    #expect(await modem.levels[dimmer] == nil)

  }

  @Test func refusesADeviceThatWontSayWhatItIs() async throws {

    let modem = InMemoryModem()
    let stranger: InsteonAddress = RelayExample.stranger
    // It rejects the modem, as an i2CS device does until it's linked, so it reports no identity.
    await modem.setUnlinked(stranger)

    await expectRefusal({ _ = try await linkRelay(modem, .on, device: stranger) }) { (error: RelayStateLinkingError) -> Bool in

      guard case let .notLinkedToModem(device) = error else {

        return false

      }

      return device == stranger

    }

    #expect(changes(in: await modem.linkingSteps).isEmpty)

  }

  @Test func refusesADeviceTheCatalogDoesntDescribe() async throws {

    let modem = InMemoryModem()
    let stranger: InsteonAddress = RelayExample.stranger
    await modem.setIdentity(SetButtonPressed(sender: stranger, role: .responder, category: 0x7A, subcategory: 0x7F, firmwareVersion: 0x41))

    await expectRefusal({ _ = try await linkRelay(modem, .on, device: stranger) }) { (error: RelayStateLinkingError) -> Bool in

      guard case let .notDescribed(device) = error else {

        return false

      }

      return device == stranger

    }

    #expect(changes(in: await modem.linkingSteps).isEmpty)

  }

  @Test func failsWithoutWritingAnythingWhenTheDeviceDoesntAnswer() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.pulse.bit)
    await modem.setUnanswering(module)

    await #expect {

      _ = try await linkRelay(modem, .on)

    } throws: { (error: any Error) -> Bool in

      guard case let .deviceTimedOut(device)? = error as? ModemError else {

        return false

      }

      return device == module

    }

    #expect(changes(in: await modem.linkingSteps).isEmpty)
    #expect(await modem.operatingFlags[module] == RelayExample.pulse.bit)
    #expect(await modem.databases[module] == nil)

  }

  // MARK: - Without a relay state

  @Test func plainLinkNeverTouchesTheRelayOrItsFlags() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.pulse.bit)

    let result: DeviceLinkingResult = try await network(modem).linking.link(module, as: .controller, group: 2, twoWay: .never, observer: LinkingRecorder())

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    #expect(result.relayState == nil)
    #expect(!steps.contains { (step: InMemoryModem.LinkingStep) -> Bool in

      if case let .device(_, command, _) = step {

        return [0x11, 0x13, 0x19, 0x1F, 0x20].contains(command.command1)

      }

      return false

    })
    #expect(await modem.operatingFlags[module] == RelayExample.pulse.bit)

  }

  // MARK: - A relay whose catalog gives its links to a Hub

  /// A network on which the module is the relay whose catalog gives its links to a Hub.
  func leggedNetwork(_ modem: InMemoryModem) -> DeviceNetwork {

    network(modem, identities: [module: RelayExample.leggedModuleIdentity])

  }

  @Test func plainLinkByTheCatalogsLegsNeverTouchesTheRelayOrItsFlags() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.pulse.bit)

    let result: DeviceLinkingResult = try await leggedNetwork(modem).linking.link(module, as: .controller, observer: LinkingRecorder())

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    // Linked by the catalog's legs, with no relay command and no flag written.
    #expect(result.legs.count == 2)
    #expect(!steps.contains { (step: InMemoryModem.LinkingStep) -> Bool in

      if case let .device(_, command, _) = step {

        return [0x11, 0x13, 0x20].contains(command.command1)

      }

      return false

    })
    #expect(await modem.operatingFlags[module] == RelayExample.pulse.bit)

  }

  @Test func linksAPulsingRelayOnInOneLinkNotByTheLegsAndPutsItAllBack() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.pulse.bit)

    let result: DeviceLinkingResult = try await leggedNetwork(modem).linking.linkRelay(module, recording: .on, observer: LinkingRecorder())

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    // Flags and status read, pulse cleared and read back, the relay set and confirmed, the
    // link and the link back, then the relay returned to rest, the flag set back and read
    // back, and the status the record check asks for.
    #expect(steps == [
      step(0x1F, 0x00),
      statusRequest,
      step(0x20, RelayExample.pulse.off, extended: true),
      step(0x1F, 0x00),
      step(0x11, 0xFF),
      statusRequest,
      step(0x0D, 0x00),
      .modem(.controller, 0x00),
      step(0x09, 0x01, extended: true),
      step(0x0D, 0x00),
      step(0x09, 0x01, extended: true),
      .modem(.responder, 0x01)
    ] + returnAndRestore + [statusRequest])
    #expect(await modem.databases[module]?.values.contains { (record: AllLinkRecord) -> Bool in

      !record.flags.contains(.controller) && record.data1 == 0xFF

    } == true)
    #expect(result.legs.isEmpty)
    #expect(result.relayState?.clearedFlags.map(\.name) == ["pulse"])
    #expect(result.relayState?.isRestored == true)
    #expect(await modem.operatingFlags[module] == RelayExample.pulse.bit)
    #expect(await modem.levels[module] == 0x00)

  }

  @Test func putsAPulsingRelayBackWhenItsLinkIsCanceled() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.pulse.bit)
    await modem.setSilent(module)
    let network: DeviceNetwork = leggedNetwork(modem)
    let module: InsteonAddress = self.module
    let linking = Task { () async throws -> DeviceLinkingResult in

      try await network.linking.linkRelay(module, recording: .on, observer: LinkingRecorder())

    }

    await clock.waitForSleeper(until: Linker.defaultRemoteLinkingTimeout)
    linking.cancel()

    await #expect(throws: CancellationError.self) {

      _ = try await linking.value

    }

    #expect(Array(await modem.linkingSteps.suffix(3)) == returnAndRestore)
    #expect(await modem.operatingFlags[module] == RelayExample.pulse.bit)
    #expect(await modem.levels[module] == 0x00)

  }

  // MARK: - By writing ALL-Link databases

  @Test func writesTheRelayStateAsData1OfTheResponderRecord() async throws {

    let device: InsteonAddress = DatabaseLinkingExample.module
    let modem = InMemoryModem()
    await modem.setEngine(.i2cs, of: device)
    await modem.setIdentity(SetButtonPressed(sender: device, role: .responder, category: 0x02, subcategory: 0x74, firmwareVersion: 0x41))
    await modem.setOperatingFlags(0x00, of: device)
    let log: OperationLog = await OperationLog.logging(modem)
    let linking: DeviceLinkingCoordinator = DeviceNetwork(modem: modem, catalog: DatabaseLinkingExample.catalog, clock: clock).linking

    let plan: DatabaseLinkPlan = try await linking.planDatabaseLink(device, relayState: .off)

    let responder: DatabaseLinkStep? = plan.deviceSteps.first { (step: DatabaseLinkStep) -> Bool in step.kind == .addDeviceRecord && !step.record.isController }

    #expect(plan.relayState == .off)
    #expect(responder?.record.data == [0x00, 0x00, 0x00])
    // Planning reads, the flags the catalog names among them; it neither sets the relay nor
    // writes a flag.
    #expect(log.standardCommands == [0x0D, 0x10, 0x1F])
    #expect(log.writesAndExtendedMessages == 0)

    let result: DatabaseLinkResult = try await linking.apply(plan)

    #expect(result.isComplete)
    #expect(await modem.record(of: device, at: 0x0FFF).data1 == 0x00)

  }

  @Test func refusesADatabaseRelayStateWhenTheRecordInPlaceHoldsTheOtherState() async throws {

    let device: InsteonAddress = DatabaseLinkingExample.module
    let modem = InMemoryModem()
    await modem.setEngine(.i2cs, of: device)
    await modem.setIdentity(SetButtonPressed(sender: device, role: .responder, category: 0x02, subcategory: 0x74, firmwareVersion: 0x41))
    await modem.setOperatingFlags(0x00, of: device)
    await modem.setDatabase([
      0x0FFF: AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 0x00, address: modem.address, data1: 0xFF, data2: 0x00, data3: 0x00)
    ], of: device)
    let linking: DeviceLinkingCoordinator = DeviceNetwork(modem: modem, catalog: DatabaseLinkingExample.catalog, clock: clock).linking

    await expectRefusal({ _ = try await linking.planDatabaseLink(device, relayState: .off) }) { (error: RelayStateLinkingError) -> Bool in

      guard case let .recordInPlace(refused, group, data1) = error else {

        return false

      }

      return refused == device && group == 0x00 && data1 == 0xFF

    }

    // The same state already in place is no reason to refuse.
    let plan: DatabaseLinkPlan = try await linking.planDatabaseLink(device, relayState: .on)

    #expect(plan.relayState == .on)

  }

  @Test func refusesADatabaseRelayStateForADeviceWhoseMainGroupIsntARelay() async throws {

    let dimmer: InsteonAddress = RelayExample.dimmer
    let modem = InMemoryModem()
    await modem.setEngine(.i2cs, of: dimmer)
    await modem.setIdentity(SetButtonPressed(sender: dimmer, role: .responder, category: 0x7B, subcategory: 0x62, firmwareVersion: 0x41))
    let linking: DeviceLinkingCoordinator = DeviceNetwork(modem: modem, catalog: RelayExample.catalog, clock: clock).linking

    await expectRefusal({ _ = try await linking.planDatabaseLink(dimmer, relayState: .on) }) { (error: RelayStateLinkingError) -> Bool in

      guard case let .notARelay(device, _) = error else {

        return false

      }

      return device == dimmer

    }

  }

  @Test func keepsTheDatabaseRefusalsGuidanceForADeviceItCantIdentify() async throws {

    let device: InsteonAddress = DatabaseLinkingExample.module
    let modem = InMemoryModem()
    await modem.setEngine(.i2cs, of: device)
    await modem.setIdentity(SetButtonPressed(sender: device, role: .responder, category: 0x02, subcategory: 0x7E, firmwareVersion: 0x41))
    let linking: DeviceLinkingCoordinator = DeviceNetwork(modem: modem, catalog: DatabaseLinkingExample.catalog, clock: clock).linking

    await #expect(throws: DatabaseLinkRefusal.notInCatalog(device)) {

      _ = try await linking.planDatabaseLink(device, relayState: .on)

    }

  }

  @Test func writesTheStateOnlyForAGroupWhoseTypeIsARelay() {

    let description: DeviceDescription = RelayExample.catalog.describe(category: 0x7A, subcategory: 0x60, firmwareVersion: 0x41)

    #expect(DeviceLinkingCoordinator.recordsRelayState(description, deviceGroup: 1))
    // The catalog gives no type for group 2, so its record isn't the relay's.
    #expect(!DeviceLinkingCoordinator.recordsRelayState(description, deviceGroup: 2))

  }

  // MARK: - Values

  /// The made-up pulse flag, as a relay link names it.
  let pulseFlag = RelayFlag(name: "pulse", label: "Pulse")

  /// The made-up pulseBoth flag, as a relay link names it.
  let pulseBothFlag = RelayFlag(name: "pulseBoth", label: "Pulse on both")

  @Test func describesEachRefusalNamingTheDeviceAndTheFlagsLabel() {

    let refused = RelayStateLinkingError.flagNotChangeable(module, flag: pulseFlag)
    let notRestored = RelayStateLinkingError.flagNotRestored(module, flag: pulseFlag, reason: ModemError.deviceTimedOut(module))
    let unconfirmed = RelayStateLinkingError.flagRestoreUnconfirmed(module, flag: pulseFlag, reason: ModemError.deviceTimedOut(module))
    let undescribed = RelayStateLinkingError.stateHoldingNotDescribed(module, product: "Example 9611 9611")
    let unknownFlag = RelayStateLinkingError.stateHoldingFlagUnknown(module, flag: "hum")
    let unknownRest = RelayStateLinkingError.restStateUnknown(module, action: "closed")
    let notWritable = RelayStateLinkingError.flagNotWritable(module, flag: pulseFlag, reason: ModemError.deviceTimedOut(module))
    let inPlace = RelayStateLinkingError.recordInPlace(module, group: 0, data1: 0xFF)

    #expect(InsteonErrorDescription.message(for: refused) == refused.description)
    #expect(refused.description.hasPrefix("\(module)'s Pulse flag is on, so its relay doesn't hold a state"))
    #expect(notRestored.description.hasPrefix("\(module)'s Pulse flag wasn't set back on: "))
    #expect(unconfirmed.description.hasPrefix("\(module)'s Pulse flag was written back on, but it couldn't be read back to confirm: "))
    #expect(undescribed.description == "The Insteon device catalog doesn't say how \(module)'s relay, Example 9611 9611, holds a state, "
      + "so what a link would record isn't known. Nothing was changed.")
    #expect(undescribed.device == module)
    #expect(unknownFlag.description == "The Insteon device catalog names a flag, hum, in how \(module)'s relay holds a state, "
      + "but its command set doesn't give that flag, so it can't be read. Nothing was changed.")
    #expect(unknownRest.description == "The Insteon device catalog gives \(module)'s relay the rest state closed, which isn't its On or Off action, "
      + "so the state it returns to isn't known. Nothing was changed.")
    #expect(notWritable.description.hasPrefix("\(module)'s Pulse flag is on, so its relay doesn't hold a state, and the message that turns the flag off or back on would be refused: "))
    #expect([unknownFlag.device, unknownRest.device, notWritable.device] == [module, module, module])
    #expect(inPlace.description.contains("Data 1 0xFF"))

  }

  @Test func saysHowARelayChangedSinceItsPlan() {

    let holding = RelayStateHolding(releasedBy: ["pulse"], restState: .off, pulsesOnEveryCommandWhen: [["pulse", "pulseBoth"]], flagsOn: [pulseFlag])
    let old = RelayLinkPlan(device: module, state: .on, before: .off, holding: holding)
    var switched: RelayLinkPlan = old
    var flagged: RelayLinkPlan = old
    var both: RelayLinkPlan = old
    var other: RelayLinkPlan = old

    switched.before = .on
    flagged.holding.flagsOn = []
    both.before = .on
    both.holding.flagsOn = [pulseFlag, pulseBothFlag]
    other.state = .off

    let prefix: String = "\(module) changed since the plan was shown: "
    let suffix: String = ". Nothing was changed; plan the link again."

    #expect(RelayStateLinkingError.planChanged(old: old, new: switched).description == prefix + "its relay reads on, not off" + suffix)
    #expect(RelayStateLinkingError.planChanged(old: old, new: flagged).description == prefix + "its Pulse flag is off" + suffix)
    #expect(RelayStateLinkingError.planChanged(old: old, new: both).description == prefix
      + "its relay reads on, not off, and its Pulse on both flag is on" + suffix)
    #expect(RelayStateLinkingError.planChanged(old: old, new: other).description == prefix + "the plan is for another relay or state" + suffix)

  }

  @Test func readsHowARelayHoldsAStateFromTheFlagsOn() {

    let both: [[String]] = [["pulse", "pulseBoth"]]

    // Nothing on: the relay holds its state.
    #expect(RelayStateHolding(releasedBy: ["pulse"], restState: .off, pulsesOnEveryCommandWhen: both).holdsState)
    // A releasing flag on.
    let released = RelayStateHolding(releasedBy: ["pulse"], restState: .off, pulsesOnEveryCommandWhen: both, flagsOn: [pulseFlag])
    #expect(!released.holdsState)
    #expect(!released.ignoresState)
    #expect(released.releasingFlags == [pulseFlag])
    // Only part of a pulsing set: an ordinary relay.
    let part = RelayStateHolding(releasedBy: ["pulse"], restState: .off, pulsesOnEveryCommandWhen: both, flagsOn: [pulseBothFlag])
    #expect(part.holdsState)
    #expect(!part.ignoresState)
    // The whole set.
    let whole = RelayStateHolding(releasedBy: ["pulse"], restState: .off, pulsesOnEveryCommandWhen: both, flagsOn: [pulseBothFlag, pulseFlag])
    #expect(whole.ignoresState)
    #expect(whole.pulsingFlags == [pulseFlag, pulseBothFlag])
    // A relay nothing releases always holds its state: its pulsing sets don't apply.
    let neverReleased = RelayStateHolding(releasedBy: [], restState: .off, pulsesOnEveryCommandWhen: both, flagsOn: [pulseFlag, pulseBothFlag])
    #expect(neverReleased.holdsState)
    #expect(!neverReleased.ignoresState)
    // An empty set never pulses, and doesn't hide a set after it.
    #expect(!RelayStateHolding(releasedBy: ["pulse"], restState: .off, pulsesOnEveryCommandWhen: [[]]).ignoresState)
    #expect(RelayStateHolding(releasedBy: ["pulse"], restState: .off, pulsesOnEveryCommandWhen: [[], ["pulse"]], flagsOn: [pulseFlag]).pulsingFlags == [pulseFlag])

  }

  @Test func plansFromHowTheRelayHoldsAState() {

    let holding = RelayStateHolding(releasedBy: ["pulse"], restState: .off, flagsOn: [pulseFlag])

    // A released relay at rest, asked for its rest state, isn't switched.
    #expect(!RelayLinkPlan(device: module, state: .off, before: .off, holding: holding).switchesRelay)
    // Read mid-pulse, it's switched to its rest state without turning a flag off.
    let midPulse = RelayLinkPlan(device: module, state: .off, before: .on, holding: holding)
    #expect(midPulse.switchesRelay)
    #expect(midPulse.clearedFlags.isEmpty)
    #expect(!midPulse.returnsToRestAfterLinking)
    // Asked for the other state, it's switched with its flag off, then returned to rest.
    let on = RelayLinkPlan(device: module, state: .on, before: .on, holding: holding)
    #expect(on.switchesRelay)
    #expect(on.clearedFlags == [pulseFlag])
    #expect(on.returnsToRestAfterLinking)
    #expect(!on.switchesBackOnFailure)

    // A relay that rests on returns to on.
    var restsOn: RelayStateHolding = holding
    restsOn.restState = .on
    let off = RelayLinkPlan(device: module, state: .off, before: .on, holding: restsOn)
    #expect(off.switchesRelay)
    #expect(off.returnsToRestAfterLinking)
    #expect(!RelayLinkPlan(device: module, state: .on, before: .on, holding: restsOn).switchesRelay)

  }

  @Test func givesEachStateItsData1AndItsOpposite() {

    #expect(RelayState.on.data1 == 0xFF)
    #expect(RelayState.off.data1 == 0x00)
    #expect(RelayState.on.opposite == .off)
    #expect(RelayState.off.opposite == .on)

  }

}

/// The failures an observer was told about while things were put back.
actor ReportedFailures {

  private(set) var failures: [RelayStateLinkingError] = []

  func append(_ failure: RelayStateLinkingError) {

    failures.append(failure)

  }

}

/// Whether the pulse flag's restore has begun, for a test that fails what follows it, and
/// how many times something was tried.
actor RestoreWatch {

  private(set) var hasBegun: Bool = false

  private(set) var attempts: Int = 0

  func begin() {

    hasBegun = true

  }

  func count() {

    attempts += 1

  }

}
