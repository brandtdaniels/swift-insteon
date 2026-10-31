import Foundation
import Testing
@testable import InsteonCore
import InsteonDeviceCatalog
import InsteonLinking
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// Made-up devices to remove: a lamp, an i2CS dimmer whose catalog entry has reset steps; a
/// keypad that controls it in a scene; and a sensor whose database can't be read.
enum RemovalExample {

  static let lamp = InsteonAddress(0x3C, 0x4D, 0x01)

  static let keypad = InsteonAddress(0x3C, 0x4D, 0x02)

  static let sensor = InsteonAddress(0x3C, 0x4D, 0x03)

  static let lampIdentity = ReportedIdentity(category: 0x01, subcategory: 0x6A, firmwareVersion: 0x45)

  static let keypadIdentity = ReportedIdentity(category: 0x01, subcategory: 0x6B, firmwareVersion: 0x45)

  static let sensorIdentity = ReportedIdentity(category: 0x10, subcategory: 0x6C, firmwareVersion: 0x45)

  static let unlinkingSteps: [DeviceLifecycle.Step] = [
    DeviceLifecycle.Step(text: "Hold the SET button until it beeps, then hold it again.")
  ]

  static let resetSteps: [DeviceLifecycle.Step] = [
    DeviceLifecycle.Step(text: "Pull the air gap out.", action: .pullTab),
    DeviceLifecycle.Step(text: "Push it in while holding the paddle down.", expectation: "A long beep")
  ]

  static let catalog = DeviceCatalog(profiles: [
    DeviceProfile(
      model: "9301",
      name: "Example Removable Dimmer",
      identities: [DeviceIdentity(category: 0x01, subcategory: 0x6A)],
      groups: [DeviceProfile.Group(number: 1, name: "Load", role: .responder)],
      lifecycle: DeviceLifecycle(
        unlinking: DeviceLifecycle.Procedure(steps: unlinkingSteps),
        reset: DeviceLifecycle.Procedure(steps: resetSteps),
        resetErases: [.links, .settings]
      )
    ),
    DeviceProfile(
      model: "9302",
      name: "Example Scene Keypad",
      identities: [DeviceIdentity(category: 0x01, subcategory: 0x6B)],
      groups: [DeviceProfile.Group(number: 3, name: "Button C", role: .controller)]
    )
  ])

  /// The modem's records for the lamp: it responds to the lamp's group 1, and controls it in
  /// its own group 0.
  static let lampRecords: [AllLinkRecord] = [
    AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x00, address: lamp),
    AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 0x01, address: lamp)
  ]

  /// A record of the modem's for the keypad, which removing the lamp leaves alone.
  static let keypadRecord = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x00, address: keypad)

}

/// Removing a device with ``DeviceLinkingCoordinator/remove(_:scan:forceModemSide:timeout:observer:)``,
/// on an in-memory modem, a ``TestClock`` and fixed times.
struct DeviceRemovalTests {

  let clock: TestClock = TestClock()

  let times: FixedTimes = FixedTimes()

  /// A network that knows the lamp, the keypad and the sensor, with the modem's records for
  /// the lamp and the keypad, and a copy of the lamp's database and its state.
  func network(_ modem: InMemoryModem) async -> DeviceNetwork {

    await modem.setModemRecords(RemovalExample.lampRecords + [RemovalExample.keypadRecord])
    await modem.setRecordsLinks()

    let times: FixedTimes = self.times
    let lampCopy = AllLinkDatabaseCopy(delta: 0x00, records: [])
    let snapshot = NetworkSnapshot(
      registry: DeviceRegistrySnapshot(identities: [
        RemovalExample.lamp: RemovalExample.lampIdentity,
        RemovalExample.keypad: RemovalExample.keypadIdentity,
        RemovalExample.sensor: RemovalExample.sensorIdentity
      ]),
      devices: [
        RemovalExample.lamp: NetworkDeviceState(engine: .i2cs, allLinkDatabase: lampCopy, level: 0xFF, lastSeen: Date(timeIntervalSince1970: 1_700_000_000))
      ],
      modemDatabase: RemovalExample.lampRecords + [RemovalExample.keypadRecord]
    )

    return DeviceNetwork(
      modem: modem,
      catalog: RemovalExample.catalog,
      snapshot: snapshot,
      clock: clock,
      now: { () -> Date in times.now() }
    )

  }

  /// The modem's steps in linking: the modes it entered and left.
  func modemSteps(_ modem: InMemoryModem) async -> [InMemoryModem.LinkingStep] {

    await modem.linkingSteps.filter { (step: InMemoryModem.LinkingStep) -> Bool in

      switch step {
      case .modem, .cancel:
        return true
      case .device:
        return false
      }

    }

  }

  // MARK: - Removing

  @Test(.timeLimit(.minutes(1))) func removesAnI2csDevicesLinksWithGroupZeroLast() async throws {

    let modem = InMemoryModem()
    let lamp: InsteonAddress = RemovalExample.lamp
    await modem.setEngine(.i2cs, of: lamp)
    let network: DeviceNetwork = await self.network(modem)
    let recorder = LinkingRecorder()

    let result: DeviceRemovalResult = try await network.linking.remove(lamp, observer: recorder)

    let steps: [InMemoryModem.LinkingStep] = await modem.linkingSteps
    let sentExtendedLinkingMode: Bool = steps.contains { (step: InMemoryModem.LinkingStep) -> Bool in

      guard case let .device(device, command, isExtended) = step else {

        return false

      }

      return device == lamp && command.command1 == 0x09 && isExtended

    }

    // The link the lamp controls goes first, and the modem's group 0 last.
    #expect(result.removed.links == [ModemLink(modemRole: .responder, group: 0x01), ModemLink(modemRole: .controller, group: 0x00)])
    #expect(await modemSteps(modem) == [.modem(.responder, 0x01), .modem(.delete, 0x00)])
    #expect(sentExtendedLinkingMode)
    #expect(result.remainingLinks == [])
    #expect(result.remoteUnlinkingFailure == nil)
    #expect(result.deletedModemRecords.isEmpty)
    #expect(await modem.modemRecords == [RemovalExample.keypadRecord])
    #expect(await recorder.lines == [
      "reading modem links \(lamp) to remove",
      "unlinking remotely \(lamp) responder 1",
      "unlinking remotely \(lamp) controller 0",
      "unlinked all \(lamp) [\"responder 1\", \"controller 0\"]",
      "remaining \(lamp) []",
      "forgot \(lamp) known",
      "factory reset \(lamp) steps 2"
    ])

  }

  @Test(.timeLimit(.minutes(1))) func forgetsTheDeviceEverywhere() async throws {

    let modem = InMemoryModem()
    let lamp: InsteonAddress = RemovalExample.lamp
    let network: DeviceNetwork = await self.network(modem)
    let start: NetworkSnapshot = await network.snapshot()

    #expect(start.devices[lamp]?.allLinkDatabase != nil)

    let result: DeviceRemovalResult = try await network.linking.remove(lamp, observer: LinkingRecorder())

    let snapshot: NetworkSnapshot = await network.snapshot()
    let modemDatabase: [AllLinkRecord] = snapshot.modemDatabase ?? []

    #expect(result.forgotten?.address == lamp)
    #expect(result.forgotten?.device?.identity == RemovalExample.lampIdentity)
    #expect(await network.registry.device(lamp) == nil)
    #expect(await network.state(of: lamp) == nil)
    #expect(await network.cache.copies[lamp] == nil)
    #expect(snapshot.registry.identities[lamp] == nil)
    #expect(snapshot.devices[lamp] == nil)
    #expect(!modemDatabase.contains { (record: AllLinkRecord) -> Bool in record.address == lamp })
    #expect(modemDatabase.contains(RemovalExample.keypadRecord))
    // The other devices stay known.
    #expect(snapshot.registry.identities[RemovalExample.keypad] == RemovalExample.keypadIdentity)

    // A store's snapshot merged with what changed forgets the lamp too.
    let saved: NetworkSnapshot = start.merging(changesFrom: start, to: snapshot)

    #expect(saved.registry.identities[lamp] == nil)
    #expect(saved.devices[lamp] == nil)

  }

  @Test(.timeLimit(.minutes(1))) func forgetsTheDevicesRecordsInTheSnapshotsCopyOfTheModemsDatabase() async throws {

    let modem = InMemoryModem()
    let lamp: InsteonAddress = RemovalExample.lamp
    let keypad: InsteonAddress = RemovalExample.keypad
    let network = DeviceNetwork(
      modem: modem,
      catalog: RemovalExample.catalog,
      snapshot: NetworkSnapshot(modemDatabase: RemovalExample.lampRecords + [RemovalExample.keypadRecord]),
      clock: clock
    )

    let forgotten: RegisteredDevice? = await network.forget(lamp)

    #expect(forgotten == nil)
    #expect(await network.snapshot().modemDatabase == [RemovalExample.keypadRecord])
    #expect(await network.knownDevices().isEmpty)
    #expect(await network.registry.device(keypad) == nil)

  }

  // MARK: - Other devices' records

  @Test(.timeLimit(.minutes(1))) func listsTheRecordsOtherDevicesHoldWithoutChangingThem() async throws {

    let modem = InMemoryModem()
    let lamp: InsteonAddress = RemovalExample.lamp
    let keypad: InsteonAddress = RemovalExample.keypad
    let sensor: InsteonAddress = RemovalExample.sensor
    let scene = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x03, address: lamp)
    let toModem = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 0x00, address: InsteonAddress(0x11, 0x22, 0x33))
    await modem.setDatabase([0x0FFF: toModem, 0x0FF7: scene], of: keypad)
    // The sensor rejects the modem, so its database can't be read.
    await modem.setUnlinked(sensor)
    let network: DeviceNetwork = await self.network(modem)
    let recorder = LinkingRecorder()

    let result: DeviceRemovalResult = try await network.linking.remove(lamp, scan: true, observer: recorder)

    let scan: LeftoverRecordScan? = result.leftoverRecords

    #expect(scan?.removedDevice == lamp)
    #expect(scan?.holders.map(\.address) == [keypad])
    #expect(scan?.holders.first?.device?.identity == RemovalExample.keypadIdentity)
    #expect(scan?.holders.first?.records.map(\.record) == [scene])
    #expect(scan?.holders.first?.records.map(\.address) == [0x0FF7])
    #expect(scan?.unread.map(\.address) == [sensor])
    // Nothing was written to any device's database.
    #expect(await modem.writes.isEmpty)
    #expect(await modem.databases[keypad]?[0x0FF7] == scene)
    #expect(await recorder.lines.suffix(5) == [
      "forgot \(lamp) known",
      "scanning \(keypad) for \(lamp)",
      "scanning \(sensor) for \(lamp)",
      "leftovers for \(lamp) [\"\(keypad) 1\"] unread [\"\(sensor)\"]",
      "factory reset \(lamp) steps 2"
    ])

  }

  @Test(.timeLimit(.minutes(1))) func doesntLookAtOtherDevicesUnlessAsked() async throws {

    let modem = InMemoryModem()
    let network: DeviceNetwork = await self.network(modem)

    let result: DeviceRemovalResult = try await network.linking.remove(RemovalExample.lamp, observer: LinkingRecorder())

    #expect(result.leftoverRecords == nil)
    #expect(await modem.databaseReads.isEmpty)

  }

  // MARK: - A device that doesn't answer

  @Test(.timeLimit(.minutes(1))) func fallsBackToTheSETButtonAndKeepsADeviceThatDoesntAnswer() async throws {

    let modem = InMemoryModem()
    let lamp: InsteonAddress = RemovalExample.lamp
    await modem.setUnanswering(lamp)
    let network: DeviceNetwork = await self.network(modem)
    let recorder = LinkingRecorder()

    do {

      _ = try await network.linking.remove(lamp, scan: true, observer: recorder)
      Issue.record("Expected the removal to fail.")

    } catch let error as RemoteUnlinkingError {

      #expect(error.device == lamp)
      #expect(error.deviceDescription?.profile?.model == "9301")

    }

    #expect(await recorder.lines == [
      "reading modem links \(lamp) to remove",
      "unlinking remotely \(lamp) responder 1",
      "remaining \(lamp) [\"controller 0\", \"responder 1\"]",
      "fallback: SET button unlinking \(lamp) steps 1"
    ])
    // The device still has links, so it isn't forgotten, and the modem keeps its records.
    #expect(await network.registry.device(lamp)?.identity == RemovalExample.lampIdentity)
    #expect(await modem.modemRecords == RemovalExample.lampRecords + [RemovalExample.keypadRecord])
    #expect(await modem.modemDeletions == 0)

  }

  @Test(.timeLimit(.minutes(1))) func deletesTheModemsRecordsOfADeviceThatsGoneWhenAsked() async throws {

    let modem = InMemoryModem()
    let lamp: InsteonAddress = RemovalExample.lamp
    await modem.setUnanswering(lamp)
    let network: DeviceNetwork = await self.network(modem)
    let recorder = LinkingRecorder()

    let result: DeviceRemovalResult = try await network.linking.remove(lamp, forceModemSide: true, observer: recorder)

    #expect(result.removed.links.isEmpty)
    #expect(result.remoteUnlinkingFailure != nil)
    #expect(result.deletedModemRecords == RemovalExample.lampRecords)
    #expect(result.remainingLinks == [])
    #expect(await modem.modemRecords == [RemovalExample.keypadRecord])
    #expect(await modem.modemDeletions == 2)
    #expect(await network.registry.device(lamp) == nil)
    // No SET button steps, and no links to unlink, for a device that's gone.
    #expect(await recorder.lines == [
      "reading modem links \(lamp) to remove",
      "unlinking remotely \(lamp) responder 1",
      "deleting modem records \(lamp) no answer",
      "modem records deleted \(lamp) 2",
      "forgot \(lamp) known",
      "factory reset \(lamp) steps 2"
    ])

  }

  // MARK: - Links left

  @Test(.timeLimit(.minutes(1))) func keepsADeviceTheModemStillHasLinksWith() async throws {

    let modem = InMemoryModem()
    let lamp: InsteonAddress = RemovalExample.lamp
    let network: DeviceNetwork = await self.network(modem)
    // The modem reports each link removed but keeps its records, so the links are left.
    await modem.setRecordsLinks(false)
    let recorder = LinkingRecorder()

    let result: DeviceRemovalResult = try await network.linking.remove(lamp, scan: true, observer: recorder)

    #expect(result.address == lamp)
    #expect(result.forgotten == nil)
    #expect(result.factoryReset == nil)
    #expect(result.leftoverRecords == nil)
    #expect(result.remainingLinks == [ModemLink(modemRole: .controller, group: 0x00), ModemLink(modemRole: .responder, group: 0x01)])

    guard case let .linksRemain(links)? = result.keptBecause else {

      Issue.record("Expected the device to be kept for its links.")

      return

    }

    #expect(links == result.remainingLinks)
    #expect(await network.registry.device(lamp)?.identity == RemovalExample.lampIdentity)
    #expect(await recorder.lines == [
      "reading modem links \(lamp) to remove",
      "unlinking remotely \(lamp) responder 1",
      "unlinking remotely \(lamp) controller 0",
      "unlinked all \(lamp) [\"responder 1\", \"controller 0\"]",
      "remaining \(lamp) [\"controller 0\", \"responder 1\"]",
      "kept \(lamp) links remain [\"controller 0\", \"responder 1\"]"
    ])

  }

  @Test(.timeLimit(.minutes(1))) func deletesTheLinksLeftWhenForcedThenForgets() async throws {

    let modem = InMemoryModem()
    let lamp: InsteonAddress = RemovalExample.lamp
    let network: DeviceNetwork = await self.network(modem)
    await modem.setRecordsLinks(false)
    let recorder = LinkingRecorder()

    let result: DeviceRemovalResult = try await network.linking.remove(lamp, forceModemSide: true, observer: recorder)

    #expect(result.keptBecause == nil)
    #expect(result.forgotten?.address == lamp)
    #expect(result.remoteUnlinkingFailure == nil)
    #expect(result.deletedModemRecords == RemovalExample.lampRecords)
    #expect(result.remainingLinks == [])
    #expect(await modem.modemRecords == [RemovalExample.keypadRecord])
    #expect(await recorder.lines == [
      "reading modem links \(lamp) to remove",
      "unlinking remotely \(lamp) responder 1",
      "unlinking remotely \(lamp) controller 0",
      "unlinked all \(lamp) [\"responder 1\", \"controller 0\"]",
      "deleting modem records \(lamp) links left 2",
      "modem records deleted \(lamp) 2",
      "forgot \(lamp) known",
      "factory reset \(lamp) steps 2"
    ])

  }

  @Test(.timeLimit(.minutes(1))) func keepsADeviceWhenTheModemRejectsADeletionMidway() async throws {

    let inner = InMemoryModem()
    let lamp: InsteonAddress = RemovalExample.lamp
    await inner.setUnanswering(lamp)
    // The modem accepts the first delete and rejects the second.
    let modem = RejectingModem(inner: inner, rejectingDeletion: 2)
    let times: FixedTimes = self.times
    await inner.setModemRecords(RemovalExample.lampRecords + [RemovalExample.keypadRecord])
    let network = DeviceNetwork(
      modem: modem,
      catalog: RemovalExample.catalog,
      snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [lamp: RemovalExample.lampIdentity])),
      clock: clock,
      now: { () -> Date in times.now() }
    )
    let recorder = LinkingRecorder()

    let result: DeviceRemovalResult = try await network.linking.remove(lamp, forceModemSide: true, observer: recorder)

    #expect(result.forgotten == nil)
    #expect(result.factoryReset == nil)
    #expect(result.deletedModemRecords.isEmpty)
    #expect(result.remainingLinks == [ModemLink(modemRole: .responder, group: 0x01)])
    #expect(await inner.modemRecords == [RemovalExample.lampRecords[1], RemovalExample.keypadRecord])
    #expect(await network.registry.device(lamp)?.identity == RemovalExample.lampIdentity)
    #expect(await recorder.lines == [
      "reading modem links \(lamp) to remove",
      "unlinking remotely \(lamp) responder 1",
      "deleting modem records \(lamp) no answer",
      "kept \(lamp) records not deleted"
    ])

    guard case let .modemRecordsNotDeleted(error)? = result.keptBecause else {

      Issue.record("Expected the device to be kept for the rejected deletion.")

      return

    }

    #expect((error as? ModemError) == .rejected(.manageAllLinkRecord))

  }

  @Test(.timeLimit(.minutes(1))) func saysWhenADeviceCantBeUnlinkedRemotelyBeforeDeletingItsRecords() async throws {

    let modem = InMemoryModem()
    let lamp: InsteonAddress = RemovalExample.lamp
    await modem.setEngine(.i1, of: lamp)
    let network: DeviceNetwork = await self.network(modem)
    let recorder = LinkingRecorder()

    _ = try await network.linking.remove(lamp, forceModemSide: true, observer: recorder)

    #expect(await recorder.lines.contains("deleting modem records \(lamp) unsupported"))

  }

  @Test func classifiesWhyTheModemsRecordsAreDeleted() {

    let lamp: InsteonAddress = RemovalExample.lamp

    func name(_ error: any Error) -> String {

      LinkingRecorder.deletionReason(DeviceLinkingCoordinator.deletionReason(for: error))

    }

    #expect(name(ModemError.deviceTimedOut(lamp)) == "no answer")
    #expect(name(LinkingError.linkingTimedOut) == "no answer")
    #expect(name(LinkingError.remoteLinkingUnsupported(lamp)) == "unsupported")
    #expect(name(LinkingError.databaseFull(lamp)) == "failed")

  }

  // MARK: - Cancellation

  @Test(.timeLimit(.minutes(1))) func keepsTheBookkeepingOfARemovalCanceledMidway() async throws {

    let modem = InMemoryModem()
    let lamp: InsteonAddress = RemovalExample.lamp
    let network: DeviceNetwork = await self.network(modem)
    let (reachedGroupZero, signal): (AsyncStream<Void>, AsyncStream<Void>.Continuation) = AsyncStream<Void>.makeStream()
    // The lamp's first link goes, then it stops answering before the modem's group 0.
    let recorder = LinkingRecorder(reacting: { (event: LinkingEvent) async -> Void in

      if case let .unlinkingRemotely(_, _, link) = event, link.modemRole == .controller {

        await modem.setSilent(lamp)
        signal.yield()

      }

    })
    let removal = Task { () async throws -> DeviceRemovalResult in

      try await network.linking.remove(lamp, scan: true, observer: recorder)

    }

    var events: AsyncStream<Void>.Iterator = reachedGroupZero.makeAsyncIterator()

    _ = await events.next()
    // The first link's wait is over, so the one sleeping is the modem's group 0.
    await clock.waitForSleeper(until: Linker.defaultRemoteLinkingTimeout)
    removal.cancel()

    await #expect(throws: CancellationError.self) {

      _ = try await removal.value

    }

    let snapshot: NetworkSnapshot = await network.snapshot()

    // The modem left its mode, the copies the unlink changed are forgotten, and the lamp,
    // which still has a link, stays known.
    #expect(await modemSteps(modem) == [.modem(.responder, 0x01), .modem(.delete, 0x00), .cancel])
    #expect(await network.cache.copies[lamp] == nil)
    #expect(snapshot.modemDatabase == nil)
    #expect(snapshot.registry.identities[lamp] == RemovalExample.lampIdentity)
    #expect(await recorder.lines.last == "unlinking remotely \(lamp) controller 0")

    // The turn was given back, so the next call runs.
    let next: DeviceUnlinkingAllResult = try await network.linking.unlinkAll(RemovalExample.keypad, observer: LinkingRecorder())

    #expect(next.removed.links == [ModemLink(modemRole: .controller, group: 0x00)])

  }

  // MARK: - Factory reset

  @Test(.timeLimit(.minutes(1))) func givesTheCatalogsResetStepsWithoutResetting() async throws {

    let modem = InMemoryModem()
    let lamp: InsteonAddress = RemovalExample.lamp
    let network: DeviceNetwork = await self.network(modem)
    let recorder = LinkingRecorder()

    let result: DeviceRemovalResult = try await network.linking.remove(lamp, observer: recorder)

    #expect(result.factoryReset?.address == lamp)
    #expect(result.factoryReset?.procedure?.steps == RemovalExample.resetSteps)
    #expect(result.factoryReset?.erases == [.links, .settings])
    #expect(result.factoryReset?.deviceDescription?.profile?.model == "9301")
    #expect(await recorder.lines.last == "factory reset \(lamp) steps 2")
    // The device was sent only what removing its links takes: no reset.
    let sentToLamp: [Command] = await modem.linkingSteps.compactMap { (step: InMemoryModem.LinkingStep) -> Command? in

      guard case let .device(device, command, _) = step, device == lamp else {

        return nil

      }

      return command

    }

    #expect(sentToLamp.map(\.command1) == [0x0D, 0x0A, 0x0D, 0x09])

  }

  @Test(.timeLimit(.minutes(1))) func givesNoResetStepsForADeviceTheCatalogDoesntHave() async throws {

    let modem = InMemoryModem()
    let stranger = InsteonAddress(0x3C, 0x4D, 0x09)
    await modem.setModemRecords([AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x00, address: stranger)])
    await modem.setRecordsLinks()
    let network = DeviceNetwork(modem: modem, catalog: RemovalExample.catalog, clock: clock)
    let recorder = LinkingRecorder()

    let result: DeviceRemovalResult = try await network.linking.remove(stranger, observer: recorder)

    #expect(result.factoryReset != nil)
    #expect(result.factoryReset?.procedure == nil)
    #expect(result.factoryReset?.erases.isEmpty == true)
    #expect(result.forgotten != nil)
    #expect(result.forgotten?.device == nil)
    #expect(await recorder.lines.suffix(2) == ["forgot \(stranger) unknown", "factory reset \(stranger) steps 0"])

  }

}

/// A modem that passes everything to an in-memory modem, but rejects one of the records it's
/// asked to delete with Manage ALL-Link Record, as a modem NAKs a delete it can't carry out.
struct RejectingModem: LinkingModem {

  let inner: InMemoryModem

  /// Which delete is rejected, counting from 1.
  let rejectingDeletion: Int

  private let deletions: DeletionCount = DeletionCount()

  init(inner: InMemoryModem, rejectingDeletion: Int) {

    self.inner = inner
    self.rejectingDeletion = rejectingDeletion

  }

  func send(_ command: SerialCommand) async throws {

    if case let .manageAllLinkRecord(action, _) = command, action == .deleteFirst {

      let count: Int = await deletions.next()

      if count == rejectingDeletion {

        throw ModemError.rejected(.manageAllLinkRecord)

      }

    }

    try await inner.send(command)

  }

  func modemInfo() async throws -> ModemInfo {

    try await inner.modemInfo()

  }

  func request(_ message: StandardMessage, timeout: Duration) async throws -> ReceivedMessage {

    try await inner.request(message, timeout: timeout)

  }

  func request(_ message: ExtendedMessage, timeout: Duration) async throws -> ReceivedMessage {

    try await inner.request(message, timeout: timeout)

  }

  func readAllLinkDatabase(of device: InsteonAddress, timeout: Duration) async throws -> [AllLinkRecordResponse] {

    try await inner.readAllLinkDatabase(of: device, timeout: timeout)

  }

  func readAllLinkRecord(of device: InsteonAddress, at address: UInt16, timeout: Duration) async throws -> AllLinkRecordResponse {

    try await inner.readAllLinkRecord(of: device, at: address, timeout: timeout)

  }

  func allLinkRecords(group: AllLinkGroupNumber, device: InsteonAddress) async throws -> [AllLinkRecord] {

    try await inner.allLinkRecords(group: group, device: device)

  }

  func allLinkRecords() async throws -> [AllLinkRecord] {

    try await inner.allLinkRecords()

  }

  func replies() async -> AsyncStream<ModemReply> {

    await inner.replies()

  }

}

/// How many deletes a ``RejectingModem`` was asked for.
actor DeletionCount {

  private var count: Int = 0

  /// Counts one more delete.
  ///
  /// - Returns: The count, from 1.
  func next() -> Int {

    count += 1

    return count

  }

}
