import Foundation
import InsteonCore
import InsteonDeviceCatalog
import InsteonLinking
import InsteonLinkingTestSupport
import InsteonModem
import InsteonProtocol
import Testing
@testable import InsteonService

/// Applying a scene membership plan in the service: consent that names the plan, the admission gate, a re-read of
/// the databases, the writes through the coordinator, the cache and the `scene` event afterward, and a plan that is
/// used once. Every device and product is made up, and the modem is in memory.
@Suite(.timeLimit(.minutes(1)))
struct SceneMembershipApplyServiceTests {
  let modemAddress = InsteonAddress(0x11, 0x22, 0x33)
  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)
  let fan = InsteonAddress(0x4D, 0x5E, 0x6F)
  let keypad = InsteonAddress(0x7A, 0x8B, 0x9C)
  let identity = ReportedIdentity(category: 0x01, subcategory: 0x7D, firmwareVersion: 0x45)

  private static let catalog: DeviceCatalog = {
    let load = GroupType(
      name: "load",
      label: "Load",
      kind: .dimmer,
      linkData: GroupType.LinkData(responder: [
        LinkDataByte(position: 1, name: "onLevel", summary: "The on-level."),
        LinkDataByte(position: 2, name: "rampRate", summary: "The ramp rate."),
        LinkDataByte(position: 3, name: "button", summary: "The device's own group.", isPerGroup: true)
      ])
    )
    let profile = DeviceProfile(
      model: "9001",
      name: "Example Dimmer",
      identities: [DeviceIdentity(category: 0x01, subcategory: 0x7D)],
      engines: [DeviceEngine(engine: .i2cs, category: 0x01, subcategory: 0x7D)],
      commandSets: [CommandSetEntry(commandSet: "madeUpDimmer", category: 0x01, subcategory: 0x7D)],
      groups: [.init(number: 1, name: "Load", role: .responder, type: "load")]
    )
    return DeviceCatalog(profiles: [profile], commandSets: [CommandSet(id: "madeUpDimmer", name: "Made-Up Dimmer", summary: "A made-up command set.", groupTypes: [load])])
  }()

  private func responder(group: UInt8, data: [UInt8] = [0xFF, 0x1F, 0x01]) -> AllLinkRecord {
    AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: AllLinkGroupNumber(rawValue: group), address: modemAddress, data1: data[0], data2: data[1], data3: data[2])
  }

  private func controller(group: UInt8, _ address: InsteonAddress) -> AllLinkRecord {
    AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: AllLinkGroupNumber(rawValue: group), address: address, data1: 0, data2: 0, data3: 0)
  }

  /// A modem with the lamp and the fan in scene 3, and the keypad in none.
  private func modem() async -> InMemoryModem {
    let modem = InMemoryModem()
    await modem.setModemRecords([controller(group: 3, lamp), controller(group: 3, fan)])
    await modem.setDatabase([0x0FFF: responder(group: 3)], of: lamp)
    await modem.setDatabase([0x0FFF: responder(group: 3)], of: fan)
    return modem
  }

  private func service(_ modem: any LinkingModem, clock: WallClock, persistence: (any SnapshotPersisting)? = nil) -> InsteonService {
    let network = DeviceNetwork(modem: modem, catalog: Self.catalog, snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [lamp: identity, fan: identity, keypad: identity])), now: { clock.now })
    return InsteonService(network: network, persistence: persistence, now: { clock.now })
  }

  private static func isAddingModemRecord(_ operation: InMemoryModem.Operation) -> Bool {
    if case let .send(command) = operation, case let .manageAllLinkRecord(action, _) = command { return action == .modifyFirstControllerOrAdd || action == .modifyFirstResponderOrAdd }
    return false
  }

  private func change(_ scene: UInt8 = 4, add: [InsteonAddress] = [], remove: [InsteonAddress] = []) -> SceneMembershipChange {
    SceneMembershipChange(scene: scene, additions: add.map { SceneMembershipChange.Addition(device: $0, onLevel: 0xFF, rampRate: 0x1F) }, removals: remove.map { SceneMembershipChange.Removal(device: $0) })!
  }

  private func consent(_ plan: SceneMembershipPlan) -> DatabaseLinkConsent {
    DatabaseLinkConsent(writeLinkRecords: true, readFingerprint: plan.fingerprint)
  }

  /// A service that has read the databases, and a plan that adds the lamp to scene 4 (or `change`).
  private func planned(_ change: SceneMembershipChange? = nil, modem: InMemoryModem? = nil, clock: WallClock = WallClock("2026-11-27T10:00:00Z"), persistence: (any SnapshotPersisting)? = nil) async throws -> (service: InsteonService, modem: InMemoryModem, plan: SceneMembershipPlan, clock: WallClock) {
    let made = await self.modem()
    let modem = modem ?? made
    let service = service(modem, clock: clock, persistence: persistence)
    _ = try await service.refreshScenes()
    let receipt = try await service.planSceneMembership(change ?? self.change(add: [lamp]))
    return (service, modem, receipt.plan, clock)
  }

  // MARK: Applying

  @Test func writesEachStepOfThePlanInOrderAndReadsBothDatabasesBack() async throws {
    let (service, modem, plan, _) = try await planned()
    #expect(plan.steps.map(\.kind) == [.markEndOfDatabase, .addDeviceRecord, .addModemRecord])

    let application = try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan))

    #expect(application.isComplete)
    #expect(application.interruption == nil)
    #expect(application.result.steps.map(\.outcome) == [.written, .written, .written])
    #expect(application.result.mismatches.isEmpty)
    #expect(application.result.isModemChecked)
    #expect(application.result.deviceChecks == [lamp: .checked])
    #expect(await modem.record(of: lamp, at: 0x0FF7) == responder(group: 4))
    #expect(await modem.modemRecords.contains(controller(group: 4, lamp)))
    // The records of scene 3 stay as they were.
    #expect(await modem.record(of: lamp, at: 0x0FFF) == responder(group: 3))
    #expect(await modem.modemRecords.contains(controller(group: 3, lamp)))
    #expect(await modem.modemRecords.contains(controller(group: 3, fan)))
  }

  @Test func readsTheDatabasesFromTheDevicesBeforeItWritesAndWritesNothingElse() async throws {
    let (service, modem, plan, _) = try await planned()
    let lampReads = await modem.databaseReads[lamp] ?? 0
    let fanReads = await modem.databaseReads[fan]
    let keypadReads = await modem.databaseReads[keypad]
    let modemReads = await modem.modemDatabaseReads

    _ = try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan))

    let lampReadsAfter = await modem.databaseReads[lamp] ?? 0
    let modemReadsAfter = await modem.modemDatabaseReads
    #expect(lampReadsAfter > lampReads)
    #expect(modemReadsAfter > modemReads)
    // Only the lamp's database was written: the fan and the keypad are never asked.
    #expect(Set(await modem.writes.map(\.device)) == [lamp])
    #expect(await modem.databaseReads[fan] == fanReads)
    #expect(await modem.databaseReads[keypad] == keypadReads)
    #expect(await modem.groupCommands.isEmpty)
    #expect(await modem.linkingSteps.isEmpty)
  }

  @Test func listsTheNewMemberAtOnceBecauseTheServiceReadsTheDatabasesItChanged() async throws {
    let (service, modem, plan, _) = try await planned()

    _ = try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan))
    let reads = await modem.databaseReads[fan]
    let listing = await service.scenes()

    let scene = try #require(listing.scenes.first { $0.number == 4 })
    #expect(scene.members.map(\.address) == [lamp])
    #expect(scene.members.first?.data == [0xFF, 0x1F, 0x01])
    #expect(scene.halfLinks.isEmpty)
    // A device the plan didn't change is not read again.
    #expect(await modem.databaseReads[fan] == reads)
    #expect(listing.unreadable.isEmpty)
  }

  @Test func savesACheckpointAndReportsHowItWent() async throws {
    let store = RecordingStore()
    let (service, _, plan, _) = try await planned(persistence: NetworkSnapshotPersistence(store: store))

    let application = try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan))

    #expect(application.persistence == .saved)
    #expect(await store.saved?.modemDatabase?.contains(controller(group: 4, lamp)) == true)
  }

  @Test func removesAMemberModemRecordFirstAndTheDevicesLast() async throws {
    let (service, modem, plan, _) = try await planned(change(3, remove: [lamp]))
    #expect(plan.steps.map(\.kind) == [.removeModemRecord, .removeDeviceRecord])

    let application = try await service.applySceneMembership(scene: 3, planId: plan.id, consent: consent(plan))

    #expect(application.isComplete)
    #expect(await modem.modemRecords == [controller(group: 3, fan)])
    #expect(await modem.record(of: lamp, at: 0x0FFF).flags.contains(.inUse) == false)
  }

  // MARK: The event

  @Test func publishesASceneEventThatSaysTheMembersChanged() async throws {
    let (service, _, plan, clock) = try await planned()
    let events = await service.events()

    _ = try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan))

    var reader = events.makeAsyncIterator()
    guard case let .sceneChanged(changed)? = try await reader.next() else { Issue.record("expected a sceneChanged event"); return }
    #expect(changed.number == 4)
    #expect(changed.source == .api)
    #expect(changed.isComplete)
    #expect(changed.firedAt == clock.now)
  }

  @Test func publishesNothingWhenNothingWasWritten() async throws {
    let (service, modem, plan, _) = try await planned()
    let events = await service.events()
    await modem.setModemRecords(await modem.modemRecords + [controller(group: 9, keypad)])

    await #expect(throws: ServiceControlError.planStale) { try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan)) }

    // The next thing published is the scene's run, not a change.
    _ = try await service.runScene(SceneCommand(number: 3, action: .on))
    var reader = events.makeAsyncIterator()
    guard case .scene? = try await reader.next() else { Issue.record("expected the run's event first"); return }
  }

  // MARK: Consent

  @Test func writesNothingWithoutConsentThatAgrees() async throws {
    let (service, modem, plan, _) = try await planned()
    let before = (await modem.writes.count, await modem.databaseReads[lamp], await modem.modemDatabaseReads)

    await #expect(throws: ServiceControlError.consentRequired) { try await service.applySceneMembership(scene: 4, planId: plan.id, consent: DatabaseLinkConsent(writeLinkRecords: false, readFingerprint: plan.fingerprint)) }

    #expect(await modem.writes.count == before.0)
    #expect(await modem.databaseReads[lamp] == before.1)
    #expect(await modem.modemDatabaseReads == before.2)
  }

  @Test func writesNothingWhenTheConsentNamesAnotherPlanAndKeepsThePlanForTheRightConsent() async throws {
    let (service, modem, plan, _) = try await planned()
    let before = (await modem.writes.count, await modem.databaseReads[lamp])

    for fingerprint in ["sha256:" + String(repeating: "0", count: 64), "", plan.id + "x"] {
      await #expect(throws: ServiceControlError.consentMismatch) { try await service.applySceneMembership(scene: 4, planId: plan.id, consent: DatabaseLinkConsent(writeLinkRecords: true, readFingerprint: fingerprint)) }
    }

    #expect(await modem.writes.count == before.0)
    #expect(await modem.databaseReads[lamp] == before.1)
    // A consent that didn't name the plan doesn't spend it.
    let application = try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan))
    #expect(application.isComplete)
  }

  @Test func neverTakesTheConsentOfAnotherPlanThatTheServiceHolds() async throws {
    let (service, modem, plan, _) = try await planned()
    let other = try await service.planSceneMembership(change(5, add: [lamp])).plan
    #expect(other.fingerprint != plan.fingerprint)

    await #expect(throws: ServiceControlError.consentMismatch) { try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(other)) }
    #expect(await modem.writes.isEmpty)
  }

  // MARK: The plan

  @Test func refusesAPlanItNeverMadeAndOneForAnotherScene() async throws {
    let (service, modem, plan, _) = try await planned()
    let unknown = "sha256:" + String(repeating: "f", count: 64)

    await #expect(throws: ServiceControlError.unknownPlan) { try await service.applySceneMembership(scene: 4, planId: unknown, consent: DatabaseLinkConsent(writeLinkRecords: true, readFingerprint: unknown)) }
    await #expect(throws: ServiceControlError.unknownPlan) { try await service.applySceneMembership(scene: 9, planId: plan.id, consent: consent(plan)) }

    #expect(await modem.writes.isEmpty)
  }

  @Test func refusesAPlanOlderThanFiveMinutesByTheInjectedClock() async throws {
    let (service, modem, plan, clock) = try await planned()
    clock.advance(by: 299)
    let reads = await modem.modemDatabaseReads
    clock.advance(by: 1)

    await #expect(throws: ServiceControlError.planExpired) { try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan)) }

    #expect(await modem.writes.isEmpty)
    #expect(await modem.modemDatabaseReads == reads)
  }

  @Test func appliesAPlanOneSecondBeforeItExpires() async throws {
    let (service, _, plan, clock) = try await planned()
    clock.advance(by: 299)

    let application = try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan))

    #expect(application.isComplete)
  }

  @Test func refusesAPlanWithARefusalBecauseItCanNeverBeApplied() async throws {
    let modem = await modem()
    let service = service(modem, clock: WallClock("2026-11-27T10:00:00Z"))
    _ = try await service.refreshScenes()
    // The keypad holds no record of the modem and is an i2CS device, so it rejects the modem and the plan refuses it.
    let plan = try await service.planSceneMembership(change(add: [keypad])).plan
    #expect(!plan.refusals.isEmpty)

    await #expect(throws: ServiceControlError.planNotApplicable) { try await service.applySceneMembership(scene: 4, planId: plan.id, consent: DatabaseLinkConsent(writeLinkRecords: true, readFingerprint: plan.fingerprint)) }
    #expect(await modem.writes.isEmpty)
  }

  @Test func refusesAPlanThatWritesNothing() async throws {
    let modem = await modem()
    let service = service(modem, clock: WallClock("2026-11-27T10:00:00Z"))
    _ = try await service.refreshScenes()
    // The lamp is a member of scene 3 already, with this record.
    let plan = try await service.planSceneMembership(change(3, add: [lamp])).plan
    #expect(plan.isEmpty)

    await #expect(throws: ServiceControlError.planNotApplicable) { try await service.applySceneMembership(scene: 3, planId: plan.id, consent: DatabaseLinkConsent(writeLinkRecords: true, readFingerprint: plan.fingerprint)) }
  }

  @Test func usesAPlanOnce() async throws {
    let (service, modem, plan, _) = try await planned()
    _ = try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan))
    let writes = await modem.writes.count

    await #expect(throws: ServiceControlError.planAlreadyApplied) { try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan)) }

    #expect(await modem.writes.count == writes)
  }

  @Test func spendsAPlanThatWroteSomethingAndFailed() async throws {
    let (service, modem, plan, _) = try await planned()
    await modem.setForgetful(lamp)

    let application = try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan))

    #expect(!application.isComplete)
    await #expect(throws: ServiceControlError.planAlreadyApplied) { try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan)) }
  }

  // MARK: A database that changed

  @Test func writesNothingWhenTheModemsDatabaseChangedSinceThePlanAndSpendsThePlan() async throws {
    let (service, modem, plan, _) = try await planned()
    await modem.setModemRecords(await modem.modemRecords + [controller(group: 9, keypad)])

    await #expect(throws: ServiceControlError.planStale) { try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan)) }

    #expect(await modem.writes.isEmpty)
    #expect(await modem.modemRecords.count == 3)
    await #expect(throws: ServiceControlError.planAlreadyApplied) { try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan)) }
  }

  @Test func writesNothingWhenADevicesDatabaseChangedSinceThePlan() async throws {
    let (service, modem, plan, _) = try await planned()
    // Someone links the lamp to another group at the lamp's SET button, into the slot the plan would use.
    await modem.setDatabase([0x0FFF: responder(group: 3), 0x0FF7: responder(group: 8)], of: lamp)

    await #expect(throws: ServiceControlError.planStale) { try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan)) }

    #expect(await modem.writes.isEmpty)
    #expect(await modem.record(of: lamp, at: 0x0FF7) == responder(group: 8))
  }

  @Test func readsTheDevicesFromTheHardwareNotTheCacheSoAChangeTheCacheNeverSawIsCaught() async throws {
    let (service, modem, plan, _) = try await planned()
    // The cache still holds the databases as read, and the lamp changed after that.
    await modem.setDatabase([0x0FFF: responder(group: 3, data: [0x80, 0x1F, 0x01])], of: lamp)

    await #expect(throws: ServiceControlError.planStale) { try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan)) }

    #expect(await modem.writes.isEmpty)
  }

  // MARK: The gate

  @Test func refusesWhileAnotherOperationHoldsTheGateAndKeepsThePlan() async throws {
    let (service, modem, plan, _) = try await planned()
    let pause = Pause()
    await modem.setBeforeOperation { operation in
      if case .readModemDatabase = operation { await pause.wait() }
    }
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask { _ = try await service.refreshScenes() }
      await pause.waitUntilPaused()
      await #expect(throws: ServiceControlError.busy) { try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan)) }
      await pause.release()
      try await group.waitForAll()
    }
    await modem.setBeforeOperation(nil)
    #expect(await modem.writes.isEmpty)

    // Nothing was tried, so the plan is still open. The refresh read the same databases, so it applies.
    let application = try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan))
    #expect(application.isComplete)
  }

  @Test func judgesConsentBeforeTheGateSoARequestThatNeverAgreedIsNotToldTheServiceIsBusy() async throws {
    let (service, modem, plan, _) = try await planned()
    let pause = Pause()
    await modem.setBeforeOperation { operation in
      if case .readModemDatabase = operation { await pause.wait() }
    }
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask { _ = try await service.refreshScenes() }
      await pause.waitUntilPaused()
      await #expect(throws: ServiceControlError.consentRequired) { try await service.applySceneMembership(scene: 4, planId: plan.id, consent: DatabaseLinkConsent(writeLinkRecords: false, readFingerprint: plan.fingerprint)) }
      await #expect(throws: ServiceControlError.consentMismatch) { try await service.applySceneMembership(scene: 4, planId: plan.id, consent: DatabaseLinkConsent(writeLinkRecords: true, readFingerprint: "sha256:" + String(repeating: "0", count: 64))) }
      await #expect(throws: ServiceControlError.busy) { try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan)) }
      await pause.release()
      try await group.waitForAll()
    }
  }

  @Test func holdsTheGateWhileItWritesSoNothingElseRunsBesideIt() async throws {
    let (service, modem, plan, _) = try await planned()
    let pause = Pause()
    let hasPaused = Flag()
    await modem.setBeforeOperation { operation in
      if case .extendedRequest = operation, await hasPaused.raise() { await pause.wait() }
    }
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask { _ = try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan)) }
      await pause.waitUntilPaused()
      await #expect(throws: ServiceControlError.busy) { try await service.refreshScenes() }
      await #expect(throws: ServiceControlError.busy) { try await service.execute(ServiceCommand(address: lamp, action: .on)) }
      await #expect(throws: ServiceControlError.busy) { try await service.runScene(SceneCommand(number: 3, action: .on)) }
      await #expect(throws: ServiceControlError.busy) { try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan)) }
      await pause.release()
      try await group.waitForAll()
    }
    #expect(await modem.groupCommands.isEmpty)
    // The gate is free again.
    _ = try await service.refreshScenes()
  }

  @Test func refusesBeforeAnythingIsSentWhileTheModemIsAway() async throws {
    let modem = await modem()
    let away = InsteonService(
      network: DeviceNetwork(modem: modem, catalog: Self.catalog, snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [lamp: identity]))),
      opener: AwayOpener()
    )
    let id = "sha256:" + String(repeating: "a", count: 64)

    await #expect(throws: ServiceControlError.modemUnavailable(.connecting)) { try await away.applySceneMembership(scene: 4, planId: id, consent: DatabaseLinkConsent(writeLinkRecords: true, readFingerprint: id)) }
    #expect(await modem.writes.isEmpty)
    #expect(await modem.modemDatabaseReads == 0)
  }

  // MARK: Cancellation, a device that doesn't answer, and the cache

  /// A lamp whose database holds a free slot, so the plan writes into it with no end moved.
  private func freeSlotModem() async -> InMemoryModem {
    let modem = await modem()
    let freed = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0x22), group: 0, address: InsteonAddress(0, 0, 0), data1: 0, data2: 0, data3: 0)
    await modem.setDatabase([0x0FFF: responder(group: 3), 0x0FF7: freed], of: lamp)
    return modem
  }

  @Test func readsTheDatabasesItChangedIntoTheCacheEvenWhenTheRequestIsCanceledBetweenSteps() async throws {
    let memory = await modem()
    let damaging = DamagingModem(memory)
    let service = service(damaging, clock: WallClock("2026-11-27T10:00:00Z"))
    _ = try await service.refreshScenes()
    let plan = try await service.planSceneMembership(change(add: [lamp])).plan
    let box = TaskBox()
    let reads = Counter()
    // Canceled after the second read of a record of the lamp's: the plan's record has been written and read back.
    await damaging.setAfterRead { read in
      if case .record = read, await reads.next() == 3 { await box.cancel() }
    }
    let running = Task { try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan)) }
    await box.set(running)

    let application = try await running.value
    await damaging.setAfterRead(nil)

    #expect(application.interruption == .canceled)
    #expect(application.result.steps.map(\.outcome) == [.written, .written, .notReached])
    #expect(application.isCacheReloaded)
    // The listing shows the lamp's half of the link at once, so the cache was read again after the cancellation.
    let listing = await service.scenes()
    #expect(listing.looseHalfLinks.contains { $0.endpoint == .device(lamp) && $0.record.group == 4 } || listing.scenes.contains { $0.number == 4 && !$0.halfLinks.isEmpty })
    #expect(listing.unreadable.isEmpty)
  }

  @Test func writesNothingAndKeepsThePlanWhenTheDeviceDoesNotAnswerTheReadOfItsFirstSlot() async throws {
    let memory = await freeSlotModem()
    let damaging = DamagingModem(memory)
    let service = service(damaging, clock: WallClock("2026-11-27T10:00:00Z"))
    _ = try await service.refreshScenes()
    let plan = try await service.planSceneMembership(change(add: [lamp])).plan
    #expect(plan.steps.map(\.kind) == [.addDeviceRecord, .addModemRecord])
    let events = await service.events()
    await damaging.setFailingReads([ModemError.deviceTimedOut(lamp)], at: 0x0FF7, of: lamp)

    await #expect(throws: ServiceControlError.deviceNotAnswering) { try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan)) }

    #expect(await memory.writes.isEmpty)
    // Nothing was written, so the plan is still open and the same consent applies it.
    let application = try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan))
    #expect(application.isComplete)
    var reader = events.makeAsyncIterator()
    guard case let .sceneChanged(changed)? = try await reader.next() else { Issue.record("expected one sceneChanged event"); return }
    #expect(changed.isComplete)
  }

  @Test func writesNothingAndKeepsThePlanWhenTheRequestIsCanceledBeforeTheFirstStep() async throws {
    let memory = await modem()
    let damaging = DamagingModem(memory)
    let service = service(damaging, clock: WallClock("2026-11-27T10:00:00Z"))
    _ = try await service.refreshScenes()
    let plan = try await service.planSceneMembership(change(add: [lamp])).plan
    let box = TaskBox()
    // Canceled once the lamp's database has been read for the comparison, before the first step.
    await damaging.setAfterRead { read in
      if case .database = read { await box.cancel() }
    }
    let running = Task { try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan)) }
    await box.set(running)

    await #expect(throws: CancellationError.self) { try await running.value }
    await damaging.setAfterRead(nil)

    #expect(await memory.writes.isEmpty)
    let application = try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan))
    #expect(application.isComplete)
  }

  @Test func answersStaleAndSpendsThePlanWhenTheFirstSlotChangedAfterItWasReadAndNothingWasWritten() async throws {
    let memory = await freeSlotModem()
    let damaging = DamagingModem(memory)
    let service = service(damaging, clock: WallClock("2026-11-27T10:00:00Z"))
    _ = try await service.refreshScenes()
    let plan = try await service.planSceneMembership(change(add: [lamp])).plan
    let lampRecord = responder(group: 8)
    // The slot is written by someone else after the comparison read and before the step's own read of the slot.
    await damaging.setAfterRead { read in
      if case .database(lamp) = read { await memory.setDatabase([0x0FFF: responder(group: 3), 0x0FF7: lampRecord], of: lamp) }
    }

    await #expect(throws: ServiceControlError.planStale) { try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan)) }

    #expect(await memory.writes.isEmpty)
    #expect(await memory.record(of: lamp, at: 0x0FF7) == lampRecord)
    await #expect(throws: ServiceControlError.planAlreadyApplied) { try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan)) }
  }

  @Test func reportsThatTheCacheWasNotReloadedWhenTheModemFailsTheReadAfterTheWrites() async throws {
    let (service, modem, plan, _) = try await planned()
    let reads = Counter()
    // The modem's database is read before the writes, after them for the comparison, and then into the cache.
    await modem.setBeforeOperation { operation in
      if case .readModemDatabase = operation, await reads.next() == 3 { throw ModemError.connectionClosed }
    }

    let application = try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan))

    #expect(application.isComplete)
    #expect(application.isCacheReloaded == false)
  }

  @Test func listsADeviceThatRejectsTheModemAfterItsLastRecordIsRemovedAsExpectedAndStillSaysTheCacheWasReloaded() async throws {
    let (service, modem, plan, _) = try await planned(change(3, remove: [lamp]))
    #expect(plan.steps.last?.risks == [.rejectsModemOnceUnlinked])
    await modem.setUnlinked(lamp, afterWrites: 1)

    let application = try await service.applySceneMembership(scene: 3, planId: plan.id, consent: consent(plan))

    #expect(application.isComplete)
    #expect(application.isCacheReloaded)
    #expect(application.expectedUnreadable == [lamp])
  }

  @Test func readsTheDatabaseOfADeviceNamedOnlyByAModemStepIntoTheCache() async throws {
    let modem = await modem()
    // The lamp has its half of the link to scene 4 and the modem lacks the other half, so the plan has one modem step.
    await modem.setDatabase([0x0FFF: responder(group: 3), 0x0FF7: responder(group: 4)], of: lamp)
    let (service, _, plan, _) = try await planned(modem: modem)
    #expect(plan.steps.map(\.kind) == [.addModemRecord])
    let reads = await modem.databaseReads[lamp] ?? 0

    let application = try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan))

    #expect(application.isComplete)
    #expect(application.isCacheReloaded)
    #expect(await modem.databaseReads[lamp] ?? 0 > reads)
    let listing = await service.scenes()
    #expect(listing.scenes.first { $0.number == 4 }?.members.map(\.address) == [lamp])
  }

  // MARK: Failures, a step at a time

  /// A three-byte address as the service prints one, which no description of why steps stopped carries.
  private static func hasAddress(_ text: String) -> Bool {
    text.range(of: #"[0-9A-Fa-f]{2}\.[0-9A-Fa-f]{2}\.[0-9A-Fa-f]{2}"#, options: .regularExpression) != nil
  }

  @Test func saysHowManyStepsWereWrittenAndNeverThatNothingWasWhenASlotChangedMidRun() async throws {
    let (service, modem, plan, _) = try await planned(change(add: [lamp, fan]))
    #expect(plan.steps.count == 6)
    let added = Flag()
    // After the lamp's three steps, someone writes the fan's end slot, which the fan's steps are about to use.
    await modem.setBeforeOperation { [self] operation in
      if Self.isAddingModemRecord(operation), await added.raise() {
        await modem.setBeforeOperation(nil)
        let first = await modem.record(of: fan, at: 0x0FFF)
        await modem.setDatabase([0x0FFF: first, 0x0FF7: responder(group: 8)], of: fan)
      }
    }
    _ = modem

    let application = try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan))

    guard case let .failed(detail)? = application.interruption else { Issue.record("expected a failed interruption, got \(String(describing: application.interruption))"); return }
    #expect(application.outcome == .incomplete)
    #expect(application.result.madeSteps.count == 4)
    #expect(detail.contains("after 4 of 6 steps were made"))
    #expect(detail.contains("step 5"))
    #expect(!detail.contains("Nothing was written"))
    #expect(!Self.hasAddress(detail))
  }

  @Test func describesAModemFailureByTheStepAndWithoutAnAddress() async throws {
    let (service, modem, plan, _) = try await planned()
    await modem.setBeforeOperation { operation in
      if Self.isAddingModemRecord(operation) { throw ModemError.connectionClosed }
    }

    let application = try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan))

    guard case let .failed(detail)? = application.interruption else { Issue.record("expected a failed interruption"); return }
    #expect(detail.contains("Step 3"))
    #expect(detail.contains("2 of 3 steps were made"))
    #expect(!Self.hasAddress(detail))
  }

  @Test func describesADeviceThatStopsAnsweringByTheStepAndWithoutAnAddress() async throws {
    let memory = await modem()
    let damaging = DamagingModem(memory)
    let service = service(damaging, clock: WallClock("2026-11-27T10:00:00Z"))
    _ = try await service.refreshScenes()
    let plan = try await service.planSceneMembership(change(add: [lamp])).plan
    // The lamp answers the slot read before the first step and not the one before the second.
    await damaging.setFailingReads([ModemError.deviceTimedOut(lamp)], at: 0x0FF7, of: lamp)

    let application = try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan))

    guard case let .failed(detail)? = application.interruption else { Issue.record("expected a failed interruption"); return }
    #expect(detail.contains("1 of 3 steps were made"))
    #expect(detail.contains("Step 2"))
    #expect(!Self.hasAddress(detail))
  }

  @Test func callsAnApplyWhoseStepsWereAllMadeButWhoseFinalReadDidNotFinishUnverifiedAndNotIncomplete() async throws {
    let memory = await modem()
    let damaging = DamagingModem(memory)
    let service = service(damaging, clock: WallClock("2026-11-27T10:00:00Z"))
    _ = try await service.refreshScenes()
    let plan = try await service.planSceneMembership(change(add: [lamp])).plan
    let events = await service.events()
    // The lamp answers the read before the writes and not the final one.
    await damaging.setFailingDatabaseReads([nil, ModemError.deviceTimedOut(lamp)], of: lamp)

    let application = try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan))

    #expect(application.result.steps.map(\.outcome) == [.written, .written, .written])
    #expect(application.outcome == .appliedUnverified)
    #expect(!application.isComplete)
    var reader = events.makeAsyncIterator()
    guard case let .sceneChanged(changed)? = try await reader.next() else { Issue.record("expected a sceneChanged event"); return }
    #expect(!changed.isComplete)
  }

  @Test func callsAnApplyIncompleteWhenAStepWasNotMadeOrARecordIsOtherThanExpected() async throws {
    let (service, modem, plan, _) = try await planned()
    await modem.setForgetful(lamp)

    let application = try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan))

    #expect(application.outcome == .incomplete)
  }

  @Test func callsACompleteApplyApplied() async throws {
    let (service, _, plan, _) = try await planned()

    #expect(try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan)).outcome == .applied)
  }

  @Test func stopsAtTheFirstStepThatReadsBackDifferentlyTwiceAndSaysWhatWasAndWasNotWritten() async throws {
    let (service, modem, plan, _) = try await planned()
    // The lamp acknowledges its writes and keeps none.
    await modem.setForgetful(lamp)

    let application = try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan))

    #expect(!application.isComplete)
    // Marking the end writes a record the slot already holds, so it reads back as written even from a device that keeps nothing.
    #expect(application.result.steps.map(\.outcome) == [.written, .notWritten, .notReached])
    #expect(application.result.madeSteps.map(\.kind) == [.markEndOfDatabase])
    #expect(application.result.unmadeSteps.map(\.kind) == [.addDeviceRecord, .addModemRecord])
    // The modem's record, the plan's last step, was never added, and nothing is undone.
    #expect(await modem.modemRecords.contains(controller(group: 4, lamp)) == false)
    #expect(await modem.writes.map(\.address) == [0x0FEF, 0x0FF7, 0x0FF7])
  }

  @Test func writesAStepOnceMoreWhenItReadsBackDifferentlyOnceAndSaysSo() async throws {
    let (service, modem, plan, _) = try await planned()
    // The lamp forgets its first two writes: the end's marker, which reads back as written anyway, and the record.
    await modem.setForgetful(lamp, writes: 2)

    let application = try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan))

    #expect(application.isComplete)
    #expect(application.result.steps.map(\.outcome) == [.written, .writtenOnRetry, .written])
  }

  @Test func leavesTheStepsBeforeAFailureWrittenAndNeverRollsThemBack() async throws {
    let (service, modem, plan, _) = try await planned()
    // The modem fails the add of its record, the plan's last step, after the lamp's two records were written.
    await modem.setBeforeOperation { operation in
      if Self.isAddingModemRecord(operation) { throw ModemError.connectionClosed }
    }

    let application = try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan))

    #expect(!application.isComplete)
    #expect(application.result.steps.map(\.outcome) == [.written, .written, .unanswered])
    #expect(application.result.madeSteps.map(\.kind) == [.markEndOfDatabase, .addDeviceRecord])
    #expect(application.interruption != nil)
    #expect(await modem.record(of: lamp, at: 0x0FF7) == responder(group: 4))
    // Nothing was repeated or undone: the lamp's record stays, and the modem has none.
    #expect(await modem.writes.count == 2)
    #expect(await modem.modemRecords.contains(controller(group: 4, lamp)) == false)
  }

  @Test func stopsWhenADeviceStopsAnsweringMidPlanAndSendsNothingToTheNextDevice() async throws {
    let (service, modem, plan, _) = try await planned(change(add: [lamp, fan]))
    #expect(plan.steps.map(\.endpoint).contains(.device(fan)))
    // The lamp rejects every request after its second stored write, as a device does once it forgets the modem.
    await modem.setUnlinked(lamp, afterWrites: 2)

    let application = try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan))

    #expect(!application.isComplete)
    #expect(application.result.steps.map(\.outcome).prefix(2) == [.written, .unanswered])
    #expect(application.result.steps.dropFirst(2).allSatisfy { $0.outcome == .notReached })
    #expect(await modem.writes.contains { $0.device == fan } == false)
    #expect(await modem.modemRecords.contains(controller(group: 4, fan)) == false)
  }

  @Test func stopsBetweenStepsWhenTheRequestIsCanceledAndMakesNoStepAfter() async throws {
    let (service, modem, plan, _) = try await planned()
    let task = TaskBox()
    let first = Flag()
    // The modem carries out what it was asked even when canceled, so the first write is made, then the task is canceled.
    await modem.setHonorsCancellation(false)
    await modem.setBeforeOperation { operation in
      if case .extendedRequest = operation, await first.raise() { await task.cancel() }
    }
    let running = Task { try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan)) }
    await task.set(running)

    let application = try await running.value

    #expect(application.interruption == .canceled)
    #expect(application.result.steps.map(\.outcome) == [.written, .notReached, .notReached])
    #expect(await modem.writes.count == 1)
    #expect(await modem.modemRecords.contains(controller(group: 4, lamp)) == false)
  }

  @Test func reportsAnUnplannedRecordTheFinalReadFoundAndIsNotComplete() async throws {
    let (service, modem, plan, _) = try await planned()
    // Another controller adds a record to the modem as the plan's last step is made.
    await modem.setBeforeOperation { operation in
      if Self.isAddingModemRecord(operation) { await modem.setModemRecords(await modem.modemRecords + [controller(group: 9, keypad)]) }
    }

    let application = try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan))

    #expect(!application.isComplete)
    #expect(application.interruption == nil)
    #expect(application.result.steps.map(\.outcome) == [.written, .written, .written])
    #expect(application.result.mismatches.count == 1)
    #expect(application.result.mismatches.first?.device == nil)
    #expect(application.result.mismatches.first?.mismatch.found?.address == keypad)
  }

  @Test func publishesAChangeThatSaysTheScenesMembersMayHaveChangedWhenAStepFailedAfterWriting() async throws {
    let (service, modem, plan, _) = try await planned()
    let events = await service.events()
    await modem.setBeforeOperation { operation in
      if Self.isAddingModemRecord(operation) { throw ModemError.connectionClosed }
    }

    _ = try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan))

    var reader = events.makeAsyncIterator()
    guard case let .sceneChanged(changed)? = try await reader.next() else { Issue.record("expected a sceneChanged event"); return }
    #expect(changed.number == 4)
    #expect(changed.isComplete == false)
  }

  @Test func readsTheDatabasesItChangedIntoTheCacheEvenWhenAStepFailed() async throws {
    let (service, modem, plan, _) = try await planned()
    await modem.setBeforeOperation { operation in
      if Self.isAddingModemRecord(operation) { throw ModemError.connectionClosed }
    }

    _ = try await service.applySceneMembership(scene: 4, planId: plan.id, consent: consent(plan))
    await modem.setBeforeOperation(nil)

    // The lamp holds its half of the link and the modem lacks the other, which the listing says as a half link.
    let listing = await service.scenes()
    #expect(listing.looseHalfLinks.contains { $0.endpoint == .device(lamp) && $0.record.group == 4 } || listing.scenes.contains { $0.number == 4 && !$0.halfLinks.isEmpty })
  }
}

/// Counts calls, from 1.
private actor Counter {
  private var count = 0
  func next() -> Int {
    count += 1
    return count
  }
}

/// A flag that is raised once: the first caller gets `true`.
private actor Flag {
  private var raised = false
  func raise() -> Bool {
    defer { raised = true }
    return !raised
  }
}

/// Holds the task a hook cancels, since the task is made after the hook.
private actor TaskBox {
  private var task: Task<SceneMembershipApplication, any Error>?
  private var canceledEarly = false
  func set(_ task: Task<SceneMembershipApplication, any Error>) {
    self.task = task
    if canceledEarly { task.cancel() }
  }
  func cancel() {
    canceledEarly = true
    task?.cancel()
  }
}

/// An opener that is never asked, since the service in the test isn't run.
private struct AwayOpener: ServedNetworkOpening {
  func withServedNetwork(snapshot: NetworkSnapshot, onPollSucceeded: @escaping @Sendable () async -> Void, _ body: @escaping @Sendable (any ServedNetwork) async throws -> Void) async throws { throw ModemError.connectionClosed }
}
