import Foundation
import Testing
@testable import InsteonCore
import InsteonDeviceCatalog
import InsteonLinking
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// Made-up devices whose catalog profiles give their linking from a Hub as legs.
enum HubLinkingExample {

  static let module = InsteonAddress(0x3C, 0x4D, 0x01)

  static let remote = InsteonAddress(0x3C, 0x4D, 0x02)

  static let button = InsteonAddress(0x3C, 0x4D, 0x03)

  static let keypad = InsteonAddress(0x3C, 0x4D, 0x04)

  static let unknownRole = InsteonAddress(0x3C, 0x4D, 0x05)

  /// A module whose catalog says Enter Linking Mode works for it.
  static let moduleIdentity = ReportedIdentity(category: 0x07, subcategory: 0x6A, firmwareVersion: 0x41)

  /// A battery-powered remote that goes first.
  static let remoteIdentity = ReportedIdentity(category: 0x00, subcategory: 0x6B, firmwareVersion: 0x41)

  /// A device whose catalog says Enter Linking Mode doesn't work for it.
  static let buttonIdentity = ReportedIdentity(category: 0x07, subcategory: 0x6C, firmwareVersion: 0x41)

  /// A keypad the catalog doesn't know whether Enter Linking Mode works for.
  static let keypadIdentity = ReportedIdentity(category: 0x07, subcategory: 0x6D, firmwareVersion: 0x41)

  /// A device whose leg names a modem role this package doesn't know.
  static let unknownRoleIdentity = ReportedIdentity(category: 0x07, subcategory: 0x6E, firmwareVersion: 0x41)

  static let lifecycleSteps = DeviceLifecycle.Procedure(steps: [
    DeviceLifecycle.Step(text: "Start linking on the Hub.", isOnOtherDevice: true),
    DeviceLifecycle.Step(text: "Hold the SET button.")
  ])

  static let controllerThenResponder: [DeviceLifecycle.HubLinking.Leg] = {

    [
      DeviceLifecycle.HubLinking.Leg(modemRole: .controller, modemGroup: 0x00, deviceGroup: 0x01),
      DeviceLifecycle.HubLinking.Leg(modemRole: .responder, modemGroup: 0x01, deviceGroup: 0x01)
    ]

  }()

  static func profile(
    _ model: ProductModel,
    _ identity: ReportedIdentity,
    legs: [DeviceLifecycle.HubLinking.Leg],
    works: DeviceLifecycle.HubLinking.Answer,
    isDeviceFirst: Bool = false
  ) -> DeviceProfile {

    DeviceProfile(
      model: model,
      name: "Example \(model)",
      identities: [DeviceIdentity(category: identity.category, subcategory: identity.subcategory)],
      groups: [
        DeviceProfile.Group(number: 1, name: "Load", role: .both),
        DeviceProfile.Group(number: 2, name: "Button B", role: .controller),
        DeviceProfile.Group(number: 3, name: "Button C", role: .controller)
      ],
      lifecycle: DeviceLifecycle(
        linking: lifecycleSteps,
        fromHub: DeviceLifecycle.HubLinking(
          legs: legs,
          isDeviceFirst: isDeviceFirst,
          remoteEnterLinkingMode: DeviceLifecycle.HubLinking.RemoteEnterLinkingMode(works: works)
        )
      )
    )

  }

  static let catalog = DeviceCatalog(profiles: [
    profile("9301", moduleIdentity, legs: controllerThenResponder, works: .yes),
    profile(
      "9302",
      remoteIdentity,
      legs: [
        DeviceLifecycle.HubLinking.Leg(modemRole: .responder, modemGroup: 0x01, deviceGroup: 0x01),
        DeviceLifecycle.HubLinking.Leg(modemRole: .responder, modemGroup: 0x02, deviceGroup: 0x02)
      ],
      works: .unknown,
      isDeviceFirst: true
    ),
    profile("9303", buttonIdentity, legs: controllerThenResponder, works: .no),
    profile(
      "9304",
      keypadIdentity,
      legs: [
        DeviceLifecycle.HubLinking.Leg(modemRole: .controller, modemGroup: 0x00, deviceGroup: 0x01),
        DeviceLifecycle.HubLinking.Leg(
          modemRole: .responder,
          modemGroup: 0x02,
          deviceGroup: 0x02,
          allGroupsWhen: DeviceProfile.Group.Condition(flag: "linkToAllGroups", isSet: true)
        ),
        DeviceLifecycle.HubLinking.Leg(modemRole: .responder, modemGroup: 0x03, deviceGroup: 0x03)
      ],
      works: .unknown
    ),
    profile(
      "9305",
      unknownRoleIdentity,
      legs: [DeviceLifecycle.HubLinking.Leg(modemRole: DeviceLifecycle.HubLinking.Role(rawValue: "observer"), modemGroup: 0x00, deviceGroup: 0x01)],
      works: .yes
    )
  ])

}

/// Linking by a device's address from the catalog's legs, on an in-memory modem.
struct HubLinkingTests {

  let clock: TestClock = TestClock()

  let times: FixedTimes = FixedTimes()

  func network(_ modem: InMemoryModem, catalog: DeviceCatalog = HubLinkingExample.catalog, identities: [InsteonAddress: ReportedIdentity]) -> DeviceNetwork {

    let times: FixedTimes = self.times

    return DeviceNetwork(
      modem: modem,
      catalog: catalog,
      snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: identities)),
      clock: clock,
      now: { () -> Date in times.now() }
    )

  }

  /// The engine request a remote leg starts with.
  static func engineRequest(_ device: InsteonAddress) -> InMemoryModem.LinkingStep {

    .device(device, Command(command1: 0x0D), isExtended: false)

  }

  /// Enter Linking Mode for a device group.
  static func enterLinkingMode(_ device: InsteonAddress, group: UInt8, isExtended: Bool) -> InMemoryModem.LinkingStep {

    .device(device, Command(command1: 0x09, command2: group), isExtended: isExtended)

  }

  /// What became of each leg, as short words.
  static func statuses(_ result: DeviceLinkingResult) -> [String] {

    result.legs.map { (outcome: HubLinkingLegOutcome) -> String in

      switch outcome.status {
      case let .linked(_, join):
        return "linked by \(LinkingRecorder.join(join))"
      case .failed:
        return "failed"
      case .notRun:
        return "not run"
      }

    }

  }

  // MARK: - Legs in order

  @Test(.timeLimit(.minutes(1))) func runsTheLegsInOrderWithTheModemStartingFirst() async throws {

    let modem = InMemoryModem()
    let module: InsteonAddress = HubLinkingExample.module
    let network: DeviceNetwork = self.network(modem, identities: [module: HubLinkingExample.moduleIdentity])
    let recorder = LinkingRecorder()

    let result: DeviceLinkingResult = try await network.linking.link(module, as: .controller, observer: recorder)

    // The modem starts ALL-Linking before the device is sent Enter Linking Mode in both legs,
    // as responder too, and the second leg starts only once the first one's link is reported.
    #expect(await modem.linkingSteps == [
      Self.engineRequest(module),
      .modem(.controller, 0x00),
      Self.enterLinkingMode(module, group: 0x01, isExtended: false),
      Self.engineRequest(module),
      .modem(.responder, 0x01),
      Self.enterLinkingMode(module, group: 0x01, isExtended: false)
    ])
    #expect(result.links.map(\.mode) == [.controller, .responder])
    #expect(result.links.map(\.group) == [0x00, 0x01])
    #expect(Self.statuses(result) == ["linked by Enter Linking Mode", "linked by Enter Linking Mode"])
    #expect(result.failedLeg == nil)
    #expect(result.linkBackFailure == nil)
    #expect(result.device?.identity == HubLinkingExample.moduleIdentity)
    #expect(await recorder.lines == [
      "not turning on \(module)",
      "leg 1/2 started controller 0 device group 1",
      "leg 1 joined by Enter Linking Mode",
      "linked \(module) group 0 controller first",
      "leg 1 completed group 0 controller",
      "leg 2/2 started responder 1 device group 1",
      "leg 2 joined by Enter Linking Mode",
      "linked \(module) group 1 responder leg 2",
      "leg 2 completed group 1 responder"
    ])

  }

  @Test(.timeLimit(.minutes(1))) func sendsEnterLinkingModeExtendedToAnI2CSDevice() async throws {

    let modem = InMemoryModem()
    let module: InsteonAddress = HubLinkingExample.module
    await modem.setEngine(.i2cs, of: module)
    let network: DeviceNetwork = self.network(modem, identities: [module: HubLinkingExample.moduleIdentity])

    _ = try await network.linking.link(module, as: .controller, observer: LinkingRecorder())

    let sent: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    #expect(sent.filter { (step: InMemoryModem.LinkingStep) -> Bool in step == Self.enterLinkingMode(module, group: 0x01, isExtended: true) }.count == 2)

  }

  @Test(.timeLimit(.minutes(1))) func reportsALegThatCoversEveryGroupWithoutChangingTheFlag() async throws {

    let modem = InMemoryModem()
    let keypad: InsteonAddress = HubLinkingExample.keypad
    let network: DeviceNetwork = self.network(modem, identities: [keypad: HubLinkingExample.keypadIdentity])
    let recorder = LinkingRecorder()

    let result: DeviceLinkingResult = try await network.linking.link(keypad, as: .controller, observer: recorder)

    #expect(result.links.map(\.group) == [0x00, 0x02, 0x03])
    #expect(await recorder.lines.contains("leg 2 all groups when linkToAllGroups true"))
    // Only linking commands went to the keypad: no Get or Set Operating Flags.
    let flagCommands: [InMemoryModem.LinkingStep] = await modem.linkingSteps.filter { (step: InMemoryModem.LinkingStep) -> Bool in

      guard case let .device(_, command, _) = step else {

        return false

      }

      return command.command1 == 0x1F || command.command1 == 0x20

    }

    #expect(flagCommands.isEmpty)

  }

  // MARK: - A device that goes first

  @Test(.timeLimit(.minutes(1))) func hasTheDevicePutInLinkingModeFirstThenRunsTheRest() async throws {

    let modem = InMemoryModem()
    let remote: InsteonAddress = HubLinkingExample.remote
    let network: DeviceNetwork = self.network(modem, identities: [remote: HubLinkingExample.remoteIdentity])
    let recorder = LinkingRecorder(readying: { (_: DeviceFirstPrompt) async throws -> Void in

      await modem.pressSetButton(of: remote)

    })

    let result: DeviceLinkingResult = try await network.linking.link(remote, as: .controller, observer: recorder)

    #expect(await modem.linkingSteps == [
      .modem(.responder, 0x01),
      Self.engineRequest(remote),
      .modem(.responder, 0x02),
      Self.enterLinkingMode(remote, group: 0x02, isExtended: false)
    ])
    #expect(Self.statuses(result) == ["linked by device first", "linked by Enter Linking Mode"])
    #expect(await recorder.lines == [
      "leg 1/2 started responder 1 device group 1",
      "device first: linking \(remote) steps 1",
      "leg 1 joined by device first",
      "modem joining 240",
      "linked \(remote) group 1 responder first",
      "leg 1 completed group 1 responder",
      "leg 2/2 started responder 2 device group 2",
      "leg 2 joined by Enter Linking Mode",
      "linked \(remote) group 2 responder leg 2",
      "leg 2 completed group 2 responder"
    ])

  }

  // MARK: - Whether Enter Linking Mode works

  @Test(.timeLimit(.minutes(1))) func usesTheSETButtonWhenTheCatalogSaysEnterLinkingModeDoesntWork() async throws {

    let modem = InMemoryModem()
    let button: InsteonAddress = HubLinkingExample.button
    let network: DeviceNetwork = self.network(modem, identities: [button: HubLinkingExample.buttonIdentity])
    let recorder = LinkingRecorder(pressing: { (prompt: SETButtonPrompt) async -> Void in

      await modem.pressSetButton(of: prompt.device ?? button)

    })

    let result: DeviceLinkingResult = try await network.linking.link(button, as: .controller, observer: recorder)

    // The device is never sent Enter Linking Mode, or asked for its engine.
    #expect(await modem.linkingSteps == [.modem(.controller, 0x00), .modem(.responder, 0x01)])
    #expect(Self.statuses(result) == ["linked by SET button", "linked by SET button"])
    #expect(await recorder.lines == [
      "not turning on \(button)",
      "leg 1/2 started controller 0 device group 1",
      "press SET: linking group 0 \(button) steps 1",
      "linked \(button) group 0 controller first",
      "leg 1 completed group 0 controller",
      "leg 2/2 started responder 1 device group 1",
      "press SET: linking group 1 \(button) steps 1",
      "linked \(button) group 1 responder leg 2",
      "leg 2 completed group 1 responder"
    ])

  }

  @Test(.timeLimit(.minutes(1))) func linksBothLegsOfAnI1DeviceBySETButtonWhereTheCatalogSaysEnterLinkingModeWorks() async throws {

    let modem = InMemoryModem()
    let module: InsteonAddress = HubLinkingExample.module
    // An i1 device can't take Enter Linking Mode, which the catalog doesn't expect.
    await modem.setEngine(.i1, of: module)
    let network: DeviceNetwork = self.network(modem, identities: [module: HubLinkingExample.moduleIdentity])
    let recorder = LinkingRecorder(pressing: { (prompt: SETButtonPrompt) async -> Void in

      await modem.pressSetButton(of: prompt.device ?? module)

    })

    let result: DeviceLinkingResult = try await network.linking.link(module, as: .controller, observer: recorder)

    // The first leg falls back, saying the catalog expected Enter Linking Mode to work, and the
    // second goes straight to the SET button, with its own prompt, role and groups.
    #expect(Self.statuses(result) == ["linked by SET button", "linked by SET button"])
    #expect(result.failedLeg == nil)
    #expect(await modem.linkingSteps == [Self.engineRequest(module), .modem(.controller, 0x00), .modem(.responder, 0x01)])
    #expect(await recorder.prompts.map { (prompt: SETButtonPrompt) -> String in

      "\(prompt.modemRole.map(LinkingRecorder.role) ?? "none") \(prompt.group) \(prompt.deviceGroup.map { "\($0)" } ?? "none")"

    } == ["controller 0 1", "responder 1 1"])
    #expect(await recorder.lines == [
      "not turning on \(module)",
      "leg 1/2 started controller 0 device group 1",
      "fallback: SET button linking \(module) expected to work",
      "press SET: linking group 0 \(module) steps 1",
      "linked \(module) group 0 controller first",
      "leg 1 completed group 0 controller",
      "leg 2/2 started responder 1 device group 1",
      "press SET: linking group 1 \(module) steps 1",
      "linked \(module) group 1 responder leg 2",
      "leg 2 completed group 1 responder"
    ])

  }

  @Test(.timeLimit(.minutes(1))) func stopsAtALaterLegThatFailsWhereTheCatalogSaysEnterLinkingModeWorks() async throws {

    let modem = InMemoryModem()
    let module: InsteonAddress = HubLinkingExample.module
    let network: DeviceNetwork = self.network(modem, identities: [module: HubLinkingExample.moduleIdentity])
    // The module stops answering once the second leg starts.
    let recorder = LinkingRecorder(reacting: { (event: LinkingEvent) async -> Void in

      if case let .hubLinkingLegStarted(leg) = event, leg.index == 1 {

        await modem.setUnanswering(module)

      }

    })

    let result: DeviceLinkingResult = try await network.linking.link(module, as: .controller, observer: recorder)

    // No SET button for a later leg that fails this way, and no error thrown: the result
    // reports it, as a failure linking again may fix.
    #expect(Self.statuses(result) == ["linked by Enter Linking Mode", "failed"])
    #expect(HubLinkingLeg.canSucceedOnRetry(after: try #require(result.failedLeg?.failure)))
    #expect(await recorder.prompts.isEmpty)
    #expect(await recorder.lines.last == "leg 2 failed, not run 0")

  }

  @Test(.timeLimit(.minutes(1))) func linksEveryLegBySETButtonAfterTheFirstFallsBack() async throws {

    let modem = InMemoryModem()
    let keypad: InsteonAddress = HubLinkingExample.keypad
    await modem.setEngine(.i1, of: keypad)
    let network: DeviceNetwork = self.network(modem, identities: [keypad: HubLinkingExample.keypadIdentity])
    let recorder = LinkingRecorder(pressing: { (prompt: SETButtonPrompt) async -> Void in

      await modem.pressSetButton(of: prompt.device ?? keypad)

    })

    let result: DeviceLinkingResult = try await network.linking.link(keypad, as: .controller, observer: recorder)

    #expect(Self.statuses(result) == ["linked by SET button", "linked by SET button", "linked by SET button"])
    #expect(result.links.map(\.group) == [0x00, 0x02, 0x03])
    // Enter Linking Mode was tried once, for the first leg.
    #expect(await modem.linkingSteps.filter { (step: InMemoryModem.LinkingStep) -> Bool in step == Self.engineRequest(keypad) }.count == 1)
    #expect(await recorder.prompts.map(\.group) == [0x00, 0x02, 0x03])

  }

  @Test(.timeLimit(.minutes(1))) func fallsBackToTheSETButtonForALaterLegThatCantTakeEnterLinkingMode() async throws {

    let modem = InMemoryModem()
    let keypad: InsteonAddress = HubLinkingExample.keypad
    let network: DeviceNetwork = self.network(modem, identities: [keypad: HubLinkingExample.keypadIdentity])
    // The keypad answers as an i1 device once the second leg starts.
    let recorder = LinkingRecorder(
      pressing: { (prompt: SETButtonPrompt) async -> Void in

        await modem.pressSetButton(of: prompt.device ?? keypad)

      },
      reacting: { (event: LinkingEvent) async -> Void in

        if case let .hubLinkingLegStarted(leg) = event, leg.index == 1 {

          await modem.setEngine(.i1, of: keypad)

        }

      }
    )

    let result: DeviceLinkingResult = try await network.linking.link(keypad, as: .controller, observer: recorder)

    #expect(Self.statuses(result) == ["linked by Enter Linking Mode", "linked by SET button", "linked by SET button"])
    #expect(await recorder.lines.contains("fallback: SET button linking \(keypad)"))

  }

  @Test(.timeLimit(.minutes(1))) func stopsAtALaterLegThatFails() async throws {

    let modem = InMemoryModem()
    let keypad: InsteonAddress = HubLinkingExample.keypad
    let network: DeviceNetwork = self.network(modem, identities: [keypad: HubLinkingExample.keypadIdentity])
    // The keypad stops answering once the second leg starts.
    let recorder = LinkingRecorder(reacting: { (event: LinkingEvent) async -> Void in

      if case let .hubLinkingLegStarted(leg) = event, leg.index == 1 {

        await modem.setUnanswering(keypad)

      }

    })

    let result: DeviceLinkingResult = try await network.linking.link(keypad, as: .controller, observer: recorder)

    #expect(Self.statuses(result) == ["linked by Enter Linking Mode", "failed", "not run"])
    // The third leg's modem group was never started.
    #expect(await !modem.linkingSteps.contains(.modem(.responder, 0x03)))
    #expect(await network.registry.device(keypad)?.identity == HubLinkingExample.keypadIdentity)

  }

  @Test(.timeLimit(.minutes(1))) func reportsTheLegsLinkedBeforeALaterLegThrows() async throws {

    let modem = InMemoryModem()
    let keypad: InsteonAddress = HubLinkingExample.keypad
    let other = InsteonAddress(0x3C, 0x4D, 0x7F)
    let network: DeviceNetwork = self.network(modem, identities: [keypad: HubLinkingExample.keypadIdentity])
    // Another device is waiting in linking mode when the second leg starts, so the modem
    // reports its link instead.
    let recorder = LinkingRecorder(reacting: { (event: LinkingEvent) async -> Void in

      if case let .hubLinkingLegStarted(leg) = event, leg.index == 1 {

        await modem.pressSetButton(of: other)

      }

    })

    await #expect(throws: LinkMismatch.self) {

      _ = try await network.linking.link(keypad, as: .controller, observer: recorder)

    }

    let lines: [String] = await recorder.lines

    // The first leg's link is reported with the legs, before the error is thrown, and no leg
    // failure suggests linking again.
    #expect(lines.last == "stopped after 1 of 3 legs")
    #expect(!lines.contains { (line: String) -> Bool in line.contains("failed") })

  }

  @Test(.timeLimit(.minutes(1))) func reportsNoLegFailureForAFirstLegThatThrows() async throws {

    let modem = InMemoryModem()
    let module: InsteonAddress = HubLinkingExample.module
    let other = InsteonAddress(0x3C, 0x4D, 0x7E)
    // Another device is waiting in linking mode, so the first leg's link is another's.
    await modem.pressSetButton(of: other)
    let network: DeviceNetwork = self.network(modem, identities: [module: HubLinkingExample.moduleIdentity])
    let recorder = LinkingRecorder()

    await #expect(throws: LinkMismatch.self) {

      _ = try await network.linking.link(module, as: .controller, observer: recorder)

    }

    // The device took Enter Linking Mode, but the modem reported the other device's link.
    #expect(await recorder.lines == [
      "not turning on \(module)",
      "leg 1/2 started controller 0 device group 1",
      "leg 1 joined by Enter Linking Mode"
    ])

  }

  // MARK: - Asking for something else

  @Test(.timeLimit(.minutes(1))) func linksAsBeforeWhenTheCallerDoesntUseTheCatalogsLegs() async throws {

    let modem = InMemoryModem()
    let module: InsteonAddress = HubLinkingExample.module
    let network: DeviceNetwork = self.network(modem, identities: [module: HubLinkingExample.moduleIdentity])
    let recorder = LinkingRecorder()

    // As for --either or an explicit --group 0, whose role and group equal the defaults.
    let result: DeviceLinkingResult = try await network.linking.link(module, as: .controller, usesCatalogLegs: false, observer: recorder)

    #expect(result.legs.isEmpty)
    #expect(Array(await recorder.lines.prefix(2)) == ["not turning on \(module)", "linking remotely \(module) as controller"])

  }

  // MARK: - A device the registry doesn't know

  @Test(.timeLimit(.minutes(1))) func identifiesADeviceTheRegistryDoesntKnowThenLinksItsLegs() async throws {

    let modem = InMemoryModem()
    let module: InsteonAddress = HubLinkingExample.module
    let identity: ReportedIdentity = HubLinkingExample.moduleIdentity
    await modem.setIdentity(SetButtonPressed(
      sender: module,
      role: .responder,
      category: identity.category,
      subcategory: identity.subcategory,
      firmwareVersion: identity.firmwareVersion
    ))
    let network: DeviceNetwork = self.network(modem, identities: [:])
    let recorder = LinkingRecorder()

    let result: DeviceLinkingResult = try await network.linking.link(module, as: .controller, observer: recorder)

    // Get Insteon Engine Version and ID Request identify it, then its legs run.
    #expect(await modem.linkingSteps == [
      Self.engineRequest(module),
      Self.engineRequest(module),
      .modem(.controller, 0x00),
      Self.enterLinkingMode(module, group: 0x01, isExtended: false),
      Self.engineRequest(module),
      .modem(.responder, 0x01),
      Self.enterLinkingMode(module, group: 0x01, isExtended: false)
    ])
    #expect(Self.statuses(result) == ["linked by Enter Linking Mode", "linked by Enter Linking Mode"])
    #expect(Array(await recorder.lines.prefix(3)) == [
      "identifying \(module)",
      "not turning on \(module)",
      "leg 1/2 started controller 0 device group 1"
    ])
    #expect(await network.registry.device(module)?.identity == identity)

  }

  @Test(.timeLimit(.minutes(1))) func linksAsBeforeWhenADeviceTheRegistryDoesntKnowIsntIdentified() async throws {

    let modem = InMemoryModem()
    let module: InsteonAddress = HubLinkingExample.module
    // Unlinked, it rejects the requests that identify it, though its catalog gives legs.
    await modem.setUnlinked(module)
    let network: DeviceNetwork = self.network(modem, identities: [:])
    let recorder = LinkingRecorder()

    let result: DeviceLinkingResult = try await network.linking.link(module, as: .controller, observer: recorder)

    #expect(result.legs.isEmpty)
    #expect(result.links.map(\.mode) == [.controller])
    #expect(Array(await recorder.lines.prefix(4)) == [
      "identifying \(module)",
      "not identified \(module) not linked",
      "not turning on \(module)",
      "linking remotely \(module) as controller"
    ])

  }

  // MARK: - Without legs

  @Test(.timeLimit(.minutes(1))) func linksAsBeforeWithoutLegs() async throws {

    let modem = InMemoryModem()
    let sensor: InsteonAddress = LinkingExample.sensor
    let network = DeviceNetwork(
      modem: modem,
      catalog: LinkingExample.catalog,
      snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [sensor: LinkingExample.sensorIdentity])),
      clock: clock,
      now: { () -> Date in Date(timeIntervalSince1970: 0) }
    )
    let recorder = LinkingRecorder()

    let result: DeviceLinkingResult = try await network.linking.link(sensor, as: .controller, observer: recorder)

    #expect(result.legs.isEmpty)
    #expect(result.links.map(\.mode) == [.controller, .responder])
    #expect(await recorder.lines == [
      "not turning on \(sensor)",
      "linking remotely \(sensor) as controller",
      "linked \(sensor) group 0 controller first",
      "linking back \(sensor) group 1",
      "linked \(sensor) group 1 responder back"
    ])

  }

  @Test(.timeLimit(.minutes(1))) func linksAsBeforeWhenTheCallerAsksForSomethingElse() async throws {

    let modem = InMemoryModem()
    let module: InsteonAddress = HubLinkingExample.module
    let network: DeviceNetwork = self.network(modem, identities: [module: HubLinkingExample.moduleIdentity])
    let recorder = LinkingRecorder()

    let result: DeviceLinkingResult = try await network.linking.link(module, as: .controller, twoWay: .never, observer: recorder)

    #expect(result.legs.isEmpty)
    #expect(result.links.map(\.mode) == [.controller])
    #expect(await recorder.lines == ["not turning on \(module)", "linking remotely \(module) as controller", "linked \(module) group 0 controller first"])

  }

  @Test(.timeLimit(.minutes(1))) func linksAsBeforeWhenALegNamesARoleThisPackageDoesntKnow() async throws {

    let modem = InMemoryModem()
    let device: InsteonAddress = HubLinkingExample.unknownRole
    let network: DeviceNetwork = self.network(modem, identities: [device: HubLinkingExample.unknownRoleIdentity])

    let result: DeviceLinkingResult = try await network.linking.link(device, as: .controller, observer: LinkingRecorder())

    #expect(result.legs.isEmpty)
    #expect(await modem.linkingSteps.contains(.modem(.controller, 0x00)))

  }

  // MARK: - The bundled catalog

  @Test(.timeLimit(.minutes(1))) func linksTheBundledOutdoorPlugByItsLegs() async throws {

    let modem = InMemoryModem()
    let plug = InsteonAddress(0x4E, 0x5F, 0x01)
    await modem.setEngine(.i2cs, of: plug)
    let identity = ReportedIdentity(category: 0x02, subcategory: 0x38, firmwareVersion: 0x42)
    let network: DeviceNetwork = self.network(modem, catalog: try DeviceCatalog.bundled(), identities: [plug: identity])

    let result: DeviceLinkingResult = try await network.linking.link(plug, as: .controller, observer: LinkingRecorder())

    // Light On first, so the plug records full on; then the modem as controller of group 0,
    // then as responder of the plug's group 1, each with the extended Enter Linking Mode.
    #expect(await modem.linkingSteps == [
      .device(plug, Command(command1: 0x11, command2: 0xFF), isExtended: false),
      Self.engineRequest(plug),
      .modem(.controller, 0x00),
      Self.enterLinkingMode(plug, group: 0x01, isExtended: true),
      Self.engineRequest(plug),
      .modem(.responder, 0x01),
      Self.enterLinkingMode(plug, group: 0x01, isExtended: true)
    ])
    #expect(result.links.map(\.mode) == [.controller, .responder])
    #expect(result.legs.allSatisfy { (outcome: HubLinkingLegOutcome) -> Bool in outcome.leg.isRemoteLinkingExpectedToWork })

  }

  @Test(.timeLimit(.minutes(1))) func linksTheBundledIOModuleByItsLegsWithoutTurningItOn() async throws {

    let modem = InMemoryModem()
    let module = InsteonAddress(0x4E, 0x5F, 0x02)
    await modem.setEngine(.i2cs, of: module)
    let identity = ReportedIdentity(category: 0x07, subcategory: 0x00, firmwareVersion: 0x41)
    let catalog: DeviceCatalog = try DeviceCatalog.bundled()
    let network: DeviceNetwork = self.network(modem, catalog: catalog, identities: [module: identity])

    // Light On would switch whatever the relay drives, such as a garage door.
    #expect(!catalog.describe(category: 0x07, subcategory: 0x00, firmwareVersion: 0x41).setsOnLevelFromLoadWhenLinked)

    let result: DeviceLinkingResult = try await network.linking.link(module, as: .controller, observer: LinkingRecorder())

    #expect(await modem.linkingSteps == [
      Self.engineRequest(module),
      .modem(.controller, 0x00),
      Self.enterLinkingMode(module, group: 0x01, isExtended: true),
      Self.engineRequest(module),
      .modem(.responder, 0x01),
      Self.enterLinkingMode(module, group: 0x01, isExtended: true)
    ])
    #expect(await modem.levels[module] == nil)
    #expect(result.links.map(\.group) == [0x00, 0x01])

  }

  @Test(.timeLimit(.minutes(1))) func linksEachOfTheBundledSmokeBridgesGroups() async throws {

    let modem = InMemoryModem()
    let bridge = InsteonAddress(0x4E, 0x5F, 0x03)
    await modem.setEngine(.i2cs, of: bridge)
    let identity = ReportedIdentity(category: 0x10, subcategory: 0x0A, firmwareVersion: 0xDC)
    let network: DeviceNetwork = self.network(modem, catalog: try DeviceCatalog.bundled(), identities: [bridge: identity])

    let result: DeviceLinkingResult = try await network.linking.link(bridge, as: .controller, observer: LinkingRecorder())

    let groups: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x0A]
    let expected: [InMemoryModem.LinkingStep] = groups.flatMap { (group: UInt8) -> [InMemoryModem.LinkingStep] in

      [Self.engineRequest(bridge), .modem(.responder, AllLinkGroupNumber(rawValue: group)), Self.enterLinkingMode(bridge, group: group, isExtended: true)]

    }

    // The modem responds to each group the bridge controls, and never controls it.
    #expect(await modem.linkingSteps == expected)
    #expect(result.links.map(\.group.rawValue) == groups)
    #expect(result.links.allSatisfy { (link: AllLinkingCompleted) -> Bool in link.mode == .responder })

  }

}
