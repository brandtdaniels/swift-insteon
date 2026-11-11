import Foundation
import Testing
@testable import InsteonCore
import InsteonDeviceCatalog
import InsteonLinking
import InsteonLinkingTestSupport
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// Keeping a battery-powered device awake while it links by the catalog's legs, and letting it
/// sleep again, on an in-memory modem.
struct KeepAwakeTests {

  let clock: TestClock = TestClock()

  let times: FixedTimes = FixedTimes()

  /// A made-up contact sensor whose catalog keeps it awake with the extended Set its command
  /// set names, right after its first link, and gives no message to release it.
  static let contact = (address: InsteonAddress(0x5A, 0x6B, 0x01), identity: ReportedIdentity(category: 0x10, subcategory: 0x71, firmwareVersion: 0x41))

  /// A made-up remote, kept awake with its hold-awake flag after its first link, and released
  /// by clearing it.
  static let remote = (address: InsteonAddress(0x5A, 0x6B, 0x02), identity: ReportedIdentity(category: 0x00, subcategory: 0x71, firmwareVersion: 0x37))

  /// A made-up climate sensor, kept awake by Set Operating Flags given by its bytes before it
  /// goes into linking mode, and released the same way.
  static let climate = (address: InsteonAddress(0x5A, 0x6B, 0x03), identity: ReportedIdentity(category: 0x05, subcategory: 0x71, firmwareVersion: 0x41))

  /// The contact sensor's command set: hold awake is an extended Set with D1 `0x01` and D2
  /// `0x04`, and the seconds to remain awake in D3.
  static let contactCommands = CommandSet(
    id: "exampleContact",
    name: "Example contact sensor",
    summary: "A sensor kept awake by an extended Set.",
    extendedCommands: [
      DeviceExtendedCommand(
        name: "holdAwake",
        summary: "Keeps the sensor awake.",
        command: Command(command1: 0x2E, command2: 0x00),
        fixedBytes: [FixedUserDataByte(position: 1, value: 0x01), FixedUserDataByte(position: 2, value: 0x04)],
        parameters: [MessageField(name: "duration", summary: "How long it remains awake.", location: .userData([3]), kind: .number(unit: .seconds), range: 0...255)],
        integrity: .checksum,
        effect: .configuration, isIdempotent: true
      )
    ]
  )

  /// The remote's command set: hold awake is a flag, set with Set Operating Flags `0x06` and
  /// cleared with `0x07`.
  static let remoteCommands = CommandSet(
    id: "exampleRemote",
    name: "Example remote",
    summary: "A remote kept awake by a flag.",
    operatingFlags: [
      OperatingFlag(name: "holdAwake", summary: "The remote remains awake.", query: .operatingFlags, bit: 0x08, on: 0x06, off: 0x07, label: "Hold awake")
    ]
  )

  /// The climate sensor's command set, with no flags: its keep-awake messages are given by
  /// their bytes.
  static let climateCommands = CommandSet(id: "exampleClimate", name: "Example climate sensor", summary: "A sensor kept awake by bytes.")

  /// One leg in which the modem responds to a device's group.
  static func leg(_ group: AllLinkGroupNumber) -> DeviceLifecycle.HubLinking.Leg {

    DeviceLifecycle.HubLinking.Leg(modemRole: .responder, modemGroup: group, deviceGroup: group)

  }

  /// A battery-powered profile linked from a Hub with the device going first.
  static func sleepy(
    model: String,
    name: String,
    identity: ReportedIdentity,
    commands: CommandSet,
    groups: [AllLinkGroupNumber],
    waking: DeviceLifecycle.Procedure? = nil,
    keepAwake: DeviceLifecycle.HubLinking.KeepAwake
  ) -> DeviceProfile {

    DeviceProfile(
      model: ProductModel(rawValue: model),
      name: name,
      identities: [DeviceIdentity(category: identity.category, subcategory: identity.subcategory)],
      commandSets: [CommandSetEntry(commandSet: commands.id, category: identity.category, subcategory: identity.subcategory)],
      isBatteryPowered: true,
      groups: groups.map { (number: AllLinkGroupNumber) -> DeviceProfile.Group in DeviceProfile.Group(number: number, name: "Group \(number.rawValue)", role: .controller) },
      lifecycle: DeviceLifecycle(
        waking: waking,
        fromHub: DeviceLifecycle.HubLinking(
          legs: groups.map(leg),
          isDeviceFirst: true,
          remoteEnterLinkingMode: DeviceLifecycle.HubLinking.RemoteEnterLinkingMode(works: .unknown),
          keepAwake: keepAwake
        )
      )
    )

  }

  /// The made-up catalog of the three sleepy devices.
  static let catalog = DeviceCatalog(
    profiles: [
      sleepy(
        model: "9411",
        name: "Example Contact Sensor",
        identity: contact.identity,
        commands: contactCommands,
        groups: [1],
        keepAwake: DeviceLifecycle.HubLinking.KeepAwake(timing: .afterLinked, send: .command("holdAwake"))
      ),
      sleepy(
        model: "9412",
        name: "Example Remote",
        identity: remote.identity,
        commands: remoteCommands,
        groups: [1],
        keepAwake: DeviceLifecycle.HubLinking.KeepAwake(
          timing: .afterLinked,
          send: .flag(DeviceProfile.Group.Condition(flag: "holdAwake", isSet: true)),
          release: .flag(DeviceProfile.Group.Condition(flag: "holdAwake", isSet: false))
        )
      ),
      sleepy(
        model: "9413",
        name: "Example Climate Sensor",
        identity: climate.identity,
        commands: climateCommands,
        groups: [1, 2, 3, 4],
        waking: DeviceLifecycle.Procedure(steps: [
          DeviceLifecycle.Step(text: "Press the wake button.", action: .press, control: "wake button"),
          DeviceLifecycle.Step(text: "Send Set Operating Flags with cmd2 0x06.", command: "Set Operating Flags")
        ]),
        keepAwake: DeviceLifecycle.HubLinking.KeepAwake(
          timing: .beforeLinking,
          send: .bytes(DeviceLifecycle.HubLinking.RawMessage(command: Command(command1: 0x20, command2: 0x06), isExtended: true, integrity: .checksum, effect: .configuration, isIdempotent: true)),
          release: .bytes(DeviceLifecycle.HubLinking.RawMessage(command: Command(command1: 0x20, command2: 0x07), isExtended: true, integrity: .checksum, effect: .configuration, isIdempotent: true)),
          duration: .seconds(240)
        )
      )
    ],
    commandSets: [contactCommands, remoteCommands, climateCommands]
  )

  func network(_ modem: InMemoryModem, catalog: DeviceCatalog, identities: [InsteonAddress: ReportedIdentity]) -> DeviceNetwork {

    let times: FixedTimes = self.times

    return DeviceNetwork(
      modem: modem,
      catalog: catalog,
      snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: identities)),
      clock: clock,
      now: { () -> Date in times.now() }
    )

  }

  /// A recorder that presses a device's SET button when it's to go first.
  func readying(_ device: InsteonAddress, on modem: InMemoryModem) -> LinkingRecorder {

    LinkingRecorder(readying: { (_: DeviceFirstPrompt) async throws -> Void in

      await modem.pressSetButton(of: device)

    })

  }

  /// The cmd1 and cmd2 of each extended message sent to a device.
  func extendedCommands(to device: InsteonAddress, on modem: InMemoryModem) async -> [Command] {

    await modem.extendedRequests.filter { (request: InMemoryModem.ExtendedRequest) -> Bool in request.device == device }.map(\.command)

  }

  /// A made-up contact sensor whose catalog marks the extended Set that keeps it awake as
  /// destructive, which a catalog build rejects.
  static let wiper = (address: InsteonAddress(0x5A, 0x6B, 0x04), identity: ReportedIdentity(category: 0x10, subcategory: 0x72, firmwareVersion: 0x41))

  static var wiperCommands: CommandSet {

    var commands: CommandSet = contactCommands

    commands.id = "exampleWiper"
    commands.extendedCommands[0].effect = .destructive
    commands.extendedCommands[0].isIdempotent = false

    return commands

  }

  /// The same sensor, kept awake before linking.
  static let earlyWiper = (address: InsteonAddress(0x5A, 0x6B, 0x05), identity: ReportedIdentity(category: 0x10, subcategory: 0x73, firmwareVersion: 0x41))

  static let wiperCatalog = DeviceCatalog(
    profiles: [
      sleepy(
        model: "9414",
        name: "Example Wiping Sensor",
        identity: wiper.identity,
        commands: wiperCommands,
        groups: [1],
        keepAwake: DeviceLifecycle.HubLinking.KeepAwake(timing: .afterLinked, send: .command("holdAwake"))
      ),
      sleepy(
        model: "9415",
        name: "Example Early Wiping Sensor",
        identity: earlyWiper.identity,
        commands: wiperCommands,
        groups: [1],
        keepAwake: DeviceLifecycle.HubLinking.KeepAwake(timing: .beforeLinking, send: .command("holdAwake"))
      )
    ],
    commandSets: [wiperCommands]
  )

  // MARK: - Sending and releasing

  @Test(.timeLimit(.minutes(1))) func keepsAContactSensorAwakeAfterItsFirstLink() async throws {

    let modem = InMemoryModem()
    let (sensor, identity): (InsteonAddress, ReportedIdentity) = Self.contact
    await modem.setEngine(.i2cs, of: sensor)
    let network: DeviceNetwork = self.network(modem, catalog: Self.catalog, identities: [sensor: identity])
    let recorder: LinkingRecorder = readying(sensor, on: modem)

    _ = try await network.linking.link(sensor, as: .controller, observer: recorder)

    let sent: [InMemoryModem.ExtendedRequest] = await modem.extendedRequests.filter { (request: InMemoryModem.ExtendedRequest) -> Bool in request.device == sensor }

    // The command set's holdAwake: extended Set with D1 0x01 and D2 0x04, and the longest
    // time its parameter takes in D3, since the catalog gives no seconds.
    #expect(sent.map(\.command) == [Command(command1: 0x2E, command2: 0x00)])
    #expect(sent.first.map { (request: InMemoryModem.ExtendedRequest) -> [UInt8] in [request.userData[1], request.userData[2], request.userData[3]] } == [0x01, 0x04, 0xFF])

    let lines: [String] = await recorder.lines

    #expect(lines.contains("keep awake: sending \(sensor) afterLinked"))
    #expect(lines.contains("keep awake: sent \(sensor)"))
    // The keep-awake message follows the first link and comes before the link is reported.
    #expect((lines.firstIndex(of: "modem joining 240") ?? Int.max) < (lines.firstIndex(of: "keep awake: sending \(sensor) afterLinked") ?? Int.min))
    // No release message, so none is sent.
    #expect(!lines.contains { (line: String) -> Bool in line.hasPrefix("keep awake: releasing") })

  }

  @Test(.timeLimit(.minutes(1))) func setsAndClearsARemotesHoldAwakeFlag() async throws {

    let modem = InMemoryModem()
    let (remote, identity): (InsteonAddress, ReportedIdentity) = Self.remote
    await modem.setEngine(.i2cs, of: remote)
    let network: DeviceNetwork = self.network(modem, catalog: Self.catalog, identities: [remote: identity])
    let recorder: LinkingRecorder = readying(remote, on: modem)

    let result: DeviceLinkingResult = try await network.linking.link(remote, as: .controller, observer: recorder)

    // Set Operating Flags, extended for the i2CS remote: hold awake on, then off once linked.
    #expect(await extendedCommands(to: remote, on: modem) == [Command(command1: 0x20, command2: 0x06), Command(command1: 0x20, command2: 0x07)])
    #expect(result.links.count == 1)
    #expect(await recorder.lines.suffix(3) == [
      "leg 1 completed group 1 responder",
      "keep awake: releasing \(remote)",
      "keep awake: released \(remote)"
    ])

  }

  @Test(.timeLimit(.minutes(1))) func wakesAClimateSensorAndKeepsItAwakeBeforeLinking() async throws {

    let modem = InMemoryModem()
    let (climate, identity): (InsteonAddress, ReportedIdentity) = Self.climate
    let catalog: DeviceCatalog = Self.catalog
    let network: DeviceNetwork = self.network(modem, catalog: catalog, identities: [climate: identity])
    let recorder: LinkingRecorder = readying(climate, on: modem)
    let wakingSteps: Int = catalog.describe(category: 0x05, subcategory: 0x71, firmwareVersion: 0x41).profile?.lifecycle?.waking?.steps
      .filter { (step: DeviceLifecycle.Step) -> Bool in !step.isOnOtherDevice }.count ?? 0

    let result: DeviceLinkingResult = try await network.linking.link(climate, as: .controller, observer: recorder)

    let lines: [String] = await recorder.lines

    // The message given by its bytes, extended with a checksum: hold awake, then sleep.
    #expect(await extendedCommands(to: climate, on: modem) == [Command(command1: 0x20, command2: 0x06), Command(command1: 0x20, command2: 0x07)])
    #expect(Array(lines.prefix(3)) == [
      "wake \(climate) steps \(wakingSteps)",
      "keep awake: sending \(climate) beforeLinking",
      "keep awake: sent \(climate)"
    ])
    #expect(lines.suffix(2) == ["keep awake: releasing \(climate)", "keep awake: released \(climate)"])
    // It's kept awake before the modem starts ALL-Linking for its first leg.
    #expect(await modem.linkingSteps.first == .modem(.responder, 0x01))
    #expect(result.links.map(\.group.rawValue) == [0x01, 0x02, 0x03, 0x04])

  }

  @Test(.timeLimit(.minutes(1))) func releasesTheDeviceWhenALaterLegFails() async throws {

    let modem = InMemoryModem()
    let (climate, identity): (InsteonAddress, ReportedIdentity) = Self.climate
    let network: DeviceNetwork = self.network(modem, catalog: Self.catalog, identities: [climate: identity])
    let recorder = LinkingRecorder(
      readying: { (_: DeviceFirstPrompt) async throws -> Void in

        await modem.pressSetButton(of: climate)

      },
      reacting: { (event: LinkingEvent) async -> Void in

        if case let .hubLinkingLegStarted(leg) = event, leg.index == 1 {

          await modem.setUnanswering(climate)

        }

      }
    )

    let result: DeviceLinkingResult = try await network.linking.link(climate, as: .controller, observer: recorder)

    #expect(result.failedLeg?.leg.index == 1)
    #expect(await extendedCommands(to: climate, on: modem).last == Command(command1: 0x20, command2: 0x07))
    #expect(await recorder.lines.suffix(2) == ["keep awake: releasing \(climate)", "keep awake: released \(climate)"])

  }

  @Test(.timeLimit(.minutes(1))) func releasesTheDeviceWhenTheLinkThrows() async throws {

    struct Unready: Error {}

    let modem = InMemoryModem()
    let (climate, identity): (InsteonAddress, ReportedIdentity) = Self.climate
    let network: DeviceNetwork = self.network(modem, catalog: Self.catalog, identities: [climate: identity])
    // The person never puts the climate sensor in linking mode.
    let recorder = LinkingRecorder(readying: { (_: DeviceFirstPrompt) async throws -> Void in

      throw Unready()

    })

    await #expect(throws: Unready.self) {

      _ = try await network.linking.link(climate, as: .controller, observer: recorder)

    }

    #expect(await extendedCommands(to: climate, on: modem) == [Command(command1: 0x20, command2: 0x06), Command(command1: 0x20, command2: 0x07)])
    #expect(await modem.linkingSteps.isEmpty)
    // A first leg that throws reports no leg failure, so nothing suggests linking again.
    #expect(await !recorder.lines.contains { (line: String) -> Bool in line.contains("failed") })

  }

  @Test(.timeLimit(.minutes(1))) func releasesTheDeviceWhenTheLinkIsCanceled() async throws {

    let modem = InMemoryModem()
    let (climate, identity): (InsteonAddress, ReportedIdentity) = Self.climate
    let network: DeviceNetwork = self.network(modem, catalog: Self.catalog, identities: [climate: identity])
    // The climate sensor links its first leg, then never completes the second.
    let recorder = LinkingRecorder(
      readying: { (_: DeviceFirstPrompt) async throws -> Void in

        await modem.pressSetButton(of: climate)

      },
      reacting: { (event: LinkingEvent) async -> Void in

        if case let .hubLinkingLegStarted(leg) = event, leg.index == 1 {

          await modem.setSilent(climate)

        }

      }
    )
    let linking = Task { () async throws -> DeviceLinkingResult in

      try await network.linking.link(climate, as: .controller, observer: recorder)

    }

    await clock.waitForSleeper(until: Linker.defaultRemoteLinkingTimeout)
    linking.cancel()

    await #expect(throws: CancellationError.self) {

      _ = try await linking.value

    }

    #expect(await extendedCommands(to: climate, on: modem).last == Command(command1: 0x20, command2: 0x07))
    #expect(await recorder.lines.suffix(2) == ["keep awake: releasing \(climate)", "keep awake: released \(climate)"])

  }

  // MARK: - The guards

  /// A made-up sensor whose catalog names keep-awake messages that are never sent.
  static func guardedCatalog(send: DeviceLifecycle.HubLinking.HubMessage) -> DeviceCatalog {

    let commands = CommandSet(
      id: "exampleGuarded",
      name: "Example",
      summary: "A command set with guarded flags and a guarded command.",
      operatingFlags: [
        OperatingFlag(name: "lockout", summary: "Locks out linking from the device.", query: .operatingFlags, bit: 0x01, on: 0x00, off: 0x01, writeGuard: .neverSet),
        OperatingFlag(name: "radioMute", summary: "Mutes the radio.", query: .operatingFlags, bit: 0x40, on: 0x0C, off: 0x0D, writeGuard: .keep)
      ],
      standardCommands: [
        DeviceStandardCommand(name: "muteRadio", summary: "Mutes the radio.", command1: 0x20, command2: .fixed(0x0C), sendGuard: .never, effect: .destructive, isIdempotent: false)
      ]
    )

    return DeviceCatalog(
      profiles: [
        DeviceProfile(
          model: "9401",
          name: "Example Guarded Sensor",
          identities: [DeviceIdentity(category: 0x10, subcategory: 0x7A)],
          commandSets: [CommandSetEntry(commandSet: "exampleGuarded", category: 0x10, subcategory: 0x7A)],
          isBatteryPowered: true,
          groups: [DeviceProfile.Group(number: 1, name: "Open", role: .controller)],
          lifecycle: DeviceLifecycle(fromHub: DeviceLifecycle.HubLinking(
            legs: [DeviceLifecycle.HubLinking.Leg(modemRole: .responder, modemGroup: 0x01, deviceGroup: 0x01)],
            remoteEnterLinkingMode: DeviceLifecycle.HubLinking.RemoteEnterLinkingMode(works: .yes),
            keepAwake: DeviceLifecycle.HubLinking.KeepAwake(timing: .afterLinked, send: send)
          ))
        )
      ],
      commandSets: [commands]
    )

  }

  @Test(
    .timeLimit(.minutes(1)),
    arguments: [
      DeviceLifecycle.HubLinking.HubMessage.flag(DeviceProfile.Group.Condition(flag: "lockout", isSet: true)),
      DeviceLifecycle.HubLinking.HubMessage.bytes(DeviceLifecycle.HubLinking.RawMessage(command: Command(command1: 0x20, command2: 0x0C), effect: .configuration, isIdempotent: true)),
      DeviceLifecycle.HubLinking.HubMessage.command("muteRadio")
    ]
  )
  func neverSendsAKeepAwakeMessageTheGuardsRefuse(_ send: DeviceLifecycle.HubLinking.HubMessage) async throws {

    let modem = InMemoryModem()
    let sensor = InsteonAddress(0x5A, 0x6B, 0x04)
    let identity = ReportedIdentity(category: 0x10, subcategory: 0x7A, firmwareVersion: 0x41)
    let network: DeviceNetwork = self.network(modem, catalog: Self.guardedCatalog(send: send), identities: [sensor: identity])
    let recorder = LinkingRecorder()

    let result: DeviceLinkingResult = try await network.linking.link(sensor, as: .controller, observer: recorder)

    // Linking goes on, and nothing but linking reaches the sensor.
    #expect(result.links.count == 1)
    #expect(await modem.extendedRequests.isEmpty)
    #expect(await modem.linkingSteps.allSatisfy { (step: InMemoryModem.LinkingStep) -> Bool in

      guard case let .device(_, command, _) = step else {

        return true

      }

      return command.command1 == 0x0D || command.command1 == 0x09

    })
    #expect(await recorder.lines.contains("keep awake: not sent \(sensor)"))
    #expect(await !recorder.lines.contains { (line: String) -> Bool in line.hasPrefix("keep awake: releasing") })

  }

  @Test(.timeLimit(.minutes(1))) func neverSendsAKeepAwakeMessageNamingALinkingChange() async throws {

    // The command set lets a relay link clear pulse, which a plain link never writes,
    // even when a keep-awake message names it.
    let commands = CommandSet(
      id: "exampleRelaySensor",
      name: "Example",
      summary: "A relay whose keep-awake message names its pulse flag.",
      operatingFlags: [OperatingFlag(name: "pulse", summary: "The relay returns to off by itself.", query: .operatingFlags, bit: 0x08, on: 0x06, off: 0x07)],
      linkingChanges: [LinkingChange(flag: "pulse")]
    )
    let catalog = DeviceCatalog(
      profiles: [
        DeviceProfile(
          model: "9402",
          name: "Example Relay Sensor",
          identities: [DeviceIdentity(category: 0x10, subcategory: 0x7B)],
          commandSets: [CommandSetEntry(commandSet: "exampleRelaySensor", category: 0x10, subcategory: 0x7B)],
          isBatteryPowered: true,
          groups: [DeviceProfile.Group(number: 1, name: "Open", role: .controller)],
          lifecycle: DeviceLifecycle(fromHub: DeviceLifecycle.HubLinking(
            legs: [DeviceLifecycle.HubLinking.Leg(modemRole: .responder, modemGroup: 0x01, deviceGroup: 0x01)],
            remoteEnterLinkingMode: DeviceLifecycle.HubLinking.RemoteEnterLinkingMode(works: .yes),
            keepAwake: DeviceLifecycle.HubLinking.KeepAwake(timing: .afterLinked, send: .flag(DeviceProfile.Group.Condition(flag: "pulse", isSet: false)))
          ))
        )
      ],
      commandSets: [commands]
    )
    let modem = InMemoryModem()
    let sensor = InsteonAddress(0x5A, 0x6B, 0x05)
    let network: DeviceNetwork = self.network(modem, catalog: catalog, identities: [sensor: ReportedIdentity(category: 0x10, subcategory: 0x7B, firmwareVersion: 0x41)])
    let recorder = LinkingRecorder()

    let result: DeviceLinkingResult = try await network.linking.link(sensor, as: .controller, observer: recorder)

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps
    let lines: [String] = await recorder.lines

    // The keep-awake message names pulse, yet it isn't a flag a plain link may write.
    #expect(DeviceLinkingCoordinator.keepAwakeFlags(of: catalog.describe(category: 0x10, subcategory: 0x7B, firmwareVersion: 0x41)).isEmpty)
    #expect(result.links.count == 1)
    #expect(await modem.extendedRequests.isEmpty)
    #expect(!steps.contains { (step: InMemoryModem.LinkingStep) -> Bool in

      if case let .device(_, command, _) = step {

        return command.command1 == 0x20

      }

      return false

    })
    #expect(lines.contains("keep awake: not sent \(sensor)"))

  }

  @Test func fillsOnlyTheParameterThatTakesTheDuration() throws {

    let duration = MessageField(name: "duration", summary: "How long.", location: .userData([3]), kind: .number(unit: .seconds), range: 0...255)
    let mode = MessageField(name: "mode", summary: "Something else.", location: .userData([4]), range: 0...255)
    let command = DeviceExtendedCommand(
      name: "holdAwake",
      summary: "Keeps it awake.",
      command: Command(command1: 0x2E, command2: 0x00),
      fixedBytes: [FixedUserDataByte(position: 1, value: 0x01)],
      parameters: [mode, duration],
      effect: .configuration, isIdempotent: true
    )

    // The parameter in seconds takes the duration, even after another number.
    #expect(Device.durationParameter(of: command) == duration)
    #expect(Device.durationValue(.seconds(60), for: duration) == .number(60))
    #expect(Device.zeroValue(for: mode) == .number(0))

    let values: [SettingName: FieldValue] = [mode.name: Device.zeroValue(for: mode), duration.name: Device.durationValue(nil, for: duration)]
    let userData: UserData = try command.userData(values: values)

    #expect([userData[1], userData[3], userData[4]] == [0x01, 0xFF, 0x00])

    // With no unit, a command's only number takes it.
    let only = DeviceExtendedCommand(name: "holdAwake", summary: "Keeps it awake.", command: Command(command1: 0x2E, command2: 0x00), parameters: [mode], effect: .configuration, isIdempotent: true)

    #expect(Device.durationParameter(of: only) == mode)

  }

  @Test func writesOnlyTheFlagsTheKeepAwakeMessagesName() throws {

    let remote: DeviceDescription = Self.catalog.describe(category: Self.remote.identity.category, subcategory: Self.remote.identity.subcategory, firmwareVersion: 0x37)
    let contact: DeviceDescription = Self.catalog.describe(category: Self.contact.identity.category, subcategory: Self.contact.identity.subcategory, firmwareVersion: 0x41)
    let dimmer: DeviceDescription = ControlExample.catalog.describe(category: ControlExample.dimmerIdentity.category, subcategory: ControlExample.dimmerIdentity.subcategory, firmwareVersion: 0x45)

    #expect(DeviceLinkingCoordinator.keepAwakeFlags(of: remote) == ["holdAwake"])
    // An extended Set writes no operating flag, and a device without keep-awake writes none.
    #expect(DeviceLinkingCoordinator.keepAwakeFlags(of: contact).isEmpty)
    #expect(DeviceLinkingCoordinator.keepAwakeFlags(of: dimmer).isEmpty)
    #expect(DeviceLinkingCoordinator.keepAwakeFlags(of: nil).isEmpty)

  }

  // MARK: - Consent

  @Test(.timeLimit(.minutes(1)), arguments: [false, true])
  func stopsLinkingBeforeAnythingIsSentWhenTheKeepAwakeMessageIsDestructive(keptAwakeBeforeLinking: Bool) async throws {

    let sensor: (address: InsteonAddress, identity: ReportedIdentity) = keptAwakeBeforeLinking ? Self.earlyWiper : Self.wiper
    let modem = InMemoryModem()
    let requests = RequestCount()
    await modem.setEngine(.i2cs, of: sensor.address)
    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      await requests.record(operation)

    }
    let network: DeviceNetwork = self.network(modem, catalog: Self.wiperCatalog, identities: [sensor.address: sensor.identity])
    let recorder: LinkingRecorder = readying(sensor.address, on: modem)

    let error: DeviceControlError? = await #expect(throws: DeviceControlError.self) {

      _ = try await network.linking.link(sensor.address, as: .controller, observer: recorder)

    }

    guard case let .needsConsent(.keepAwake, effect, _)? = error else {

      Issue.record("Expected needsConsent, got \(String(describing: error)).")

      return

    }

    #expect(effect == .destructive)
    #expect(await modem.linkingSteps.isEmpty)
    #expect(await modem.extendedRequests.isEmpty)
    #expect(await requests.count == 0)

  }

}

/// Counts the operations an in-memory modem is asked to carry out.
actor RequestCount {

  private(set) var count: Int = 0

  func record(_ operation: InMemoryModem.Operation) {

    count += 1

  }

}
