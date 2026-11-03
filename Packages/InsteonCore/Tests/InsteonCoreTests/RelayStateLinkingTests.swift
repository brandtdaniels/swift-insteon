import Foundation
import Testing
@testable import InsteonCore
import InsteonDeviceCatalog
import InsteonLinking
import InsteonLinkingTestSupport
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// Made-up devices to link with a chosen relay state: an I/O module whose catalog lets linking
/// change its momentary flag, one whose catalog doesn't, and a dimmer, whose main group isn't
/// a relay.
enum RelayExample {

  static let module = InsteonAddress(0x4A, 0x5B, 0x01)

  static let fixedModule = InsteonAddress(0x4A, 0x5B, 0x02)

  static let dimmer = InsteonAddress(0x4A, 0x5B, 0x03)

  static let stranger = InsteonAddress(0x4A, 0x5B, 0x04)

  /// A module whose catalog gives a command that turns momentary off but none that turns it
  /// back on.
  static let oneWayModule = InsteonAddress(0x4A, 0x5B, 0x05)

  static let oneWayModuleIdentity = ReportedIdentity(category: 0x07, subcategory: 0x63, firmwareVersion: 0x41)

  /// A module whose relay group type gives no Off.
  static let noOffModule = InsteonAddress(0x4A, 0x5B, 0x06)

  static let noOffModuleIdentity = ReportedIdentity(category: 0x07, subcategory: 0x64, firmwareVersion: 0x41)

  /// A module whose relay group type gives no On.
  static let noOnModule = InsteonAddress(0x4A, 0x5B, 0x07)

  static let noOnModuleIdentity = ReportedIdentity(category: 0x07, subcategory: 0x65, firmwareVersion: 0x41)

  /// A module whose catalog gives a command that turns momentary on but none that turns it
  /// off, so clearing it is refused before anything is sent.
  static let noClearModule = InsteonAddress(0x4A, 0x5B, 0x08)

  static let noClearModuleIdentity = ReportedIdentity(category: 0x07, subcategory: 0x66, firmwareVersion: 0x41)

  static let moduleIdentity = ReportedIdentity(category: 0x07, subcategory: 0x60, firmwareVersion: 0x41)

  static let fixedModuleIdentity = ReportedIdentity(category: 0x07, subcategory: 0x61, firmwareVersion: 0x41)

  static let dimmerIdentity = ReportedIdentity(category: 0x01, subcategory: 0x62, firmwareVersion: 0x41)

  /// The momentary flag's bit, and its Set Operating Flags cmd2 values.
  static let momentary: (bit: UInt8, on: UInt8, off: UInt8) = (0x08, 0x06, 0x07)

  /// The flag that makes both On and Off pulse a momentary relay.
  static let bothCommands: (bit: UInt8, on: UInt8, off: UInt8) = (0x10, 0x12, 0x13)

  static let operatingFlags: [OperatingFlag] = [
    OperatingFlag(name: "momentary", summary: "The relay closes for a moment, then opens.", query: .operatingFlags, bit: momentary.bit, on: momentary.on, off: momentary.off, label: "Momentary relay"),
    OperatingFlag(
      name: "momentaryOnBothCommands",
      summary: "Both On and Off close the momentary relay.",
      query: .operatingFlags,
      bit: bothCommands.bit,
      on: bothCommands.on,
      off: bothCommands.off,
      label: "Momentary on On and Off"
    )
  ]

  static let readStatus = DeviceStandardCommand(
    name: "readStatus",
    summary: "Reads whether the relay is on.",
    command1: 0x19,
    command2: .fixed(0x00),
    reply: MessageField(name: "relayState", summary: "0x00 when off.", location: .command2)
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
    ]
  )

  static func moduleCommands(id: CommandSetID, linkingChanges: [LinkingChange], flags: [OperatingFlag] = operatingFlags, relayType: GroupType = relay) -> CommandSet {

    CommandSet(
      id: id,
      name: "Example I/O module",
      summary: "A relay with a momentary mode.",
      operatingFlags: flags,
      standardCommands: [ControlExample.lightOn, ControlExample.lightOff, readStatus],
      groupTypes: [relayType],
      linkingChanges: linkingChanges
    )

  }

  static let commands: CommandSet = moduleCommands(id: "exampleIO", linkingChanges: [LinkingChange(flag: "momentary")])

  static let fixedCommands: CommandSet = moduleCommands(id: "exampleFixedIO", linkingChanges: [])

  static let oneWayCommands: CommandSet = moduleCommands(
    id: "exampleOneWayIO",
    linkingChanges: [LinkingChange(flag: "momentary")],
    flags: [OperatingFlag(name: "momentary", summary: "The relay closes for a moment, then opens.", query: .operatingFlags, bit: momentary.bit, off: momentary.off, label: "Momentary relay")]
  )

  /// The relay group type with only the action named.
  static func relay(onlyAction name: SettingName) -> GroupType {

    var type: GroupType = relay

    type.actions = relay.actions.filter { (action: GroupType.Action) -> Bool in action.name == name }

    return type

  }

  static let noOffCommands: CommandSet = moduleCommands(id: "exampleNoOffIO", linkingChanges: [LinkingChange(flag: "momentary")], relayType: relay(onlyAction: "on"))

  static let noOnCommands: CommandSet = moduleCommands(id: "exampleNoOnIO", linkingChanges: [LinkingChange(flag: "momentary")], relayType: relay(onlyAction: "off"))

  static let noClearCommands: CommandSet = moduleCommands(
    id: "exampleNoClearIO",
    linkingChanges: [LinkingChange(flag: "momentary")],
    flags: [OperatingFlag(name: "momentary", summary: "The relay closes for a moment, then opens.", query: .operatingFlags, bit: momentary.bit, on: momentary.on, label: "Momentary relay")]
  )

  static let dimmerCommands = CommandSet(
    id: "exampleRelayDimmer",
    name: "Example dimmer",
    summary: "A dimmer.",
    standardCommands: [ControlExample.lightOn, ControlExample.lightOff, ControlExample.readLevel],
    groupTypes: [ControlExample.light]
  )

  static func profile(_ model: ProductModel, _ identity: ReportedIdentity, commands: CommandSet, type: SettingName) -> DeviceProfile {

    DeviceProfile(
      model: model,
      name: "Example \(model)",
      identities: [DeviceIdentity(category: identity.category, subcategory: identity.subcategory)],
      engines: [DeviceEngine(engine: .i2cs, category: identity.category, subcategory: identity.subcategory)],
      commandSets: [CommandSetEntry(commandSet: commands.id, category: identity.category, subcategory: identity.subcategory)],
      groups: [DeviceProfile.Group(number: 1, name: "Sensor and relay", role: .both, type: type)]
    )

  }

  static let catalog = DeviceCatalog(
    profiles: [
      profile("9601", moduleIdentity, commands: commands, type: "relay"),
      profile("9602", fixedModuleIdentity, commands: fixedCommands, type: "relay"),
      profile("9603", dimmerIdentity, commands: dimmerCommands, type: "light"),
      profile("9604", oneWayModuleIdentity, commands: oneWayCommands, type: "relay"),
      profile("9605", noOffModuleIdentity, commands: noOffCommands, type: "relay"),
      profile("9606", noOnModuleIdentity, commands: noOnCommands, type: "relay"),
      profile("9607", noClearModuleIdentity, commands: noClearCommands, type: "relay")
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

  func network(_ modem: InMemoryModem, identities: [InsteonAddress: ReportedIdentity] = RelayExample.identities) -> DeviceNetwork {

    let times: FixedTimes = self.times

    return DeviceNetwork(
      modem: modem,
      catalog: RelayExample.catalog,
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

    for flag in [RelayExample.momentary, RelayExample.bothCommands] {

      await modem.setOperatingFlagCommand(flag.on, bit: flag.bit, isSet: true, of: device)
      await modem.setOperatingFlagCommand(flag.off, bit: flag.bit, isSet: false, of: device)

    }

    await modem.setMomentaryBit(RelayExample.momentary.bit, of: device)

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

  /// The steps that put the relay back and set the momentary flag back, in order.
  var returnAndRestore: [InMemoryModem.LinkingStep] {

    [step(0x13, 0x00), step(0x20, RelayExample.momentary.on, extended: true), step(0x1F, 0x00)]

  }

  /// The status request the network's cache sends for the database delta before it reads the
  /// relay's database to check its record: the last step of a link that checks it.
  var recordCheck: InMemoryModem.LinkingStep {

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

  @Test func clearsMomentarySetsTheRelayLinksVerifiesAndPutsItAllBack() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.momentary.bit)
    let recorder = LinkingRecorder()

    let result: DeviceLinkingResult = try await linkRelay(modem, .on, observer: recorder)

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    // The flags and status are read, the flag cleared and read back, the relay set and
    // confirmed, then the link is made, the relay put back and the flag set back.
    #expect(Array(steps.prefix(6)) == [
      step(0x1F, 0x00),
      step(0x19, 0x00),
      step(0x20, RelayExample.momentary.off, extended: true),
      step(0x1F, 0x00),
      step(0x11, 0xFF),
      step(0x19, 0x00)
    ])
    #expect(steps.dropFirst(6).dropLast(3).contains(.modem(.controller, 0x02)))
    // The record is checked after everything is put back.
    #expect(Array(steps.suffix(4)) == returnAndRestore + [recordCheck])
    // The device recorded on, and the relay is off again, as it was.
    #expect(await modem.databases[module]?.values.first?.data1 == 0xFF)
    #expect(await modem.levels[module] == 0x00)
    #expect(await modem.operatingFlags[module] == RelayExample.momentary.bit)
    #expect(result.links.map(\.mode) == [.controller])

    let link: RelayStateLink? = result.relayState

    #expect(link?.groupOn == .on)
    #expect(link?.groupOff == .off)
    #expect(link?.recordedData1 == 0xFF)
    #expect(link?.recordFailure == nil)
    #expect(link?.clearedFlag == "momentary")
    #expect(link?.isRestored == true)
    #expect(link?.isMomentary == true)
    #expect(link?.restoreFailures.isEmpty == true)
    #expect(await recorder.lines == [
      "relay state: clearing momentary \(module)",
      "relay state: setting \(module) on",
      "relay state: \(module) confirmed on",
      "linking remotely \(module) as controller",
      "linked \(module) group 2 controller first",
      "relay state: returning \(module) off",
      "relay state: restoring momentary \(module)",
      "relay state: restored momentary \(module)",
      "relay state: group on gives on, off gives off, momentary true, pulses false"
    ])

  }

  @Test func sendsNothingAndWritesNoFlagForAMomentaryRelayAlreadyOff() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.momentary.bit)
    let recorder = LinkingRecorder()

    let result: DeviceLinkingResult = try await linkRelay(modem, .off, observer: recorder)

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    #expect(Array(steps.prefix(2)) == [step(0x1F, 0x00), step(0x19, 0x00)])
    #expect(!writesFlags(steps))
    #expect(!steps.contains(step(0x13, 0x00)))
    #expect(!steps.contains(step(0x11, 0xFF)))
    #expect(result.relayState?.clearedFlag == nil)
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
    // A relay that isn't momentary keeps the state it was linked in.
    #expect(await modem.levels[module] == 0x00)
    #expect(await modem.databases[module]?.values.first?.data1 == 0x00)
    #expect(result.relayState?.groupOn == .off)
    #expect(result.relayState?.groupOff == .on)
    #expect(result.relayState?.isMomentary == false)

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

  @Test func linksWithoutSwitchingAnythingWhenBothCommandsPulse() async throws {

    let flags: UInt8 = RelayExample.momentary.bit | RelayExample.bothCommands.bit
    let modem: InMemoryModem = await modem(flags: flags)
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
    #expect(result.relayState?.pulsesOnBothCommands == true)
    #expect(result.relayState?.clearedFlag == nil)
    #expect(result.relayState?.recordFailure == nil)
    #expect(Array(await recorder.lines.prefix(1)) == ["relay state: \(module) ignores the state"])

  }

  // MARK: - Planning

  @Test func plansWhatItWillSwitchAndSendsOnlyReads() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.momentary.bit)
    let linking: DeviceLinkingCoordinator = network(modem).linking

    let plan: RelayLinkPlan = try await linking.planRelayLink(module, recording: .on, observer: LinkingRecorder())

    #expect(plan.state == .on)
    #expect(plan.before == .off)
    #expect(plan.switchesRelay)
    #expect(plan.clearedFlag == "momentary")
    #expect(plan.opensAfterLinking)
    #expect(!plan.switchesBackOnFailure)
    #expect(!plan.ignoresState)
    #expect(await modem.linkingSteps == [step(0x1F, 0x00), step(0x19, 0x00)])

  }

  @Test func plansNothingToSwitchForARelayAlreadyInTheStateOrOneThatOnlyPulses() async throws {

    let still: RelayLinkPlan = try await network(await modem(flags: 0x00, relay: 0xFF)).linking.planRelayLink(module, recording: .on, observer: LinkingRecorder())
    let latching: RelayLinkPlan = try await network(await modem(flags: 0x00)).linking.planRelayLink(module, recording: .on, observer: LinkingRecorder())
    let pulsing: RelayLinkPlan = try await network(await modem(flags: RelayExample.momentary.bit | RelayExample.bothCommands.bit)).linking.planRelayLink(module, recording: .on, observer: LinkingRecorder())

    #expect(!still.switchesRelay)
    #expect(latching.switchesRelay)
    #expect(latching.switchesBackOnFailure)
    #expect(latching.clearedFlag == nil)
    #expect(pulsing.ignoresState)
    #expect(!pulsing.switchesRelay)
    #expect(pulsing.clearedFlag == nil)

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

    let modem: InMemoryModem = await modem(flags: RelayExample.momentary.bit)
    // The relay pulses whatever linking clears, so it never reads on.
    await modem.setMomentaryBit(0x80, of: module)
    await modem.setOperatingFlags(RelayExample.momentary.bit | 0x80, of: module)
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
    #expect(await modem.operatingFlags[module] == RelayExample.momentary.bit | 0x80)

  }

  @Test func putsEverythingBackWhenTheLinkIsCanceled() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.momentary.bit)
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
    #expect(await modem.operatingFlags[module] == RelayExample.momentary.bit)
    #expect(await modem.levels[module] == 0x00)

  }

  @Test func setsTheFlagBackWhenCanceledWhileItsCleared() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.momentary.bit)
    let clear = Command(command1: 0x20, command2: RelayExample.momentary.off)
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
    #expect(Array(steps.suffix(2)) == [step(0x20, RelayExample.momentary.on, extended: true), step(0x1F, 0x00)])
    #expect(await modem.operatingFlags[module] == RelayExample.momentary.bit)

  }

  @Test func putsEverythingBackWhenAnotherDeviceLinks() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.momentary.bit)
    let other = InsteonAddress(0x4A, 0x5B, 0x09)
    // Another device is waiting in linking mode when the modem starts.
    await modem.pressSetButton(of: other)

    await #expect(throws: LinkMismatch.self) {

      _ = try await linkRelay(modem, .on)

    }

    #expect(Array(await modem.linkingSteps.suffix(3)) == returnAndRestore)
    #expect(await modem.operatingFlags[module] == RelayExample.momentary.bit)

  }

  @Test func refusesTheSETButtonWhenEnterLinkingModeFails() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.momentary.bit)
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

    let modem: InMemoryModem = await modem(flags: RelayExample.momentary.bit)
    let module: InsteonAddress = self.module
    let restore = Command(command1: 0x20, command2: RelayExample.momentary.on)
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
    #expect(result.relayState?.isMomentary == false)

    guard case let .flagNotRestored(device, flag, reason)? = result.relayState?.restoreFailures.first else {

      Issue.record("Expected the flag not to be restored, got \(String(describing: result.relayState?.restoreFailures))")

      return

    }

    #expect(device == module)
    #expect(flag == "momentary")
    #expect(reason is ModemError)
    #expect(await recorder.lines.contains("relay state: failed \(module)"))

  }

  @Test func saysARestoreThatWasWrittenButNotReadBackIsUnconfirmed() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.momentary.bit)
    let module: InsteonAddress = self.module
    let restore = Command(command1: 0x20, command2: RelayExample.momentary.on)
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
    #expect(await modem.operatingFlags[module] == RelayExample.momentary.bit)
    #expect(await modem.linkingSteps.filter { $0 == step(0x20, RelayExample.momentary.on, extended: true) }.count == 2)

    guard case let .flagRestoreUnconfirmed(device, flag, _)? = result.relayState?.restoreFailures.first else {

      Issue.record("Expected the restore to be unconfirmed, got \(String(describing: result.relayState?.restoreFailures))")

      return

    }

    #expect(device == module)
    #expect(flag == "momentary")

  }

  @Test func reportsAnotherFlagThatChangedWhileItLinked() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.momentary.bit)
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
    #expect(before == RelayExample.momentary.bit)
    #expect(after == RelayExample.momentary.bit | 0x02)

  }

  // MARK: - A momentary relay read mid-pulse

  @Test func leavesAMomentaryRelayReadOnMidPulseOpenWhenRecordingOff() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.momentary.bit, relay: 0xFF)

    let result: DeviceLinkingResult = try await linkRelay(modem, .off)

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    #expect(!steps.contains(step(0x11, 0xFF)))
    #expect(steps.contains(step(0x13, 0x00)))
    #expect(Array(steps.suffix(3)) == [step(0x20, RelayExample.momentary.on, extended: true), step(0x1F, 0x00), recordCheck])
    #expect(await modem.levels[module] == 0x00)
    #expect(await modem.operatingFlags[module] == RelayExample.momentary.bit)
    #expect(result.relayState?.recordedData1 == 0x00)

  }

  @Test func opensAMomentaryRelayReadOnMidPulseAfterRecordingOn() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.momentary.bit, relay: 0xFF)

    let result: DeviceLinkingResult = try await linkRelay(modem, .on)

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    // On once, to hold it, and Off once the link is made: never On again.
    #expect(steps.filter { $0 == step(0x11, 0xFF) }.count == 1)
    #expect(Array(steps.suffix(4)) == returnAndRestore + [recordCheck])
    #expect(await modem.levels[module] == 0x00)
    #expect(await modem.operatingFlags[module] == RelayExample.momentary.bit)
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

    #expect(await modem.linkingSteps.last == step(0x13, 0x00))
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

    let modem: InMemoryModem = await modem(flags: RelayExample.momentary.bit)
    let restore = Command(command1: 0x20, command2: RelayExample.momentary.on)
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
    #expect(await modem.operatingFlags[module] == RelayExample.momentary.bit)
    #expect(await modem.databaseReads[module] == nil)

  }

  @Test func retriesTheRelaysReturnThenReportsIt() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.momentary.bit)
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
    #expect(await modem.operatingFlags[module] == RelayExample.momentary.bit)

    guard case let .relayNotReturned(device, state, _)? = result.relayState?.restoreFailures.first else {

      Issue.record("Expected the relay not to be returned, got \(String(describing: result.relayState?.restoreFailures))")

      return

    }

    #expect(device == module)
    #expect(state == .off)

  }

  @Test func saysARestoreIsUnconfirmedWhenAnyWriteWasAcknowledged() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.momentary.bit)
    let module: InsteonAddress = self.module
    let restore = Command(command1: 0x20, command2: RelayExample.momentary.on)
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

    #expect(await modem.operatingFlags[module] == RelayExample.momentary.bit)

    guard case .flagRestoreUnconfirmed? = result.relayState?.restoreFailures.first else {

      Issue.record("Expected the restore to be unconfirmed, got \(String(describing: result.relayState?.restoreFailures))")

      return

    }

  }

  @Test func refusesBeforeClearingAFlagItCouldntSetBack() async throws {

    let device: InsteonAddress = RelayExample.oneWayModule
    let modem: InMemoryModem = await modem(device, flags: RelayExample.momentary.bit)

    await #expect(throws: DeviceControlError.self) {

      _ = try await linkRelay(modem, .on, device: device)

    }

    #expect(await modem.linkingSteps == [step(0x1F, 0x00, to: device), step(0x19, 0x00, to: device)])
    #expect(await modem.operatingFlags[device] == RelayExample.momentary.bit)

  }

  @Test func leavesALatchingRelayAloneWhenItsStatusDisagrees() async throws {

    let modem: InMemoryModem = await modem(flags: 0x80)
    // The relay opens again, though the catalog doesn't call it momentary.
    await modem.setMomentaryBit(0x80, of: module)

    await expectRefusal({ _ = try await linkRelay(modem, .on) }) { (error: RelayStateLinkingError) -> Bool in

      if case .relayNotConfirmed = error {

        return true

      }

      return false

    }

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    #expect(steps.filter { $0 == step(0x11, 0xFF) }.count == 1)
    #expect(!steps.contains(step(0x13, 0x00)))

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

    await expectRefusal({ _ = try await linkRelay(modem, .on) }) { (error: RelayStateLinkingError) -> Bool in

      if case .remoteLinkingFailed = error {

        return true

      }

      return false

    }

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    #expect(steps.last == recordCheck)
    #expect(!steps.contains(step(0x13, 0x00)))

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
    let recorder = LinkingRecorder()

    await expectRefusal({ _ = try await linkRelay(modem, .on, observer: recorder) }) { (error: RelayStateLinkingError) -> Bool in

      if case .remoteLinkingFailed = error {

        return true

      }

      return false

    }

    #expect(await modem.linkingSteps.last == step(0x13, 0x00))
    #expect(await recorder.lines.suffix(2) == ["relay state: returning \(module) off", "relay state: failed \(module)"])

  }

  @Test func refusesBeforeChangingAnythingWhenTheRelayCantBeOpenedAfterward() async throws {

    let device: InsteonAddress = RelayExample.noOffModule
    let momentary: InMemoryModem = await modem(device, flags: RelayExample.momentary.bit)

    await #expect(throws: DeviceControlError.self) {

      _ = try await linkRelay(momentary, .on, device: device)

    }

    #expect(await momentary.linkingSteps == [step(0x1F, 0x00, to: device), step(0x19, 0x00, to: device)])

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
    let modem: InMemoryModem = await modem(device, flags: RelayExample.momentary.bit)

    await #expect(throws: DeviceControlError.self) {

      _ = try await linkRelay(modem, .on, device: device)

    }

    #expect(!writesFlags(await modem.linkingSteps))
    #expect(await modem.operatingFlags[device] == RelayExample.momentary.bit)

  }

  // MARK: - Refusing a relay state

  @Test func refusesMomentaryTheCatalogDoesntLetLinkingChange() async throws {

    let device: InsteonAddress = RelayExample.fixedModule
    let modem: InMemoryModem = await modem(device, flags: RelayExample.momentary.bit)
    let network: DeviceNetwork = self.network(modem)

    await expectRefusal({ _ = try await network.linking.linkRelay(device, recording: .on, group: 2, observer: LinkingRecorder()) }) { (error: RelayStateLinkingError) -> Bool in

      guard case let .momentaryNotChangeable(refused, flag) = error else {

        return false

      }

      return refused == device && flag == "momentary"

    }

    // The flags and status were read, and nothing else was sent.
    #expect(await modem.linkingSteps == [step(0x1F, 0x00, to: device), step(0x19, 0x00, to: device)])
    #expect(await modem.operatingFlags[device] == RelayExample.momentary.bit)

  }

  @Test func refusesAnUnlinkedDeviceAndSaysToLinkItFirst() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.momentary.bit)
    // An i2CS device rejects the modem's direct commands until it holds a link to it.
    await modem.setUnlinked(module)

    await expectRefusal({ _ = try await linkRelay(modem, .on) }) { (error: RelayStateLinkingError) -> Bool in

      guard case let .notLinkedToModem(device) = error else {

        return false

      }

      return device == module

    }

    #expect(await modem.linkingSteps == [step(0x1F, 0x00)])
    #expect(await modem.operatingFlags[module] == RelayExample.momentary.bit)

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
    await modem.setIdentity(SetButtonPressed(sender: stranger, role: .responder, category: 0x07, subcategory: 0x7F, firmwareVersion: 0x41))

    await expectRefusal({ _ = try await linkRelay(modem, .on, device: stranger) }) { (error: RelayStateLinkingError) -> Bool in

      guard case let .notDescribed(device) = error else {

        return false

      }

      return device == stranger

    }

    #expect(changes(in: await modem.linkingSteps).isEmpty)

  }

  @Test func failsWithoutWritingAnythingWhenTheDeviceDoesntAnswer() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.momentary.bit)
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
    #expect(await modem.operatingFlags[module] == RelayExample.momentary.bit)
    #expect(await modem.databases[module] == nil)

  }

  // MARK: - Without a relay state

  @Test func plainLinkNeverTouchesTheRelayOrItsFlags() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.momentary.bit)

    let result: DeviceLinkingResult = try await network(modem).linking.link(module, as: .controller, group: 2, twoWay: .never, observer: LinkingRecorder())

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    #expect(result.relayState == nil)
    #expect(!steps.contains { (step: InMemoryModem.LinkingStep) -> Bool in

      if case let .device(_, command, _) = step {

        return [0x11, 0x13, 0x19, 0x1F, 0x20].contains(command.command1)

      }

      return false

    })
    #expect(await modem.operatingFlags[module] == RelayExample.momentary.bit)

  }

  // MARK: - By writing ALL-Link databases

  @Test func writesTheRelayStateAsData1OfTheResponderRecord() async throws {

    let device: InsteonAddress = DatabaseLinkingExample.module
    let modem = InMemoryModem()
    await modem.setEngine(.i2cs, of: device)
    await modem.setIdentity(SetButtonPressed(sender: device, role: .responder, category: 0x02, subcategory: 0x6F, firmwareVersion: 0x41))
    let log: OperationLog = await OperationLog.logging(modem)
    let linking: DeviceLinkingCoordinator = DeviceNetwork(modem: modem, catalog: DatabaseLinkingExample.catalog, clock: clock).linking

    let plan: DatabaseLinkPlan = try await linking.planDatabaseLink(device, relayState: .off)

    let responder: DatabaseLinkStep? = plan.deviceSteps.first { (step: DatabaseLinkStep) -> Bool in step.kind == .addDeviceRecord && !step.record.isController }

    #expect(plan.relayState == .off)
    #expect(responder?.record.data == [0x00, 0x1C, 0x01])
    // Planning reads; it neither sets the relay nor writes a flag.
    #expect(log.standardCommands == [0x0D, 0x10])
    #expect(log.writesAndExtendedMessages == 0)

    let result: DatabaseLinkResult = try await linking.apply(plan)

    #expect(result.isComplete)
    #expect(await modem.record(of: device, at: 0x0FFF).data1 == 0x00)

  }

  @Test func refusesADatabaseRelayStateWhenTheRecordInPlaceHoldsTheOtherState() async throws {

    let device: InsteonAddress = DatabaseLinkingExample.module
    let modem = InMemoryModem()
    await modem.setEngine(.i2cs, of: device)
    await modem.setIdentity(SetButtonPressed(sender: device, role: .responder, category: 0x02, subcategory: 0x6F, firmwareVersion: 0x41))
    await modem.setDatabase([
      0x0FFF: AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 0x00, address: modem.address, data1: 0xFF, data2: 0x1C, data3: 0x01)
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
    await modem.setIdentity(SetButtonPressed(sender: dimmer, role: .responder, category: 0x01, subcategory: 0x62, firmwareVersion: 0x41))
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

    let description: DeviceDescription = RelayExample.catalog.describe(category: 0x07, subcategory: 0x60, firmwareVersion: 0x41)

    #expect(DeviceLinkingCoordinator.recordsRelayState(description, deviceGroup: 1))
    // The catalog gives no type for group 2, so its record isn't the relay's.
    #expect(!DeviceLinkingCoordinator.recordsRelayState(description, deviceGroup: 2))

  }

  // MARK: - Values

  @Test func describesEachRefusalNamingTheDeviceAndFlag() {

    let refused = RelayStateLinkingError.momentaryNotChangeable(module, flag: "momentary")
    let notRestored = RelayStateLinkingError.flagNotRestored(module, flag: "momentary", reason: ModemError.deviceTimedOut(module))
    let unconfirmed = RelayStateLinkingError.flagRestoreUnconfirmed(module, flag: "momentary", reason: ModemError.deviceTimedOut(module))
    let inPlace = RelayStateLinkingError.recordInPlace(module, group: 0, data1: 0xFF)

    #expect(InsteonErrorDescription.message(for: refused) == refused.description)
    #expect(refused.description.hasPrefix("\(module)'s momentary flag is on"))
    #expect(notRestored.description.hasPrefix("\(module)'s momentary flag wasn't set back on: "))
    #expect(unconfirmed.description.hasPrefix("\(module)'s momentary flag was written back on, but it couldn't be read back to confirm: "))
    #expect(inPlace.description.contains("Data 1 0xFF"))

  }

  @Test func givesEachStateItsData1AndItsOpposite() {

    #expect(RelayState.on.data1 == 0xFF)
    #expect(RelayState.off.data1 == 0x00)
    #expect(RelayState.on.opposite == .off)
    #expect(RelayState.off.opposite == .on)

  }

}

/// Whether the momentary flag's restore has begun, for a test that fails what follows it.
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
