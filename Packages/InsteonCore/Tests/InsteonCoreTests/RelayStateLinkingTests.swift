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

  static func moduleCommands(id: CommandSetID, linkingChanges: [LinkingChange]) -> CommandSet {

    CommandSet(
      id: id,
      name: "Example I/O module",
      summary: "A relay with a momentary mode.",
      operatingFlags: operatingFlags,
      standardCommands: [ControlExample.lightOn, ControlExample.lightOff, readStatus],
      groupTypes: [relay],
      linkingChanges: linkingChanges
    )

  }

  static let commands: CommandSet = moduleCommands(id: "exampleIO", linkingChanges: [LinkingChange(flag: "momentary")])

  static let fixedCommands: CommandSet = moduleCommands(id: "exampleFixedIO", linkingChanges: [])

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
      profile("9603", dimmerIdentity, commands: dimmerCommands, type: "light")
    ],
    commandSets: [commands, fixedCommands, dimmerCommands]
  )

  static let identities: [InsteonAddress: ReportedIdentity] = [
    module: moduleIdentity,
    fixedModule: fixedModuleIdentity,
    dimmer: dimmerIdentity
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

  // MARK: - Linking with a relay state

  @Test func clearsMomentarySetsTheRelayLinksAndRestoresTheFlag() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.momentary.bit)
    let recorder = LinkingRecorder()

    let result: DeviceLinkingResult = try await network(modem).linking.link(module, as: .controller, group: 2, twoWay: .never, relayState: .on, observer: recorder)

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    // The flag is cleared and read back, the relay set and confirmed, then the link is made
    // and the flag set back and read back.
    #expect(Array(steps.prefix(6)) == [
      step(0x1F, 0x00),
      step(0x20, RelayExample.momentary.off, extended: true),
      step(0x1F, 0x00),
      step(0x19, 0x00),
      step(0x11, 0xFF),
      step(0x19, 0x00)
    ])
    #expect(steps.dropFirst(6).dropLast(2).contains(.modem(.controller, 0x02)))
    #expect(steps.suffix(2) == [step(0x20, RelayExample.momentary.on, extended: true), step(0x1F, 0x00)])
    // The relay held its state through the link, and the device recorded it as Data 1.
    #expect(await modem.databases[module]?.values.first?.data1 == 0xFF)
    #expect(await modem.operatingFlags[module] == RelayExample.momentary.bit)
    #expect(result.links.map(\.mode) == [.controller])
    #expect(result.relayState?.groupOn == .on)
    #expect(result.relayState?.groupOff == .off)
    #expect(result.relayState?.isMomentary == true)
    #expect(result.relayState?.restoreFailure == nil)
    #expect(await recorder.lines == [
      "relay state: clearing momentary \(module)",
      "relay state: setting \(module) on",
      "relay state: \(module) confirmed on",
      "linking remotely \(module) as controller",
      "linked \(module) group 2 controller first",
      "relay state: restoring momentary \(module)",
      "relay state: restored momentary \(module)",
      "relay state: group on gives on, off gives off, momentary true, pulses false"
    ])

  }

  @Test func recordsOffSoAGroupOffTurnsTheRelayOn() async throws {

    let modem: InMemoryModem = await modem(flags: 0x00, relay: 0xFF)

    let result: DeviceLinkingResult = try await network(modem).linking.link(module, as: .controller, group: 2, twoWay: .never, relayState: .off, observer: LinkingRecorder())

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    #expect(steps.contains(step(0x13, 0x00)))
    // Momentary is off, so no flag is written.
    #expect(!steps.contains { (step: InMemoryModem.LinkingStep) -> Bool in

      if case let .device(_, command, _) = step {

        return command.command1 == 0x20

      }

      return false

    })
    #expect(await modem.databases[module]?.values.first?.data1 == 0x00)
    #expect(result.relayState?.groupOn == .off)
    #expect(result.relayState?.groupOff == .on)
    #expect(result.relayState?.isMomentary == false)

  }

  @Test func skipsTheCommandForARelayAlreadyInTheStateButConfirmsIt() async throws {

    let modem: InMemoryModem = await modem(flags: 0x00, relay: 0xFF)
    let recorder = LinkingRecorder()

    _ = try await network(modem).linking.link(module, as: .controller, group: 2, twoWay: .never, relayState: .on, observer: recorder)

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    #expect(Array(steps.prefix(2)) == [step(0x1F, 0x00), step(0x19, 0x00)])
    #expect(!steps.contains(step(0x11, 0xFF)))
    #expect(Array(await recorder.lines.prefix(1)) == ["relay state: \(module) already on"])

  }

  @Test func linksWithTheStateWhenBothCommandsPulseAndSaysSo() async throws {

    let flags: UInt8 = RelayExample.momentary.bit | RelayExample.bothCommands.bit
    let modem: InMemoryModem = await modem(flags: flags)
    let recorder = LinkingRecorder()

    let result: DeviceLinkingResult = try await network(modem).linking.link(module, as: .controller, group: 2, twoWay: .never, relayState: .on, observer: recorder)

    #expect(result.relayState?.pulsesOnBothCommands == true)
    #expect(await modem.operatingFlags[module] == flags)
    #expect(await recorder.lines.last == "relay state: group on gives on, off gives off, momentary true, pulses true")

  }

  // MARK: - Restoring the flag

  @Test func restoresTheFlagAndLinksNothingWhenTheRelayIsntConfirmed() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.momentary.bit)
    // The relay pulses whatever linking clears, so it never reads on.
    await modem.setMomentaryBit(0x80, of: module)
    await modem.setOperatingFlags(RelayExample.momentary.bit | 0x80, of: module)
    let recorder = LinkingRecorder()

    await #expect {

      _ = try await network(modem).linking.link(module, as: .controller, group: 2, twoWay: .never, relayState: .on, observer: recorder)

    } throws: { (error: any Error) -> Bool in

      guard case let .relayNotConfirmed(device, requested)? = error as? RelayStateLinkingError else {

        return false

      }

      return device == module && requested == .on

    }

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    #expect(!steps.contains(.modem(.controller, 0x02)))
    #expect(steps.suffix(2) == [step(0x20, RelayExample.momentary.on, extended: true), step(0x1F, 0x00)])
    #expect(await modem.operatingFlags[module] == RelayExample.momentary.bit | 0x80)
    #expect(await recorder.lines.suffix(2) == ["relay state: restoring momentary \(module)", "relay state: restored momentary \(module)"])

  }

  @Test func restoresTheFlagWhenTheLinkIsCanceled() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.momentary.bit)
    await modem.setSilent(module)
    let network: DeviceNetwork = self.network(modem)
    let linking = Task { () async throws -> DeviceLinkingResult in

      try await network.linking.link(module, as: .controller, group: 2, twoWay: .never, relayState: .on, observer: LinkingRecorder())

    }

    await clock.waitForSleeper(until: Linker.defaultRemoteLinkingTimeout)
    linking.cancel()

    await #expect(throws: CancellationError.self) {

      _ = try await linking.value

    }

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    #expect(steps.suffix(2) == [step(0x20, RelayExample.momentary.on, extended: true), step(0x1F, 0x00)])
    #expect(await modem.operatingFlags[module] == RelayExample.momentary.bit)

  }

  @Test func reportsAFlagThatWasntRestoredAndKeepsTheLink() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.momentary.bit)
    let module: InsteonAddress = self.module
    let restore = Command(command1: 0x20, command2: RelayExample.momentary.on)
    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      if case let .extendedRequest(message) = operation, message.command == restore {

        throw ModemError.deviceTimedOut(module)

      }

    }
    let recorder = LinkingRecorder()

    let result: DeviceLinkingResult = try await network(modem).linking.link(module, as: .controller, group: 2, twoWay: .never, relayState: .on, observer: recorder)

    #expect(result.links.map(\.mode) == [.controller])
    #expect(await modem.operatingFlags[module] == 0x00)

    guard case let .flagNotRestored(device, flag, reason)? = result.relayState?.restoreFailure as? RelayStateLinkingError else {

      Issue.record("Expected the flag not to be restored, got \(String(describing: result.relayState?.restoreFailure))")

      return

    }

    #expect(device == module)
    #expect(flag == "momentary")
    #expect(reason is ModemError)
    #expect(await recorder.lines.contains("relay state: not restored momentary \(module)"))

  }

  // MARK: - Refusing a relay state

  @Test func refusesMomentaryTheCatalogDoesntLetLinkingChange() async throws {

    let device: InsteonAddress = RelayExample.fixedModule
    let modem: InMemoryModem = await modem(device, flags: RelayExample.momentary.bit)

    await #expect {

      _ = try await network(modem).linking.link(device, as: .controller, group: 2, relayState: .on, observer: LinkingRecorder())

    } throws: { (error: any Error) -> Bool in

      guard case let .momentaryNotChangeable(refused, flag)? = error as? RelayStateLinkingError else {

        return false

      }

      return refused == device && flag == "momentary"

    }

    // The flag was read, and nothing else was sent.
    #expect(await modem.linkingSteps == [step(0x1F, 0x00, to: device)])
    #expect(await modem.operatingFlags[device] == RelayExample.momentary.bit)

  }

  @Test func refusesADeviceWhoseMainGroupIsntARelay() async throws {

    let modem = InMemoryModem()
    let dimmer: InsteonAddress = RelayExample.dimmer

    await #expect {

      _ = try await network(modem).linking.link(dimmer, as: .controller, group: 2, relayState: .on, observer: LinkingRecorder())

    } throws: { (error: any Error) -> Bool in

      guard case let .notARelay(device, _)? = error as? RelayStateLinkingError else {

        return false

      }

      return device == dimmer

    }

    #expect(await modem.linkingSteps.isEmpty)
    #expect(await modem.levels[dimmer] == nil)

  }

  @Test func refusesADeviceTheCatalogDoesntDescribe() async throws {

    let modem = InMemoryModem()
    let stranger: InsteonAddress = RelayExample.stranger
    // It rejects the modem, as an i2CS device does until it's linked, so it reports no identity.
    await modem.setUnlinked(stranger)

    await #expect {

      _ = try await network(modem).linking.link(stranger, as: .controller, group: 2, relayState: .on, observer: LinkingRecorder())

    } throws: { (error: any Error) -> Bool in

      guard case let .notDescribed(device)? = error as? RelayStateLinkingError else {

        return false

      }

      return device == stranger

    }

    #expect(changes(in: await modem.linkingSteps).isEmpty)

  }

  @Test func refusesTheModemAsResponder() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.momentary.bit)

    await #expect {

      _ = try await network(modem).linking.link(module, as: .responder, relayState: .on, observer: LinkingRecorder())

    } throws: { (error: any Error) -> Bool in

      guard case let .modemNotController(device)? = error as? RelayStateLinkingError else {

        return false

      }

      return device == module

    }

    #expect(await modem.linkingSteps.isEmpty)

  }

  @Test func failsWithoutWritingAnythingWhenTheDeviceDoesntAnswer() async throws {

    let modem: InMemoryModem = await modem(flags: RelayExample.momentary.bit)
    await modem.setUnanswering(module)

    await #expect {

      _ = try await network(modem).linking.link(module, as: .controller, group: 2, relayState: .on, observer: LinkingRecorder())

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

    await #expect {

      _ = try await linking.planDatabaseLink(device, relayState: .off)

    } throws: { (error: any Error) -> Bool in

      guard case let .recordInPlace(refused, group, data1)? = error as? RelayStateLinkingError else {

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

    await #expect {

      _ = try await linking.planDatabaseLink(dimmer, relayState: .on)

    } throws: { (error: any Error) -> Bool in

      guard case let .notARelay(device, _)? = error as? RelayStateLinkingError else {

        return false

      }

      return device == dimmer

    }

  }

  // MARK: - Values

  @Test func describesEachRefusalNamingTheDeviceAndFlag() {

    let refused = RelayStateLinkingError.momentaryNotChangeable(module, flag: "momentary")
    let notRestored = RelayStateLinkingError.flagNotRestored(module, flag: "momentary", reason: ModemError.deviceTimedOut(module))
    let inPlace = RelayStateLinkingError.recordInPlace(module, group: 0, data1: 0xFF)

    #expect(InsteonErrorDescription.message(for: refused) == refused.description)
    #expect(refused.description.hasPrefix("\(module)'s momentary flag is on"))
    #expect(notRestored.description.hasPrefix("\(module)'s momentary flag wasn't set back as it was: "))
    #expect(inPlace.description.contains("Data 1 0xFF"))

  }

  @Test func givesEachStateItsData1AndItsOpposite() {

    #expect(RelayState.on.data1 == 0xFF)
    #expect(RelayState.off.data1 == 0x00)
    #expect(RelayState.on.opposite == .off)
    #expect(RelayState.off.opposite == .on)

  }

}
