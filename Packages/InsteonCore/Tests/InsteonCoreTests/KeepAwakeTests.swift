import Foundation
import Testing
@testable import InsteonCore
import InsteonDeviceCatalog
import InsteonLinking
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// Keeping a battery-powered device awake while it links by the catalog's legs, and letting it
/// sleep again, on an in-memory modem.
struct KeepAwakeTests {

  let clock: TestClock = TestClock()

  let times: FixedTimes = FixedTimes()

  /// The bundled Open/Close Sensor 2843, whose catalog keeps it awake with the extended Set
  /// its command set names, right after its first link, and gives no message to release it.
  static let openClose = (address: InsteonAddress(0x5A, 0x6B, 0x01), identity: ReportedIdentity(category: 0x10, subcategory: 0x02, firmwareVersion: 0x41))

  /// The bundled RemoteLinc 2 2444A2WH4, kept awake with its stay awake flag after its first
  /// link, and released by clearing it.
  static let remote = (address: InsteonAddress(0x5A, 0x6B, 0x02), identity: ReportedIdentity(category: 0x00, subcategory: 0x10, firmwareVersion: 0x37))

  /// The bundled Wireless Zone Thermostat 2441ZTH, kept awake by Set Operating Flags given by
  /// its bytes before it goes into linking mode, and released the same way.
  static let thermostat = (address: InsteonAddress(0x5A, 0x6B, 0x03), identity: ReportedIdentity(category: 0x05, subcategory: 0x0A, firmwareVersion: 0x41))

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

  // MARK: - Sending and releasing

  @Test(.timeLimit(.minutes(1))) func keepsTheBundledOpenCloseSensorAwakeAfterItsFirstLink() async throws {

    let modem = InMemoryModem()
    let (sensor, identity): (InsteonAddress, ReportedIdentity) = Self.openClose
    await modem.setEngine(.i2cs, of: sensor)
    let network: DeviceNetwork = self.network(modem, catalog: try DeviceCatalog.bundled(), identities: [sensor: identity])
    let recorder: LinkingRecorder = readying(sensor, on: modem)

    _ = try await network.linking.link(sensor, as: .controller, observer: recorder)

    let sent: [InMemoryModem.ExtendedRequest] = await modem.extendedRequests.filter { (request: InMemoryModem.ExtendedRequest) -> Bool in request.device == sensor }

    // The command set's stayAwake: extended Set with D1 0x01 and D2 0x04, and the longest
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

  @Test(.timeLimit(.minutes(1))) func setsAndClearsTheBundledRemotesStayAwakeFlag() async throws {

    let modem = InMemoryModem()
    let (remote, identity): (InsteonAddress, ReportedIdentity) = Self.remote
    await modem.setEngine(.i2cs, of: remote)
    let network: DeviceNetwork = self.network(modem, catalog: try DeviceCatalog.bundled(), identities: [remote: identity])
    let recorder: LinkingRecorder = readying(remote, on: modem)

    let result: DeviceLinkingResult = try await network.linking.link(remote, as: .controller, observer: recorder)

    // Set Operating Flags, extended for the i2CS remote: stay awake on, then off once linked.
    #expect(await extendedCommands(to: remote, on: modem) == [Command(command1: 0x20, command2: 0x06), Command(command1: 0x20, command2: 0x07)])
    #expect(result.links.count == 1)
    #expect(await recorder.lines.suffix(3) == [
      "leg 1 completed group 1 responder",
      "keep awake: releasing \(remote)",
      "keep awake: released \(remote)"
    ])

  }

  @Test(.timeLimit(.minutes(1))) func wakesTheBundledThermostatAndKeepsItAwakeBeforeLinking() async throws {

    let modem = InMemoryModem()
    let (thermostat, identity): (InsteonAddress, ReportedIdentity) = Self.thermostat
    let catalog: DeviceCatalog = try DeviceCatalog.bundled()
    let network: DeviceNetwork = self.network(modem, catalog: catalog, identities: [thermostat: identity])
    let recorder: LinkingRecorder = readying(thermostat, on: modem)
    let wakingSteps: Int = catalog.describe(category: 0x05, subcategory: 0x0A, firmwareVersion: 0x41).profile?.lifecycle?.waking?.steps
      .filter { (step: DeviceLifecycle.Step) -> Bool in !step.isOnOtherDevice }.count ?? 0

    let result: DeviceLinkingResult = try await network.linking.link(thermostat, as: .controller, observer: recorder)

    let lines: [String] = await recorder.lines

    // The message given by its bytes, extended with a checksum: stay awake, then sleep.
    #expect(await extendedCommands(to: thermostat, on: modem) == [Command(command1: 0x20, command2: 0x06), Command(command1: 0x20, command2: 0x07)])
    #expect(Array(lines.prefix(3)) == [
      "wake \(thermostat) steps \(wakingSteps)",
      "keep awake: sending \(thermostat) beforeLinking",
      "keep awake: sent \(thermostat)"
    ])
    #expect(lines.suffix(2) == ["keep awake: releasing \(thermostat)", "keep awake: released \(thermostat)"])
    // It's kept awake before the modem starts ALL-Linking for its first leg.
    #expect(await modem.linkingSteps.first == .modem(.responder, 0x01))
    #expect(result.links.map(\.group.rawValue) == [0x01, 0x02, 0x03, 0x04])

  }

  @Test(.timeLimit(.minutes(1))) func releasesTheDeviceWhenALaterLegFails() async throws {

    let modem = InMemoryModem()
    let (thermostat, identity): (InsteonAddress, ReportedIdentity) = Self.thermostat
    let network: DeviceNetwork = self.network(modem, catalog: try DeviceCatalog.bundled(), identities: [thermostat: identity])
    let recorder = LinkingRecorder(
      readying: { (_: DeviceFirstPrompt) async throws -> Void in

        await modem.pressSetButton(of: thermostat)

      },
      reacting: { (event: LinkingEvent) async -> Void in

        if case let .hubLinkingLegStarted(leg) = event, leg.index == 1 {

          await modem.setEngine(.i1, of: thermostat)

        }

      }
    )

    let result: DeviceLinkingResult = try await network.linking.link(thermostat, as: .controller, observer: recorder)

    #expect(result.failedLeg?.leg.index == 1)
    #expect(await extendedCommands(to: thermostat, on: modem).last == Command(command1: 0x20, command2: 0x07))
    #expect(await recorder.lines.suffix(2) == ["keep awake: releasing \(thermostat)", "keep awake: released \(thermostat)"])

  }

  @Test(.timeLimit(.minutes(1))) func releasesTheDeviceWhenTheLinkThrows() async throws {

    struct Unready: Error {}

    let modem = InMemoryModem()
    let (thermostat, identity): (InsteonAddress, ReportedIdentity) = Self.thermostat
    let network: DeviceNetwork = self.network(modem, catalog: try DeviceCatalog.bundled(), identities: [thermostat: identity])
    // The person never puts the thermostat in linking mode.
    let recorder = LinkingRecorder(readying: { (_: DeviceFirstPrompt) async throws -> Void in

      throw Unready()

    })

    await #expect(throws: Unready.self) {

      _ = try await network.linking.link(thermostat, as: .controller, observer: recorder)

    }

    #expect(await extendedCommands(to: thermostat, on: modem) == [Command(command1: 0x20, command2: 0x06), Command(command1: 0x20, command2: 0x07)])
    #expect(await modem.linkingSteps.isEmpty)

  }

  @Test(.timeLimit(.minutes(1))) func releasesTheDeviceWhenTheLinkIsCanceled() async throws {

    let modem = InMemoryModem()
    let (thermostat, identity): (InsteonAddress, ReportedIdentity) = Self.thermostat
    let network: DeviceNetwork = self.network(modem, catalog: try DeviceCatalog.bundled(), identities: [thermostat: identity])
    // The thermostat links its first leg, then never completes the second.
    let recorder = LinkingRecorder(
      readying: { (_: DeviceFirstPrompt) async throws -> Void in

        await modem.pressSetButton(of: thermostat)

      },
      reacting: { (event: LinkingEvent) async -> Void in

        if case let .hubLinkingLegStarted(leg) = event, leg.index == 1 {

          await modem.setSilent(thermostat)

        }

      }
    )
    let linking = Task { () async throws -> DeviceLinkingResult in

      try await network.linking.link(thermostat, as: .controller, observer: recorder)

    }

    await clock.waitForSleeper(until: Linker.defaultRemoteLinkingTimeout)
    linking.cancel()

    await #expect(throws: CancellationError.self) {

      _ = try await linking.value

    }

    #expect(await extendedCommands(to: thermostat, on: modem).last == Command(command1: 0x20, command2: 0x07))
    #expect(await recorder.lines.suffix(2) == ["keep awake: releasing \(thermostat)", "keep awake: released \(thermostat)"])

  }

  // MARK: - The guards

  /// A made-up sensor whose catalog names keep-awake messages that are never sent.
  static func guardedCatalog(send: DeviceLifecycle.HubLinking.HubMessage) -> DeviceCatalog {

    let commands = CommandSet(
      id: "exampleGuarded",
      name: "Example",
      summary: "A command set with guarded flags.",
      operatingFlags: [
        OperatingFlag(name: "programmingLock", summary: "Locks programming.", query: .operatingFlags, bit: 0x01, on: 0x00, off: 0x01),
        OperatingFlag(name: "radioOff", summary: "Turns the radio off.", query: .operatingFlags, bit: 0x40, on: 0x0C, off: 0x0D)
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
      DeviceLifecycle.HubLinking.HubMessage.flag(DeviceProfile.Group.Condition(flag: "programmingLock", isSet: true)),
      DeviceLifecycle.HubLinking.HubMessage.bytes(DeviceLifecycle.HubLinking.RawMessage(command: Command(command1: 0x20, command2: 0x0C))),
      DeviceLifecycle.HubLinking.HubMessage.command("radioOff")
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

  @Test func writesOnlyTheFlagsTheKeepAwakeMessagesName() throws {

    let catalog: DeviceCatalog = try DeviceCatalog.bundled()
    let remote: DeviceDescription = catalog.describe(category: 0x00, subcategory: 0x10, firmwareVersion: 0x37)
    let openClose: DeviceDescription = catalog.describe(category: 0x10, subcategory: 0x02, firmwareVersion: 0x41)
    let plug: DeviceDescription = catalog.describe(category: 0x02, subcategory: 0x38, firmwareVersion: 0x42)

    #expect(DeviceLinkingCoordinator.writableLinkingFlags(of: remote) == ["stayAwake"])
    // An extended Set writes no operating flag, and a device without keep-awake writes none.
    #expect(DeviceLinkingCoordinator.writableLinkingFlags(of: openClose).isEmpty)
    #expect(DeviceLinkingCoordinator.writableLinkingFlags(of: plug).isEmpty)
    #expect(DeviceLinkingCoordinator.writableLinkingFlags(of: nil).isEmpty)

    // The bundled catalog names no flags that linking changes on its own.
    for profile in catalog.profiles {

      for identity in profile.identities {

        let description: DeviceDescription = catalog.describe(category: identity.category, subcategory: identity.subcategory, firmwareVersion: nil)

        #expect(description.commandSet?.linkingChanges.isEmpty ?? true, "\(profile.model)")

      }

    }

  }

}
