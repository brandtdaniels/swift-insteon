import Foundation
import Testing
@testable import InsteonCore
import InsteonDeviceCatalog
import InsteonLinking
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// Made-up devices to link: a lamp, which is a dimmer; a sensor, which controls; a module
/// whose relay isn't a light, so it isn't turned on before linking; and a keypad, which
/// controls in groups 3 and 4 but not group 1.
enum LinkingExample {

  static let lamp = InsteonAddress(0x2A, 0x3B, 0x01)

  static let sensor = InsteonAddress(0x2A, 0x3B, 0x02)

  static let module = InsteonAddress(0x2A, 0x3B, 0x03)

  static let lampIdentity = ReportedIdentity(category: 0x01, subcategory: 0x5A, firmwareVersion: 0x41)

  static let sensorIdentity = ReportedIdentity(category: 0x10, subcategory: 0x5B, firmwareVersion: 0x41)

  static let moduleIdentity = ReportedIdentity(category: 0x07, subcategory: 0x5C, firmwareVersion: 0x41)

  static let keypad = InsteonAddress(0x2A, 0x3B, 0x04)

  static let keypadIdentity = ReportedIdentity(category: 0x00, subcategory: 0x5D, firmwareVersion: 0x41)

  /// A step on the device, and one on the other device that's left out of the device's steps.
  static let linkingSteps: [DeviceLifecycle.Step] = [
    DeviceLifecycle.Step(text: "Start linking on the Hub.", isOnOtherDevice: true),
    DeviceLifecycle.Step(text: "Hold the SET button.", expectation: "Beeps")
  ]

  static let unlinkingSteps: [DeviceLifecycle.Step] = [
    DeviceLifecycle.Step(text: "Hold the SET button twice.")
  ]

  static let lifecycle = DeviceLifecycle(
    linking: DeviceLifecycle.Procedure(steps: linkingSteps),
    unlinking: DeviceLifecycle.Procedure(steps: unlinkingSteps)
  )

  static let catalog = DeviceCatalog(profiles: [
    DeviceProfile(
      model: "9201",
      name: "Example Lamp Dimmer",
      identities: [DeviceIdentity(category: 0x01, subcategory: 0x5A)],
      groups: [DeviceProfile.Group(number: 1, name: "Load", role: .responder)],
      lifecycle: lifecycle
    ),
    DeviceProfile(
      model: "9202",
      name: "Example Sensor",
      identities: [DeviceIdentity(category: 0x10, subcategory: 0x5B)],
      isBatteryPowered: true,
      groups: [DeviceProfile.Group(number: 1, name: "Open", role: .controller)],
      lifecycle: lifecycle
    ),
    DeviceProfile(
      model: "9203",
      name: "Example Module",
      identities: [DeviceIdentity(category: 0x07, subcategory: 0x5C)],
      groups: [DeviceProfile.Group(number: 1, name: "Relay", role: .responder)],
      lifecycle: lifecycle
    ),
    DeviceProfile(
      model: "9204",
      name: "Example Keypad",
      identities: [DeviceIdentity(category: 0x00, subcategory: 0x5D)],
      groups: [
        DeviceProfile.Group(number: 1, name: "Load", role: .responder),
        DeviceProfile.Group(number: 3, name: "Button C", role: .controller),
        DeviceProfile.Group(number: 4, name: "Button D", role: .controller)
      ],
      lifecycle: lifecycle
    )
  ])

}

/// Records what a coordinator tells it, each event as a short line, and stands in for the
/// person: it presses a device's SET button when told to.
actor LinkingRecorder: LinkingObserver {

  /// The events, in order, as short lines.
  private(set) var lines: [String] = []

  /// The SET button prompts, in order.
  private(set) var prompts: [SETButtonPrompt] = []

  /// What the person does when told to press a SET button.
  private let pressing: @Sendable (SETButtonPrompt) async -> Void

  /// What the person does when asked to put a device into its mode first.
  private let readying: @Sendable (DeviceFirstPrompt) async throws -> Void

  /// What a test does on each event, such as change a device partway.
  private let reacting: @Sendable (LinkingEvent) async -> Void

  init(
    pressing: @escaping @Sendable (SETButtonPrompt) async -> Void = { (_: SETButtonPrompt) async -> Void in },
    readying: @escaping @Sendable (DeviceFirstPrompt) async throws -> Void = { (_: DeviceFirstPrompt) async throws -> Void in },
    reacting: @escaping @Sendable (LinkingEvent) async -> Void = { (_: LinkingEvent) async -> Void in }
  ) {

    self.pressing = pressing
    self.readying = readying
    self.reacting = reacting

  }

  func linking(_ event: LinkingEvent) async {

    lines.append(Self.line(for: event))
    await reacting(event)

    if case let .pressSETButton(prompt) = event {

      prompts.append(prompt)
      await pressing(prompt)

    }

  }

  func waitUntilDeviceIsReady(_ prompt: DeviceFirstPrompt) async throws {

    lines.append("device first: \(Self.direction(prompt.direction)) \(prompt.device.map { "\($0)" } ?? "any") steps \(prompt.steps.count)")

    try await readying(prompt)

  }

  func waitUntilDeviceIsAwake(_ prompt: WakePrompt) async throws {

    lines.append("wake \(prompt.device) steps \(prompt.steps.count)")

  }

  static func direction(_ direction: LinkingDirection) -> String {

    direction == .linking ? "linking" : "unlinking"

  }

  static func role(_ role: ModemRole) -> String {

    role == .controller ? "controller" : "responder"

  }

  static func leg(_ leg: LinkLeg) -> String {

    switch leg {
    case .first:
      return "first"
    case .linkBack:
      return "back"
    case let .hubLinking(index):
      return "leg \(index + 1)"
    }

  }

  static func keepAwake(_ event: KeepAwakeEvent) -> String {

    switch event {
    case let .sending(device, timing):
      return "sending \(device) \(timing)"
    case let .sent(device):
      return "sent \(device)"
    case let .notSent(device, _):
      return "not sent \(device)"
    case let .releasing(device):
      return "releasing \(device)"
    case let .released(device):
      return "released \(device)"
    case let .notReleased(device, _):
      return "not released \(device)"
    }

  }

  static func join(_ join: HubLinkingJoin) -> String {

    switch join {
    case .enterLinkingMode:
      return "Enter Linking Mode"
    case .setButton:
      return "SET button"
    case .deviceFirst:
      return "device first"
    }

  }

  static func deletionReason(_ reason: ModemRecordDeletionReason) -> String {

    switch reason {
    case .noAnswer:
      return "no answer"
    case .remoteLinkingUnsupported:
      return "unsupported"
    case .remoteUnlinkingFailed:
      return "failed"
    case let .linksLeft(links):
      return "links left \(links.count)"
    case .modemLinksUnreadable:
      return "unreadable"
    }

  }

  static func keptReason(_ reason: DeviceKeptReason) -> String {

    switch reason {
    case let .linksRemain(links):
      return "links remain \(links.map { "\(role($0.modemRole)) \($0.group)" })"
    case .modemLinksUnreadable:
      return "unreadable"
    case .modemRecordsNotDeleted:
      return "records not deleted"
    }

  }

  static func line(for event: LinkingEvent) -> String {

    switch event {
    case let .identifying(device):
      return "identifying \(device)"
    case let .turningOnBeforeLinking(device):
      return "turning on \(device)"
    case let .notTurnedOnBeforeLinking(device, _):
      return "not turned on \(device)"
    case let .notTurningOnBeforeLinking(device):
      return "not turning on \(device)"
    case let .linkingRemotely(device, modemRole):
      return "linking remotely \(device) as \(role(modemRole))"
    case let .fallback(.setButtonLinking(device, _)):
      return "fallback: SET button linking \(device)"
    case let .fallback(.setButtonUnlinking(device, _, steps)):
      return "fallback: SET button unlinking \(device) steps \(steps.count)"
    case let .pressSETButton(prompt):
      return "press SET: \(direction(prompt.direction)) group \(prompt.group) \(prompt.device.map { "\($0)" } ?? "any") steps \(prompt.steps.count)"
    case let .modemJoining(timeout):
      return "modem joining \(timeout.components.seconds)"
    case let .linkingBack(device, group):
      return "linking back \(device) group \(group)"
    case let .linked(linked):
      return "linked \(linked.link.address) group \(linked.link.group) \(linked.link.mode?.name ?? "unknown") \(leg(linked.leg))"
    case let .hubLinkingLegStarted(leg):
      return "leg \(leg.index + 1)/\(leg.count) started \(role(leg.modemRole)) \(leg.modemGroup) device group \(leg.deviceGroup)"
    case let .hubLinkingLegJoined(leg, join):
      return "leg \(leg.index + 1) joined by \(self.join(join))"
    case let .hubLinkingLegCompleted(leg, link):
      return "leg \(leg.index + 1) completed group \(link.group) \(link.mode?.name ?? "unknown")"
    case let .hubLinkingLegFailed(leg, _, notRun):
      return "leg \(leg.index + 1) failed, not run \(notRun.count)"
    case let .allGroupsWhen(leg, condition):
      return "leg \(leg.index + 1) all groups when \(condition.flag) \(condition.isSet)"
    case let .keepAwake(keepAwake):
      return "keep awake: \(self.keepAwake(keepAwake))"
    case let .readingModemLinks(device, purpose):
      return "reading modem links \(device) \(purpose == .findingLinksToRemove ? "to remove" : "for group")"
    case let .unlinkGroupChosen(device, group, isFromModemRecords):
      return "unlink group \(device) \(group) \(isFromModemRecords ? "from records" : "default")"
    case let .unlinkingRemotely(device, _, link):
      return "unlinking remotely \(device) \(role(link.modemRole)) \(link.group)"
    case let .unlinked(unlinked):
      return "unlinked \(unlinked.link.address) group \(unlinked.link.group)"
    case let .unlinkedAll(removed):
      return "unlinked all \(removed.address) \(removed.links.map { "\(role($0.modemRole)) \($0.group)" })"
    case let .linksRemaining(device, links):
      return "remaining \(device) \(links.map { "\(role($0.modemRole)) \($0.group)" })"
    case let .remainingLinksUnknown(device, _):
      return "remaining unknown \(device)"
    case let .deletingModemRecords(device, reason):
      return "deleting modem records \(device) \(deletionReason(reason))"
    case let .modemRecordsDeleted(device, records):
      return "modem records deleted \(device) \(records.count)"
    case let .kept(device, reason):
      return "kept \(device) \(keptReason(reason))"
    case let .forgotten(forgotten):
      return "forgot \(forgotten.address) \(forgotten.device == nil ? "unknown" : "known")"
    case let .scanningDatabase(device, removedDevice):
      return "scanning \(device) for \(removedDevice)"
    case let .leftoverRecords(scan):
      return "leftovers for \(scan.removedDevice) \(scan.holders.map { "\($0.address) \($0.records.count)" }) unread \(scan.unread.map { "\($0.address)" })"
    case let .factoryReset(reset):
      return "factory reset \(reset.address) steps \(reset.procedure?.steps.count ?? 0)"
    }

  }

}

/// The coordinator on an in-memory modem, on a ``TestClock`` and fixed times.
struct DeviceLinkingCoordinatorTests {

  let clock: TestClock = TestClock()

  let times: FixedTimes = FixedTimes()

  func network(_ modem: InMemoryModem, identities: [InsteonAddress: ReportedIdentity] = [:], modemDatabase: [AllLinkRecord]? = nil) -> DeviceNetwork {

    let times: FixedTimes = self.times

    return DeviceNetwork(
      modem: modem,
      catalog: LinkingExample.catalog,
      snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: identities), modemDatabase: modemDatabase),
      clock: clock,
      now: { () -> Date in times.now() }
    )

  }

  func pressed(_ identity: ReportedIdentity, of device: InsteonAddress, role: SetButtonPressed.Role = .responder) -> SetButtonPressed {

    SetButtonPressed(sender: device, role: role, category: identity.category, subcategory: identity.subcategory, firmwareVersion: identity.firmwareVersion)

  }

  /// A recorder that presses the SET button of the device a prompt names, or else `device`.
  func pressing(_ device: InsteonAddress, on modem: InMemoryModem) -> LinkingRecorder {

    LinkingRecorder(pressing: { (prompt: SETButtonPrompt) async -> Void in

      await modem.pressSetButton(of: prompt.device ?? device)

    })

  }

  // MARK: - With the SET button

  @Test(.timeLimit(.minutes(1))) func linksBySETButtonAsController() async throws {

    let modem = InMemoryModem()
    let lamp: InsteonAddress = LinkingExample.lamp
    await modem.setIdentity(pressed(LinkingExample.lampIdentity, of: lamp))
    let network: DeviceNetwork = self.network(modem)
    let recorder: LinkingRecorder = pressing(lamp, on: modem)

    let result: DeviceLinkingResult = try await network.linking.linkBySETButton(as: .controller, observer: recorder)

    #expect(result.links.map(\.address) == [lamp])
    #expect(result.links.first?.mode == .controller)
    #expect(result.device?.identity == LinkingExample.lampIdentity)
    #expect(result.linkBackFailure == nil)
    #expect(await recorder.lines == [
      "press SET: linking group 0 any steps 0",
      "identifying \(lamp)",
      "linked \(lamp) group 0 controller first"
    ])
    #expect(await modem.linkingSteps.first == .modem(.controller, 0x00))
    #expect(await network.registry.device(lamp)?.identity == LinkingExample.lampIdentity)

  }

  @Test(.timeLimit(.minutes(1))) func linksBySETButtonAsResponderWithTheDeviceFirst() async throws {

    let modem = InMemoryModem()
    let sensor: InsteonAddress = LinkingExample.sensor
    let network: DeviceNetwork = self.network(modem, identities: [sensor: LinkingExample.sensorIdentity])
    // The person puts the device into linking mode before the modem joins.
    let recorder = LinkingRecorder(readying: { (_: DeviceFirstPrompt) async throws -> Void in

      await modem.pressSetButton(of: sensor)

    })

    let result: DeviceLinkingResult = try await network.linking.linkBySETButton(as: .responder, group: 0x01, observer: recorder)

    #expect(result.links.map(\.mode) == [.responder])
    #expect(await recorder.lines == [
      "device first: linking any steps 0",
      "modem joining 240",
      "linked \(sensor) group 1 responder first"
    ])
    #expect(await modem.linkingSteps == [.modem(.responder, 0x01)])

  }

  @Test(.timeLimit(.minutes(1))) func linksBySETButtonInEitherRole() async throws {

    let modem = InMemoryModem()
    let lamp: InsteonAddress = LinkingExample.lamp
    let network: DeviceNetwork = self.network(modem, identities: [lamp: LinkingExample.lampIdentity])

    let result: DeviceLinkingResult = try await network.linking.linkBySETButton(as: .either, observer: pressing(lamp, on: modem))

    #expect(result.links.map(\.address) == [lamp])
    #expect(await modem.linkingSteps == [.modem(.controllerOrResponder, 0x00)])

  }

  @Test(.timeLimit(.minutes(1))) func doesntLinkBackASETButtonLinkWhenToldNever() async throws {

    let modem = InMemoryModem()
    let sensor: InsteonAddress = LinkingExample.sensor
    let network: DeviceNetwork = self.network(modem, identities: [sensor: LinkingExample.sensorIdentity])

    let result: DeviceLinkingResult = try await network.linking.linkBySETButton(as: .controller, twoWay: .never, observer: pressing(sensor, on: modem))

    #expect(result.links.count == 1)

  }

  // MARK: - By address

  @Test(.timeLimit(.minutes(1))) func turnsALightOnBeforeLinkingItByAddress() async throws {

    let modem = InMemoryModem()
    let lamp: InsteonAddress = LinkingExample.lamp
    let network: DeviceNetwork = self.network(modem, identities: [lamp: LinkingExample.lampIdentity])
    let recorder = LinkingRecorder()

    let result: DeviceLinkingResult = try await network.linking.link(lamp, as: .controller, observer: recorder)

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    #expect(result.links.map(\.mode) == [.controller])
    #expect(await recorder.lines == [
      "turning on \(lamp)",
      "linking remotely \(lamp) as controller",
      "linked \(lamp) group 0 controller first"
    ])
    // Light On goes first, so the lamp records full on as its on-level.
    #expect(steps.first == .device(lamp, Command(command1: 0x11, command2: 0xFF), isExtended: false))
    #expect(await modem.levels[lamp] == 0xFF)
    #expect(await modem.databases[lamp]?.values.first?.data1 == 0xFF)

  }

  @Test(.timeLimit(.minutes(1))) func doesntTurnOnADeviceThatIsntALight() async throws {

    let modem = InMemoryModem()
    let module: InsteonAddress = LinkingExample.module
    let network: DeviceNetwork = self.network(modem, identities: [module: LinkingExample.moduleIdentity])
    let recorder = LinkingRecorder()

    _ = try await network.linking.link(module, as: .controller, observer: recorder)

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    #expect(await recorder.lines == [
      "not turning on \(module)",
      "linking remotely \(module) as controller",
      "linked \(module) group 0 controller first"
    ])
    #expect(!steps.contains(.device(module, Command(command1: 0x11, command2: 0xFF), isExtended: false)))

  }

  @Test(.timeLimit(.minutes(1))) func doesntTurnOnADeviceTheRegistryDoesntKnow() async throws {

    let modem = InMemoryModem()
    let lamp: InsteonAddress = LinkingExample.lamp
    await modem.setIdentity(pressed(LinkingExample.lampIdentity, of: lamp))
    let recorder = LinkingRecorder()

    _ = try await self.network(modem).linking.link(lamp, as: .controller, observer: recorder)

    #expect(await recorder.lines.first == "not turning on \(lamp)")
    #expect(await modem.levels[lamp] == nil)

  }

  @Test(.timeLimit(.minutes(1))) func fallsBackToTheCatalogsSETButtonSteps() async throws {

    let modem = InMemoryModem()
    let module: InsteonAddress = LinkingExample.module
    // An i1 device can't be linked remotely.
    await modem.setEngine(.i1, of: module)
    let network: DeviceNetwork = self.network(modem, identities: [module: LinkingExample.moduleIdentity])
    let recorder: LinkingRecorder = pressing(module, on: modem)

    let result: DeviceLinkingResult = try await network.linking.link(module, as: .controller, observer: recorder)

    #expect(result.links.map(\.address) == [module])
    #expect(await recorder.lines == [
      "not turning on \(module)",
      "linking remotely \(module) as controller",
      "fallback: SET button linking \(module)",
      // The step on the Hub is left out.
      "press SET: linking group 0 \(module) steps 1",
      "linked \(module) group 0 controller first"
    ])
    #expect(await recorder.prompts.first?.steps.map(\.text) == ["Hold the SET button."])
    #expect(await recorder.prompts.first?.deviceDescription?.profile?.model == "9203")

  }

  @Test(.timeLimit(.minutes(1))) func fallsBackToTheDeviceGoingFirstAsResponder() async throws {

    let modem = InMemoryModem()
    let sensor: InsteonAddress = LinkingExample.sensor
    await modem.setEngine(.i1, of: sensor)
    let network: DeviceNetwork = self.network(modem, identities: [sensor: LinkingExample.sensorIdentity])
    let recorder = LinkingRecorder(readying: { (_: DeviceFirstPrompt) async throws -> Void in

      await modem.pressSetButton(of: sensor)

    })

    let result: DeviceLinkingResult = try await network.linking.link(sensor, as: .responder, observer: recorder)

    #expect(result.links.map(\.mode) == [.responder])
    #expect(await recorder.lines == [
      "linking remotely \(sensor) as responder",
      "fallback: SET button linking \(sensor)",
      "device first: linking \(sensor) steps 1",
      "modem joining 240",
      "linked \(sensor) group 1 responder first"
    ])

  }

  @Test(.timeLimit(.minutes(1))) func linksBackADeviceTheCatalogSaysControls() async throws {

    let modem = InMemoryModem()
    let sensor: InsteonAddress = LinkingExample.sensor
    let network: DeviceNetwork = self.network(modem, identities: [sensor: LinkingExample.sensorIdentity])
    let recorder = LinkingRecorder()

    let result: DeviceLinkingResult = try await network.linking.link(sensor, as: .controller, observer: recorder)

    #expect(result.links.map(\.mode) == [.controller, .responder])
    #expect(result.links.map(\.group) == [0x00, 0x01])
    #expect(result.linkBackFailure == nil)
    #expect(await recorder.lines == [
      "not turning on \(sensor)",
      "linking remotely \(sensor) as controller",
      "linked \(sensor) group 0 controller first",
      "linking back \(sensor) group 1",
      "linked \(sensor) group 1 responder back"
    ])
    #expect(await modem.linkingSteps.contains(.modem(.responder, 0x01)))

  }

  @Test(.timeLimit(.minutes(1))) func linksBackInTheFirstGroupTheCatalogSaysTheDeviceControls() async throws {

    let modem = InMemoryModem()
    let keypad: InsteonAddress = LinkingExample.keypad
    let network: DeviceNetwork = self.network(modem, identities: [keypad: LinkingExample.keypadIdentity])
    let recorder = LinkingRecorder()

    let result: DeviceLinkingResult = try await network.linking.link(keypad, as: .controller, observer: recorder)

    // The keypad doesn't control group 1, so it links back in group 3, the first in the
    // catalog's order that it controls.
    #expect(result.links.map(\.mode) == [.controller, .responder])
    #expect(result.links.map(\.group) == [0x00, 0x03])
    #expect(await recorder.lines.suffix(2) == ["linking back \(keypad) group 3", "linked \(keypad) group 3 responder back"])
    #expect(await modem.linkingSteps.contains(.modem(.responder, 0x03)))

  }

  @Test(.timeLimit(.minutes(1))) func linksBackASETButtonLinkOfADeviceThatControls() async throws {

    let modem = InMemoryModem()
    let keypad: InsteonAddress = LinkingExample.keypad
    let network: DeviceNetwork = self.network(modem, identities: [keypad: LinkingExample.keypadIdentity])

    let result: DeviceLinkingResult = try await network.linking.linkBySETButton(as: .controller, observer: pressing(keypad, on: modem))

    #expect(result.links.map(\.mode) == [.controller, .responder])
    #expect(result.links.map(\.group) == [0x00, 0x03])

  }

  @Test(.timeLimit(.minutes(1))) func joinsTheGroupTheDeviceControlsAsResponder() async throws {

    let modem = InMemoryModem()
    let keypad: InsteonAddress = LinkingExample.keypad
    let network: DeviceNetwork = self.network(modem, identities: [keypad: LinkingExample.keypadIdentity])
    let recorder = LinkingRecorder()

    let result: DeviceLinkingResult = try await network.linking.link(keypad, as: .responder, observer: recorder)

    // The modem joins group 3, not the group it was given or group 1.
    #expect(result.links.map(\.mode) == [.responder])
    #expect(result.links.map(\.group) == [0x03])
    #expect(await modem.linkingSteps.contains(.modem(.responder, 0x03)))
    #expect(await recorder.lines == ["linking remotely \(keypad) as responder", "linked \(keypad) group 3 responder first"])

  }

  @Test(.timeLimit(.minutes(1))) func doesntLinkBackADeviceThatOnlyResponds() async throws {

    let modem = InMemoryModem()
    let lamp: InsteonAddress = LinkingExample.lamp
    let network: DeviceNetwork = self.network(modem, identities: [lamp: LinkingExample.lampIdentity])

    let result: DeviceLinkingResult = try await network.linking.link(lamp, as: .controller, observer: LinkingRecorder())

    #expect(result.links.count == 1)
    #expect(await !modem.linkingSteps.contains(.modem(.responder, 0x01)))

  }

  @Test(.timeLimit(.minutes(1))) func reportsALinkBackThatFailsWithoutThrowing() async throws {

    let modem = InMemoryModem()
    let lamp: InsteonAddress = LinkingExample.lamp
    let network: DeviceNetwork = self.network(modem, identities: [lamp: LinkingExample.lampIdentity])
    // The lamp joins the modem's group, then answers as an i1 device, which can't link back
    // without its SET button.
    let recorder = LinkingRecorder(reacting: { (event: LinkingEvent) async -> Void in

      if case .linkingBack = event {

        await modem.setEngine(.i1, of: lamp)

      }

    })

    let result: DeviceLinkingResult = try await network.linking.link(lamp, as: .controller, twoWay: .always, observer: recorder)

    #expect(result.links.count == 1)
    #expect((result.linkBackFailure as? LinkingError) == .remoteLinkingUnsupported(lamp))
    #expect(await recorder.lines.suffix(2) == ["linked \(lamp) group 0 controller first", "linking back \(lamp) group 1"])

  }

  @Test(.timeLimit(.minutes(1))) func throwsAMismatchWhenAnotherDeviceLinksRemotely() async throws {

    let modem = InMemoryModem()
    let module: InsteonAddress = LinkingExample.module
    let lamp: InsteonAddress = LinkingExample.lamp
    let network: DeviceNetwork = self.network(modem, identities: [module: LinkingExample.moduleIdentity])
    // The lamp is waiting in linking mode when the modem starts.
    await modem.pressSetButton(of: lamp)

    await #expect(throws: LinkMismatch.self) {

      _ = try await network.linking.link(module, as: .controller, observer: LinkingRecorder())

    }

  }

  // MARK: - Unlinking

  @Test(.timeLimit(.minutes(1))) func unlinksOneLinkInTheGroupTheModemsRecordsShow() async throws {

    let modem = InMemoryModem()
    let lamp: InsteonAddress = LinkingExample.lamp
    let controls = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x03, address: lamp)
    await modem.setModemRecords([controls])
    await modem.setRecordsLinks()
    let network: DeviceNetwork = self.network(modem, identities: [lamp: LinkingExample.lampIdentity])
    let recorder: LinkingRecorder = pressing(lamp, on: modem)

    let result: DeviceUnlinkingResult = try await network.linking.unlink(lamp, as: .controller, observer: recorder)

    #expect(result.link.link.mode == .delete)
    #expect(result.link.link.group == 0x03)
    #expect(result.link.device?.identity == LinkingExample.lampIdentity)
    #expect(result.remainingLinks == [])
    #expect(await recorder.lines == [
      "reading modem links \(lamp) for group",
      "unlink group \(lamp) 3 from records",
      "press SET: unlinking group 3 \(lamp) steps 1",
      "unlinked \(lamp) group 3",
      "remaining \(lamp) []"
    ])
    // The snapshot holds the modem's records as read after the unlink.
    #expect(await network.snapshot().modemDatabase == [])

  }

  @Test(.timeLimit(.minutes(1))) func unlinksAsResponderWithTheDeviceFirst() async throws {

    let modem = InMemoryModem()
    let sensor: InsteonAddress = LinkingExample.sensor
    let responds = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 0x01, address: sensor)
    let controls = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x00, address: sensor)
    await modem.setModemRecords([responds, controls])
    await modem.setRecordsLinks()
    let network: DeviceNetwork = self.network(modem, identities: [sensor: LinkingExample.sensorIdentity])
    let recorder = LinkingRecorder(readying: { (_: DeviceFirstPrompt) async throws -> Void in

      await modem.pressSetButton(of: sensor, unlinking: true)

    })

    let result: DeviceUnlinkingResult = try await network.linking.unlink(sensor, as: .responder, group: 0x01, observer: recorder)

    #expect(result.remainingLinks == [ModemLink(modemRole: .controller, group: 0x00)])
    #expect(await recorder.lines == [
      "device first: unlinking \(sensor) steps 1",
      "modem joining 240",
      "unlinked \(sensor) group 1",
      "remaining \(sensor) [\"controller 0\"]"
    ])

  }

  @Test(.timeLimit(.minutes(1))) func unlinksAllLinksWithGroupZeroLast() async throws {

    let modem = InMemoryModem()
    let lamp: InsteonAddress = LinkingExample.lamp
    await modem.setModemRecords([
      AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x00, address: lamp),
      AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 0x01, address: lamp),
      AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x02, address: lamp)
    ])
    await modem.setRecordsLinks()
    let network: DeviceNetwork = self.network(modem, identities: [lamp: LinkingExample.lampIdentity])
    let recorder = LinkingRecorder()

    let result: DeviceUnlinkingAllResult = try await network.linking.unlinkAll(lamp, observer: recorder)

    let modemSteps: [InMemoryModem.LinkingStep] = await modem.linkingSteps.filter { (step: InMemoryModem.LinkingStep) -> Bool in

      guard case .modem = step else {

        return false

      }

      return true

    }

    #expect(result.removed.links == [
      ModemLink(modemRole: .responder, group: 0x01),
      ModemLink(modemRole: .controller, group: 0x02),
      ModemLink(modemRole: .controller, group: 0x00)
    ])
    #expect(result.remainingLinks == [])
    #expect(modemSteps == [.modem(.responder, 0x01), .modem(.delete, 0x02), .modem(.delete, 0x00)])
    #expect(await recorder.lines == [
      "reading modem links \(lamp) to remove",
      "unlinking remotely \(lamp) responder 1",
      "unlinking remotely \(lamp) controller 2",
      "unlinking remotely \(lamp) controller 0",
      "unlinked all \(lamp) [\"responder 1\", \"controller 2\", \"controller 0\"]",
      "remaining \(lamp) []"
    ])
    #expect(await network.snapshot().modemDatabase == [])

  }

  @Test(.timeLimit(.minutes(1))) func sendsABatteryPoweredDeviceEnterUnlinkingModeExtended() async throws {

    let modem = InMemoryModem()
    let sensor: InsteonAddress = LinkingExample.sensor
    await modem.setEngine(.i2cs, of: sensor)
    await modem.setModemRecords([AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 0x01, address: sensor)])
    await modem.setRecordsLinks()
    let network: DeviceNetwork = self.network(modem, identities: [sensor: LinkingExample.sensorIdentity])

    _ = try await network.linking.unlinkAll(sensor, observer: LinkingRecorder())

    let extended: Bool = await modem.linkingSteps.contains { (step: InMemoryModem.LinkingStep) -> Bool in

      guard case let .device(device, command, isExtended) = step else {

        return false

      }

      return device == sensor && command.command1 == 0x0A && isExtended

    }

    #expect(extended)

  }

  @Test(.timeLimit(.minutes(1))) func fallsBackToTheSETButtonWhenLinksCantBeRemovedRemotely() async throws {

    let modem = InMemoryModem()
    let module: InsteonAddress = LinkingExample.module
    await modem.setEngine(.i1, of: module)
    await modem.setModemRecords([AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x00, address: module)])
    let network: DeviceNetwork = self.network(modem, identities: [module: LinkingExample.moduleIdentity])
    let recorder = LinkingRecorder()

    do {

      _ = try await network.linking.unlinkAll(module, observer: recorder)
      Issue.record("Expected the remote unlink to fail.")

    } catch let error as RemoteUnlinkingError {

      #expect(error.device == module)
      #expect(error.deviceDescription?.profile?.model == "9203")
      #expect((error.underlying as? LinkingError) == .remoteLinkingUnsupported(module))

    }

    #expect(await recorder.lines == [
      "reading modem links \(module) to remove",
      "unlinking remotely \(module) controller 0",
      "remaining \(module) [\"controller 0\"]",
      "fallback: SET button unlinking \(module) steps 1"
    ])

  }

  @Test(.timeLimit(.minutes(1))) func saysWhenTheModemHasNoLinksWithADevice() async throws {

    let modem = InMemoryModem()
    let lamp: InsteonAddress = LinkingExample.lamp
    let recorder = LinkingRecorder()

    let result: DeviceUnlinkingAllResult = try await self.network(modem).linking.unlinkAll(lamp, observer: recorder)

    #expect(result.removed.links.isEmpty)
    #expect(result.removed.device == nil)
    #expect(await recorder.lines == [
      "reading modem links \(lamp) to remove",
      "unlinked all \(lamp) []",
      "remaining \(lamp) []"
    ])

  }

  // MARK: - Cancellation

  @Test(.timeLimit(.minutes(1))) func cancelsALinkWaitingForTheSETButton() async throws {

    let modem = InMemoryModem()
    let network: DeviceNetwork = self.network(modem)
    let linking = Task { () async throws -> DeviceLinkingResult in

      try await network.linking.linkBySETButton(as: .controller, observer: LinkingRecorder())

    }

    await clock.waitForSleeper(until: Linker.defaultManualLinkingTimeout)
    linking.cancel()

    await #expect(throws: CancellationError.self) {

      _ = try await linking.value

    }

    #expect(await modem.linkingSteps == [.modem(.controller, 0x00), .cancel])

  }

  @Test(.timeLimit(.minutes(1))) func cancelsARemoteLinkAndTakesTheDeviceOutOfLinkingMode() async throws {

    let modem = InMemoryModem()
    let module: InsteonAddress = LinkingExample.module
    await modem.setSilent(module)
    let network: DeviceNetwork = self.network(modem, identities: [module: LinkingExample.moduleIdentity])
    let recorder = LinkingRecorder()
    let linking = Task { () async throws -> DeviceLinkingResult in

      try await network.linking.link(module, as: .controller, observer: recorder)

    }

    await clock.waitForSleeper(until: Linker.defaultRemoteLinkingTimeout)
    linking.cancel()

    await #expect(throws: CancellationError.self) {

      _ = try await linking.value

    }

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    #expect(steps.suffix(2) == [.cancel, .device(module, Command(command1: 0x08), isExtended: false)])
    // Canceling doesn't fall back to the SET button.
    #expect(await recorder.lines == ["not turning on \(module)", "linking remotely \(module) as controller"])

  }

  @Test(.timeLimit(.minutes(1))) func cancelsWhileTheDeviceIsPutIntoItsModeFirst() async throws {

    let modem = InMemoryModem()
    let network: DeviceNetwork = self.network(modem)
    let recorder = LinkingRecorder(readying: { (_: DeviceFirstPrompt) async throws -> Void in

      throw CancellationError()

    })

    await #expect(throws: CancellationError.self) {

      _ = try await network.linking.linkBySETButton(as: .responder, observer: recorder)

    }

    // The modem never entered linking mode.
    #expect(await modem.linkingSteps.isEmpty)

  }

  // MARK: - What the network keeps

  @Test(.timeLimit(.minutes(1))) func updatesTheSnapshotAndCacheAfterALink() async throws {

    let modem = InMemoryModem()
    let lamp: InsteonAddress = LinkingExample.lamp
    let stale = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x05, address: lamp)
    await modem.setIdentity(pressed(LinkingExample.lampIdentity, of: lamp))
    let network: DeviceNetwork = self.network(modem, modemDatabase: [stale])

    // A copy of the lamp's database, which the link changes.
    _ = try await network.allLinkDatabase(of: lamp)
    #expect(await network.cache.copies[lamp] != nil)

    _ = try await network.linking.linkBySETButton(as: .controller, observer: pressing(lamp, on: modem))

    let snapshot: NetworkSnapshot = await network.snapshot()

    #expect(snapshot.registry.identities[lamp] == LinkingExample.lampIdentity)
    #expect(snapshot.modemDatabase == nil)
    #expect(snapshot.devices[lamp]?.allLinkDatabase == nil)
    #expect(snapshot.devices[lamp]?.lastSeen != nil)
    #expect(await network.cache.copies[lamp] == nil)

  }

  // MARK: - What the network keeps when a link or unlink throws

  /// A record of the modem's that the network's snapshot holds until a link changes it.
  static let staleRecord = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x05, address: LinkingExample.module)

  /// A network whose snapshot holds the modem's records, with copies of the devices' ALL-Link
  /// databases in its cache.
  func networkWithCopies(
    _ modem: InMemoryModem,
    of devices: [InsteonAddress],
    identities: [InsteonAddress: ReportedIdentity] = [:]
  ) async throws -> DeviceNetwork {

    let network: DeviceNetwork = self.network(modem, identities: identities, modemDatabase: [Self.staleRecord])

    for device in devices {

      _ = try await network.allLinkDatabase(of: device)

    }

    return network

  }

  /// Whether the network forgot its copy of a device's ALL-Link database and the modem's
  /// records its snapshot held.
  func forgot(_ device: InsteonAddress, in network: DeviceNetwork) async -> Bool {

    let hasCopy: Bool = await network.cache.copies[device] != nil
    let snapshot: NetworkSnapshot = await network.snapshot()

    return !hasCopy && snapshot.modemDatabase == nil

  }

  @Test(.timeLimit(.minutes(1))) func recordsALinkCanceledWhileTheDeviceIsIdentified() async throws {

    let modem = InMemoryModem()
    let lamp: InsteonAddress = LinkingExample.lamp
    let network: DeviceNetwork = try await networkWithCopies(modem, of: [lamp])
    // The lamp sends no identity broadcast, so ID Request waits on the clock. Its database is
    // read again as it's asked, so only the canceled link can forget the copy.
    let recorder = LinkingRecorder(
      pressing: { (_: SETButtonPrompt) async -> Void in

        await modem.pressSetButton(of: lamp)

      },
      reacting: { (event: LinkingEvent) async -> Void in

        if case .identifying = event {

          _ = try? await network.allLinkDatabase(of: lamp)

        }

      }
    )
    let linking = Task { () async throws -> DeviceLinkingResult in

      try await network.linking.linkBySETButton(as: .controller, observer: recorder)

    }

    await clock.waitForSleeper(until: Modem.defaultRequestTimeout)
    linking.cancel()

    await #expect(throws: CancellationError.self) {

      _ = try await linking.value

    }

    #expect(await forgot(lamp, in: network))

  }

  @Test(.timeLimit(.minutes(1))) func recordsALinkCanceledDuringTheLinkBack() async throws {

    let modem = InMemoryModem()
    let sensor: InsteonAddress = LinkingExample.sensor
    let network: DeviceNetwork = try await networkWithCopies(modem, of: [sensor], identities: [sensor: LinkingExample.sensorIdentity])
    let (linkingBack, signal): (AsyncStream<Void>, AsyncStream<Void>.Continuation) = AsyncStream<Void>.makeStream()
    // The sensor links as the modem's responder, then never links back. Its database is read
    // again before the link back, so only the canceled link back can forget the copy.
    let recorder = LinkingRecorder(reacting: { (event: LinkingEvent) async -> Void in

      if case .linkingBack = event {

        _ = try? await network.allLinkDatabase(of: sensor)
        await modem.setSilent(sensor)
        signal.yield()

      }

    })
    let linking = Task { () async throws -> DeviceLinkingResult in

      try await network.linking.link(sensor, as: .controller, observer: recorder)

    }

    var events: AsyncStream<Void>.Iterator = linkingBack.makeAsyncIterator()

    _ = await events.next()
    linking.cancel()

    await #expect(throws: CancellationError.self) {

      _ = try await linking.value

    }

    #expect(await forgot(sensor, in: network))

  }

  @Test(.timeLimit(.minutes(1))) func recordsTheDeviceThatUnlinkedInsteadOfLinkingBySETButton() async throws {

    let modem = InMemoryModem()
    let lamp: InsteonAddress = LinkingExample.lamp
    let network: DeviceNetwork = try await networkWithCopies(modem, of: [lamp])
    let recorder = LinkingRecorder(pressing: { (_: SETButtonPrompt) async -> Void in

      await modem.pressSetButton(of: lamp, unlinking: true)

    })

    do {

      _ = try await network.linking.linkBySETButton(as: .controller, observer: recorder)
      Issue.record("Expected a mismatch.")

    } catch let mismatch as LinkMismatch {

      #expect(mismatch.reason == .unlinkedInsteadOfLinking)

    }

    #expect(await forgot(lamp, in: network))

  }

  @Test(.timeLimit(.minutes(1))) func recordsALinkInAnotherGroupThanAskedBySETButton() async throws {

    let modem = InMemoryModem()
    let lamp: InsteonAddress = LinkingExample.lamp
    await modem.setReportedGroup(0x05, of: lamp)
    let network: DeviceNetwork = try await networkWithCopies(modem, of: [lamp])

    do {

      _ = try await network.linking.linkBySETButton(as: .controller, observer: pressing(lamp, on: modem))
      Issue.record("Expected an unexpected link.")

    } catch let LinkingError.unexpectedLink(link) {

      #expect(link.address == lamp)
      #expect(link.group == 0x05)

    }

    #expect(await forgot(lamp, in: network))

  }

  @Test(.timeLimit(.minutes(1))) func recordsTheOtherDeviceThatLinkedInsteadOfTheOneAskedFor() async throws {

    let modem = InMemoryModem()
    let module: InsteonAddress = LinkingExample.module
    let lamp: InsteonAddress = LinkingExample.lamp
    let network: DeviceNetwork = try await networkWithCopies(modem, of: [module, lamp], identities: [module: LinkingExample.moduleIdentity])
    // The module can't be linked remotely, and the lamp's SET button is pressed instead.
    await modem.setEngine(.i1, of: module)
    let recorder = LinkingRecorder(pressing: { (_: SETButtonPrompt) async -> Void in

      await modem.pressSetButton(of: lamp)

    })

    do {

      _ = try await network.linking.link(module, as: .controller, observer: recorder)
      Issue.record("Expected a mismatch.")

    } catch let mismatch as LinkMismatch {

      #expect(mismatch.link.address == lamp)
      #expect(mismatch.reason == .otherDevice(expected: module))

    }

    #expect(await forgot(lamp, in: network))
    #expect(await forgot(module, in: network))

  }

  @Test(.timeLimit(.minutes(1))) func recordsTheOtherDeviceThatUnlinkedInsteadOfTheOneAskedFor() async throws {

    let modem = InMemoryModem()
    let module: InsteonAddress = LinkingExample.module
    let lamp: InsteonAddress = LinkingExample.lamp
    let network: DeviceNetwork = try await networkWithCopies(modem, of: [module, lamp], identities: [lamp: LinkingExample.lampIdentity])
    let recorder = LinkingRecorder(pressing: { (_: SETButtonPrompt) async -> Void in

      await modem.pressSetButton(of: module)

    })

    do {

      _ = try await network.linking.unlink(lamp, as: .controller, group: 0x00, observer: recorder)
      Issue.record("Expected a mismatch.")

    } catch let mismatch as LinkMismatch {

      #expect(mismatch.link.address == module)
      #expect(mismatch.reason == .otherDevice(expected: lamp))

    }

    #expect(await forgot(module, in: network))
    #expect(await forgot(lamp, in: network))

  }

  @Test(.timeLimit(.minutes(1))) func recordsAnUnlinkInAnotherGroupThanAsked() async throws {

    let modem = InMemoryModem()
    let lamp: InsteonAddress = LinkingExample.lamp
    await modem.setReportedGroup(0x03, of: lamp)
    let network: DeviceNetwork = try await networkWithCopies(modem, of: [lamp], identities: [lamp: LinkingExample.lampIdentity])

    do {

      _ = try await network.linking.unlink(nil, as: .controller, group: 0x00, observer: pressing(lamp, on: modem))
      Issue.record("Expected an unexpected link.")

    } catch let LinkingError.unexpectedLink(link) {

      #expect(link.address == lamp)
      #expect(link.group == 0x03)

    }

    #expect(await forgot(lamp, in: network))

  }

  // MARK: - Taking turns

  @Test(.timeLimit(.minutes(1))) func takesTurnsInOrder() async throws {

    let turns = LinkingTurns()

    try await turns.begin()

    let second = Task { () async throws -> Void in

      try await turns.begin()
      await turns.end()

    }

    while await turns.waitingCount == 0 {

      await Task.yield()

    }

    await turns.end()
    try await second.value

    // Once every turn ended, the next one is taken at once.
    try await turns.begin()
    await turns.end()

  }

  @Test(.timeLimit(.minutes(1))) func stopsWaitingForATurnWhenCanceled() async throws {

    let turns = LinkingTurns()

    try await turns.begin()

    let waiting = Task { () async throws -> Void in

      try await turns.begin()

    }

    while await turns.waitingCount == 0 {

      await Task.yield()

    }

    waiting.cancel()

    await #expect(throws: CancellationError.self) {

      try await waiting.value

    }

    #expect(await turns.waitingCount == 0)
    #expect(await turns.openTicketCount == 0)
    await turns.end()

  }

  @Test(.timeLimit(.minutes(1))) func keepsNothingForACancellationAfterTheTurnIsHandedOver() async throws {

    let turns = LinkingTurns()

    try await turns.begin()

    // The first caller to wait gets ticket 0.
    let second = Task { () async throws -> Void in

      try await turns.begin()

    }

    while await turns.waitingCount == 0 {

      await Task.yield()

    }

    #expect(await turns.openTicketCount == 1)

    await turns.end()
    try await second.value

    // A cancellation that arrives once the caller has its turn, as one can between the
    // handover and the caller's return, leaves nothing behind.
    await turns.cancel(0)

    #expect(await turns.openTicketCount == 0)
    #expect(await turns.canceledTicketCount == 0)

    // Nor does one for a ticket that was never handed out.
    await turns.cancel(7)

    #expect(await turns.canceledTicketCount == 0)
    await turns.end()

    // The next caller takes the turn at once.
    try await turns.begin()
    await turns.end()

  }

  @Test(.timeLimit(.minutes(1))) func givesThreeWaitersTheirTurnsInTheOrderTheyAsked() async throws {

    let turns = LinkingTurns()
    let log = TurnLog()

    try await turns.begin()

    var waiting: [Task<Void, any Error>] = []

    for caller in 1...3 {

      waiting.append(Task { () async throws -> Void in

        try await turns.begin()
        await log.append(caller)
        await turns.end()

      })

      // Each caller is waiting before the next asks.
      while await turns.waitingCount < caller {

        await Task.yield()

      }

    }

    await turns.end()

    for task in waiting {

      try await task.value

    }

    #expect(await log.entries == [1, 2, 3])
    #expect(await turns.openTicketCount == 0)

  }

  @Test(.timeLimit(.minutes(1))) func runsTwoCoordinatorCallsOneAfterTheOther() async throws {

    let modem = InMemoryModem()
    let module: InsteonAddress = LinkingExample.module
    let lamp: InsteonAddress = LinkingExample.lamp
    // The module never links, so the first call waits until it's canceled.
    await modem.setSilent(module)
    await modem.setIdentity(pressed(LinkingExample.lampIdentity, of: lamp))
    let network: DeviceNetwork = self.network(modem, identities: [module: LinkingExample.moduleIdentity])
    let first = Task { () async throws -> DeviceLinkingResult in

      try await network.linking.link(module, as: .controller, observer: LinkingRecorder())

    }

    await clock.waitForSleeper(until: Linker.defaultRemoteLinkingTimeout)

    let recorder: LinkingRecorder = pressing(lamp, on: modem)
    let second = Task { () async throws -> DeviceLinkingResult in

      try await network.linking.linkBySETButton(as: .controller, observer: recorder)

    }

    while await network.linkingTurns.waitingCount == 0 {

      await Task.yield()

    }

    // The second call waits for its turn, so the modem entered linking mode once.
    let before: [InMemoryModem.LinkingStep] = await modem.linkingSteps

    #expect(before.filter { (step: InMemoryModem.LinkingStep) -> Bool in step == .modem(.controller, 0x00) }.count == 1)
    #expect(!before.contains(.cancel))

    first.cancel()

    await #expect(throws: CancellationError.self) {

      _ = try await first.value

    }

    let result: DeviceLinkingResult = try await second.value
    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps
    let canceled: Int? = steps.firstIndex(of: .cancel)
    let secondStart: Int? = steps.lastIndex(of: .modem(.controller, 0x00))

    #expect(result.links.map(\.address) == [lamp])
    // The first call left linking mode before the second entered it.
    #expect((canceled ?? Int.max) < (secondStart ?? Int.min))

  }

  @Test func linksBackToTheBundledProductsWhoseLoadAlsoControls() throws {

    let catalog: DeviceCatalog = try DeviceCatalog.bundled()

    // The outdoor plug and the I/O module control in group 1 as well as respond, so linking
    // makes the modem their responder too; a dimmer switch's load also controls.
    let identities: [(DeviceCategory, DeviceSubcategory)] = [(0x02, 0x38), (0x07, 0x00), (0x01, 0x20)]

    for (category, subcategory) in identities {

      let description: DeviceDescription = catalog.describe(category: category, subcategory: subcategory, firmwareVersion: 0x42)

      #expect(description.profile != nil, "\(category)/\(subcategory)")
      #expect(DeviceLinkingCoordinator.controls(description), "\(category)/\(subcategory)")
      #expect(DeviceLinkingCoordinator.controllingGroup(of: description) == 1, "\(category)/\(subcategory)")

    }

  }

}

/// The order callers took their turns in.
actor TurnLog {

  private(set) var entries: [Int] = []

  func append(_ entry: Int) {

    entries.append(entry)

  }

}
