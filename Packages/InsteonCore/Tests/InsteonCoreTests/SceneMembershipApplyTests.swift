import Foundation
import Testing
import InsteonDeviceCatalog
import InsteonLinking
import InsteonLinkingTestSupport
import InsteonModem
import InsteonProtocol
import InsteonTestSupport
@testable import InsteonCore

/// Applying a scene membership plan: consent that names it, a re-read of both databases before anything is
/// written, each step written and read back in the coordinator's way, the first failure stopping the rest, and a
/// final read that compares both databases. Every device and product here is made up.
@Suite(.timeLimit(.minutes(1)))
struct SceneMembershipApplyTests {

  let modemAddress = InsteonAddress(0x11, 0x22, 0x33)
  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)
  let fan = InsteonAddress(0x4D, 0x5E, 0x6F)
  let stranger = InsteonAddress(0x7A, 0x8B, 0x9C)
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

  // MARK: Setup

  private func responder(group: UInt8, data: [UInt8] = [0xFF, 0x1F, 0x01]) -> AllLinkRecord {
    AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: AllLinkGroupNumber(rawValue: group), address: modemAddress, data1: data[0], data2: data[1], data3: data[2])
  }

  private func controller(group: UInt8, _ address: InsteonAddress) -> AllLinkRecord {
    AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: AllLinkGroupNumber(rawValue: group), address: address, data1: 0, data2: 0, data3: 0)
  }

  /// A modem with the lamp and the fan in scene 3, each device's database holding that one record and then its end.
  private func modem() async -> InMemoryModem {
    let modem = InMemoryModem()
    await modem.setModemRecords([controller(group: 3, lamp), controller(group: 3, fan)])
    await modem.setDatabase([0x0FFF: responder(group: 3)], of: lamp)
    await modem.setDatabase([0x0FFF: responder(group: 3)], of: fan)
    return modem
  }

  private func network(_ modem: any LinkingModem) -> DeviceNetwork {
    DeviceNetwork(modem: modem, catalog: Self.catalog, snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [lamp: identity, fan: identity, stranger: identity])), clock: TestClock())
  }

  private func plan(_ change: SceneMembershipChange, on network: DeviceNetwork) async throws -> SceneMembershipPlan {
    let backup = try await NetworkBackupReader.read(network: network, createdAt: Date(timeIntervalSince1970: 1_800_000_000))
    var registered: [InsteonAddress: RegisteredDevice] = [:]
    for address in [lamp, fan, stranger] {
      if let device = await network.registry.device(address) { registered[address] = device }
    }
    return SceneMembershipPlanner.plan(change, from: backup, devices: registered, modemLinkData: nil)
  }

  private func add(_ devices: InsteonAddress..., scene: UInt8 = 4) -> SceneMembershipChange {
    SceneMembershipChange(scene: scene, additions: devices.map { .init(device: $0, onLevel: 0xFF, rampRate: 0x1F) }, removals: [])!
  }

  private func remove(_ devices: InsteonAddress..., scene: UInt8 = 3) -> SceneMembershipChange {
    SceneMembershipChange(scene: scene, additions: [], removals: devices.map { .init(device: $0) })!
  }

  private func consent(_ plan: SceneMembershipPlan) -> DatabaseLinkConsent {
    DatabaseLinkConsent(writeLinkRecords: true, readFingerprint: plan.fingerprint)
  }

  private static func isAddingModemRecord(_ operation: InMemoryModem.Operation) -> Bool {
    if case let .send(command) = operation, case let .manageAllLinkRecord(action, _) = command { return action == .modifyFirstControllerOrAdd || action == .modifyFirstResponderOrAdd }
    return false
  }

  // MARK: Applying

  @Test func writesTheDevicesRecordsThenTheModemsAndReadsEachBack() async throws {
    let modem = await modem()
    let network = network(modem)
    let plan = try await plan(add(lamp), on: network)
    #expect(plan.steps.map(\.kind) == [.markEndOfDatabase, .addDeviceRecord, .addModemRecord])

    let result = try await network.linking.apply(plan, consent: consent(plan))

    #expect(result.isComplete)
    #expect(result.steps.map(\.outcome) == [.written, .written, .written])
    #expect(result.mismatches.isEmpty)
    #expect(result.isModemChecked)
    #expect(result.deviceChecks == [lamp: .checked])
    #expect(result.madeSteps == plan.steps)
    #expect(result.unmadeSteps.isEmpty)
    #expect(await modem.record(of: lamp, at: 0x0FF7) == responder(group: 4))
    #expect(await modem.record(of: lamp, at: 0x0FEF).flags.contains(.usedBefore) == false)
    #expect(await modem.modemRecords.contains(controller(group: 4, lamp)))
  }

  @Test func leavesEveryOtherRecordAsItWas() async throws {
    let modem = await modem()
    let network = network(modem)
    let plan = try await plan(add(lamp), on: network)

    _ = try await network.linking.apply(plan, consent: consent(plan))

    #expect(await modem.record(of: lamp, at: 0x0FFF) == responder(group: 3))
    #expect(await modem.record(of: fan, at: 0x0FFF) == responder(group: 3))
    #expect(await modem.record(of: fan, at: 0x0FF7).flags.contains(.usedBefore) == false)
    #expect(await modem.modemRecords.filter { $0.group != 4 } == [controller(group: 3, lamp), controller(group: 3, fan)])
  }

  @Test func makesTheExactCallsInOrderReadsThenEachSlotReadBeforeItsWriteAndReadBackAfter() async throws {
    let memory = await modem()
    let recording = RecordingModem(memory)
    let network = network(recording)
    let plan = try await plan(add(lamp), on: network)
    await recording.clear()
    let timeout = Modem.defaultExtendedRequestTimeout
    let newEnd = AllLinkRecord.endOfDatabase
    let written = responder(group: 4)

    _ = try await network.linking.apply(plan, consent: consent(plan))

    let calls = await recording.calls
    // Before any write: the modem's database, then the lamp's, are read to compare with the plan.
    #expect(Array(calls.prefix(2)) == [.readModemDatabase, .readAllLinkDatabase(lamp, timeout: timeout)])
    #expect(calls.contains(.extendedRequest(AllLinkDatabaseRequest.write(newEnd, address: 0x0FEF).message(to: lamp), timeout: timeout)))
    #expect(calls.contains(.extendedRequest(AllLinkDatabaseRequest.write(written, address: 0x0FF7).message(to: lamp), timeout: timeout)))
    // The end is marked below before the end's own slot is written, and each write is followed by a read of its slot.
    let writes = calls.enumerated().filter { if case .extendedRequest = $0.element { return true } else { return false } }.map(\.offset)
    #expect(writes.count == 2)
    #expect(calls[writes[0] + 1] == .readAllLinkRecord(lamp, address: 0x0FEF, timeout: timeout))
    #expect(calls[writes[1] + 1] == .readAllLinkRecord(lamp, address: 0x0FF7, timeout: timeout))
    #expect(writes[0] < writes[1])
    // After the writes both databases are read again to compare them. Then the network reads its copies again: the
    // modem's, and the lamp's through a status request for its delta.
    let comparisonStart = try #require(calls.indices.first { $0 > writes[1] && calls[$0] == .readAllLinkDatabase(lamp, timeout: timeout) })
    let comparing = Array(calls[comparisonStart...])
    #expect(Array(comparing.prefix(2)) == [.readAllLinkDatabase(lamp, timeout: timeout), .readModemDatabase])
    #expect(comparing.dropFirst(2).first == .readModemDatabase)
    // Nothing else is sent to a device before the network reads its copies again: no command, no level, and the fan and the stranger are never asked.
    #expect(calls[..<comparisonStart].allSatisfy { if case .standardRequest = $0 { return false } else { return true } })
    #expect(!calls.contains(.readAllLinkDatabase(fan, timeout: timeout)))
  }

  @Test func makesTheStepsOfEachDeviceInTheOrderOfThePlan() async throws {
    let modem = await modem()
    let network = network(modem)
    let plan = try await plan(add(lamp, fan), on: network)

    let result = try await network.linking.apply(plan, consent: consent(plan))

    #expect(result.isComplete)
    #expect(result.steps.map(\.step) == plan.steps)
    #expect(Set(result.deviceChecks.keys) == [lamp, fan])
    #expect(await modem.writes.map(\.device) == [lamp, lamp, fan, fan])
    #expect(await modem.record(of: fan, at: 0x0FF7) == responder(group: 4))
    #expect(await modem.modemRecords.contains(controller(group: 4, fan)))
  }

  @Test func removesTheModemsRecordFirstAndTheDevicesLast() async throws {
    let modem = await modem()
    // The lamp has records of the modem for other groups, so it never rejects the modem.
    await modem.setDatabase([0x0FFF: responder(group: 3), 0x0FF7: responder(group: 9)], of: lamp)
    let network = network(modem)
    let plan = try await plan(remove(lamp), on: network)
    #expect(plan.steps.map(\.kind) == [.removeModemRecord, .removeDeviceRecord])

    let result = try await network.linking.apply(plan, consent: consent(plan))

    #expect(result.isComplete)
    #expect(result.steps.map(\.outcome) == [.written, .written])
    #expect(await modem.modemRecords == [controller(group: 3, fan)])
    #expect(await modem.record(of: lamp, at: 0x0FFF).flags.contains(.inUse) == false)
    #expect(await modem.record(of: lamp, at: 0x0FF7) == responder(group: 9))
  }

  @Test func clearsADevicesRecordWithTheFlagsItHadAndOnlyTheInUseBit() async throws {
    let modem = await modem()
    await modem.setDatabase([0x0FFF: responder(group: 3), 0x0FF7: responder(group: 9)], of: lamp)
    let network = network(modem)
    let plan = try await plan(remove(lamp), on: network)

    _ = try await network.linking.apply(plan, consent: consent(plan))

    var expected = responder(group: 3)
    expected.flags.remove(.inUse)
    #expect(await modem.record(of: lamp, at: 0x0FFF) == expected)
  }

  @Test func saysAnI2CSDeviceThatRejectsTheModemOnceItsLastRecordIsGoneCannotBeReadBackAndIsStillComplete() async throws {
    let modem = await modem()
    let network = network(modem)
    let plan = try await plan(remove(lamp), on: network)
    #expect(plan.steps.last?.risks == [.rejectsModemOnceUnlinked])
    // The lamp keeps its only record of the modem until the last write, then rejects the modem.
    await modem.setUnlinked(lamp, afterWrites: 1)

    let result = try await network.linking.apply(plan, consent: consent(plan))

    #expect(result.steps.map(\.outcome) == [.written, .unverifiable])
    #expect(result.deviceChecks == [lamp: .rejectsModemAfterUnlinking])
    #expect(result.mismatches.isEmpty)
    #expect(result.isComplete)
  }

  @Test func afterwardsTheNetworksCopiesHoldWhatWasWritten() async throws {
    let modem = await modem()
    let network = network(modem)
    _ = try await network.allLinkDatabase(of: lamp)
    _ = try await network.modemDatabase()
    let held = await network.snapshot()
    let plan = try await plan(add(lamp), on: network)

    _ = try await network.linking.apply(plan, consent: consent(plan))
    let after = await network.snapshot()

    // The copies were forgotten and read again, so none shows the old records as current.
    #expect(held.devices[lamp]?.allLinkDatabase?.records.filter { $0.record.flags.contains(.inUse) }.count == 1)
    #expect(after.devices[lamp]?.allLinkDatabase?.records.filter { $0.record.flags.contains(.inUse) }.count == 2)
    #expect(after.modemDatabase?.count == (held.modemDatabase?.count ?? 0) + 1)
  }

  // MARK: The network's copies

  @Test func readsTheChangedDatabasesIntoTheNetworkAndSaysSo() async throws {
    let modem = await modem()
    let network = network(modem)
    let plan = try await plan(add(lamp), on: network)

    let result = try await network.linking.apply(plan, consent: consent(plan))

    #expect(result.cacheReload == SceneMembershipCacheReload(isModemReloaded: true))
    #expect(result.cacheReload?.isReloaded == true)
    #expect(result.changedDevices == [lamp])
    let snapshot = await network.snapshot()
    #expect(snapshot.modemDatabase != nil)
    #expect(snapshot.devices[lamp]?.allLinkDatabase != nil)
  }

  @Test func forgetsAndReadsAgainOnlyTheDevicesAStepWasTriedFor() async throws {
    let modem = await modem()
    let network = network(modem)
    _ = try await network.allLinkDatabase(of: fan)
    let plan = try await plan(add(lamp, fan), on: network)
    await modem.setForgetful(lamp)
    let fanReads = await modem.databaseReads[fan]

    let result = try await network.linking.apply(plan, consent: consent(plan))

    // The lamp's steps failed and the fan's were never reached, so the fan's copy is as it was and is not read again.
    #expect(result.changedDevices == [lamp])
    // The fan's database was read for the comparison before the writes and for the one after, and not again for the cache.
    let afterReads = await modem.databaseReads[fan]
    #expect(afterReads == (fanReads ?? 0) + 2)
    #expect(await network.snapshot().devices[fan]?.allLinkDatabase != nil)
  }

  @Test func listsADeviceThatRejectsTheModemOnceItsLastRecordIsGoneAsExpectedAndNotAsUnread() async throws {
    let modem = await modem()
    let network = network(modem)
    let plan = try await plan(remove(lamp), on: network)
    await modem.setUnlinked(lamp, afterWrites: 1)

    let result = try await network.linking.apply(plan, consent: consent(plan))

    #expect(result.cacheReload == SceneMembershipCacheReload(isModemReloaded: true, unreadDevices: [], expectedUnreadable: [lamp]))
    #expect(result.cacheReload?.isReloaded == true)
  }

  @Test func listsADeviceThatDoesNotAnswerTheReadAfterwardAsUnreadAndDoesNotMarkItAnswered() async throws {
    let memory = await modem()
    // The lamp has its half of the link to scene 4, so the plan has one step, the modem's, and no step asks the lamp.
    await memory.setDatabase([0x0FFF: responder(group: 3), 0x0FF7: responder(group: 4)], of: lamp)
    let damaging = DamagingModem(memory)
    let moment = Moment(Date(timeIntervalSince1970: 1_800_000_000))
    let network = DeviceNetwork(modem: damaging, catalog: Self.catalog, snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [lamp: identity, fan: identity, stranger: identity])), clock: TestClock(), now: { moment.value })
    let plan = try await plan(add(lamp), on: network)
    #expect(plan.steps.map(\.kind) == [.addModemRecord])
    let before = await network.snapshot().devices[lamp]?.lastSeen
    moment.value = Date(timeIntervalSince1970: 1_800_000_100)
    await damaging.setFailingDatabaseReads([ModemError.deviceTimedOut(lamp)], of: lamp)

    let result = try await network.linking.apply(plan, consent: consent(plan))

    #expect(result.isComplete)
    #expect(result.cacheReload == SceneMembershipCacheReload(isModemReloaded: true, unreadDevices: [lamp]))
    #expect(result.cacheReload?.isReloaded == false)
    // No step asked the lamp and it did not answer the read afterward, so it was not seen at the later time.
    #expect(await network.snapshot().devices[lamp]?.lastSeen == before)
  }

  @Test func carriesTheReloadInAnInterruptedResultAndNoneWhenNoStepWasTried() async throws {
    let modem = await modem()
    let network = network(modem)
    let plan = try await plan(add(lamp), on: network)
    await modem.setBeforeOperation { operation in
      if Self.isAddingModemRecord(operation) { throw ModemError.connectionClosed }
    }

    let interrupted = await #expect(throws: SceneMembershipInterrupted.self) { try await network.linking.apply(plan, consent: consent(plan)) }

    #expect(interrupted?.result.cacheReload?.isModemReloaded == true)
    #expect(interrupted?.result.changedDevices == [lamp])
  }

  // MARK: Consent

  @Test func writesAndReadsNothingWithoutConsentThatAgrees() async throws {
    let memory = await modem()
    let recording = RecordingModem(memory)
    let network = network(recording)
    let plan = try await plan(add(lamp), on: network)
    await recording.clear()

    let error = await #expect(throws: SceneMembershipRefusal.self) {
      try await network.linking.apply(plan, consent: DatabaseLinkConsent(writeLinkRecords: false, readFingerprint: plan.fingerprint))
    }

    #expect(error == .consentRequired)
    #expect(await recording.calls.isEmpty)
    #expect(await memory.writes.isEmpty)
  }

  @Test func writesAndReadsNothingWhenTheConsentNamesAnotherPlan() async throws {
    let memory = await modem()
    let recording = RecordingModem(memory)
    let network = network(recording)
    let plan = try await plan(add(lamp), on: network)
    let other = try await self.plan(add(fan), on: network)
    await recording.clear()

    for fingerprint in [other.fingerprint, "", "sha256:"] {
      let error = await #expect(throws: SceneMembershipRefusal.self) {
        try await network.linking.apply(plan, consent: DatabaseLinkConsent(writeLinkRecords: true, readFingerprint: fingerprint))
      }
      #expect(error == .consentMismatch)
    }

    #expect(await recording.calls.isEmpty)
  }

  @Test func refusesAPlanWithARefusalOrNoStepsWhateverTheConsent() async throws {
    let memory = await modem()
    let recording = RecordingModem(memory)
    let network = network(recording)
    // The stranger's database is not in the modem, so the plan names a device it cannot write.
    let refused = try await plan(add(stranger), on: network)
    let empty = try await plan(SceneMembershipChange(scene: 3, additions: [.init(device: lamp, onLevel: 0xFF, rampRate: 0x1F)], removals: [])!, on: network)
    #expect(!refused.refusals.isEmpty)
    #expect(empty.isEmpty)
    await recording.clear()

    for plan in [refused, empty] {
      let error = await #expect(throws: SceneMembershipRefusal.self) {
        try await network.linking.apply(plan, consent: DatabaseLinkConsent(writeLinkRecords: true, readFingerprint: plan.fingerprint))
      }
      #expect(error == .notApplicable)
    }

    #expect(await recording.calls.isEmpty)
  }

  // MARK: A database that changed

  @Test func writesNothingWhenTheModemsDatabaseChangedSinceThePlan() async throws {
    let modem = await modem()
    let network = network(modem)
    let plan = try await plan(add(lamp), on: network)
    await modem.setModemRecords(await modem.modemRecords + [controller(group: 9, stranger)])

    let error = await #expect(throws: SceneMembershipRefusal.self) {
      try await network.linking.apply(plan, consent: consent(plan))
    }

    #expect(error == .planStale(nil))
    #expect(await modem.writes.isEmpty)
    #expect(await modem.modemRecords.count == 3)
  }

  @Test func writesNothingWhenAModemRecordChangedItsDataSinceThePlan() async throws {
    let modem = await modem()
    let network = network(modem)
    let plan = try await plan(add(lamp), on: network)
    var changed = controller(group: 3, lamp)
    changed.data1 = 0x07
    await modem.setModemRecords([changed, controller(group: 3, fan)])

    let error = await #expect(throws: SceneMembershipRefusal.self) { try await network.linking.apply(plan, consent: consent(plan)) }

    #expect(error == .planStale(nil))
    #expect(await modem.writes.isEmpty)
  }

  @Test func writesNothingWhenADevicesDatabaseChangedSinceThePlan() async throws {
    let modem = await modem()
    let network = network(modem)
    let plan = try await plan(add(lamp, fan), on: network)
    // The fan's database changes after the lamp's is read, so even the lamp's steps are not made.
    await modem.setDatabase([0x0FFF: responder(group: 3), 0x0FF7: responder(group: 8)], of: fan)

    let error = await #expect(throws: SceneMembershipRefusal.self) { try await network.linking.apply(plan, consent: consent(plan)) }

    #expect(error == .planStale(fan))
    #expect(await modem.writes.isEmpty)
    #expect(await modem.record(of: fan, at: 0x0FF7) == responder(group: 8))
    #expect(await modem.modemRecords.count == 2)
  }

  @Test func writesNothingWhenADeviceNowReadsADamagedRecord() async throws {
    let modem = await modem()
    let network = network(modem)
    let plan = try await plan(add(lamp), on: network)
    await modem.setDamaged(true, record: 0x0FFF, of: lamp)

    let error = await #expect(throws: SceneMembershipRefusal.self) { try await network.linking.apply(plan, consent: consent(plan)) }

    #expect(error == .planStale(lamp))
    #expect(await modem.writes.isEmpty)
  }

  @Test func passesOnADeviceThatDoesNotAnswerTheReadBeforeAnythingIsWritten() async throws {
    let modem = await modem()
    let network = network(modem)
    let plan = try await plan(add(lamp), on: network)
    await modem.setUnlinked(lamp)

    await #expect(throws: ModemError.deviceRejected(lamp, .notLinked)) { try await network.linking.apply(plan, consent: consent(plan)) }

    #expect(await modem.writes.isEmpty)
    #expect(await modem.modemRecords.count == 2)
  }

  @Test func neverWritesOverARecordInUseEvenForAPlanThatSaysSo() async throws {
    let modem = await modem()
    let network = network(modem)
    var plan = try await plan(add(lamp), on: network)
    // A plan changed after it was made, so its record goes into the slot of scene 3's record.
    let index = try #require(plan.steps.firstIndex { $0.kind == .addDeviceRecord })
    plan.steps[index].record.memoryAddress = 0x0FFF

    let error = await #expect(throws: SceneMembershipRefusal.self) { try await network.linking.apply(plan, consent: consent(plan)) }

    #expect(error == .wouldOverwriteRecord(lamp))
    #expect(await modem.writes.isEmpty)
    #expect(await modem.record(of: lamp, at: 0x0FFF) == responder(group: 3))
  }

  @Test func stopsBeforeAWriteWhenTheSlotChangedSinceItWasRead() async throws {
    let modem = await modem()
    let network = network(modem)
    let plan = try await plan(add(lamp), on: network)
    // Something writes the end's slot between the plan's two writes to the lamp.
    let first = Flag()
    await modem.setBeforeOperation { [self] operation in
      if case .extendedRequest = operation, await first.raise() { await modem.setDatabase([0x0FFF: responder(group: 3), 0x0FF7: responder(group: 8)], of: lamp) }
    }

    let interrupted = await #expect(throws: SceneMembershipInterrupted.self) { try await network.linking.apply(plan, consent: consent(plan)) }

    let result = try #require(interrupted?.result)
    #expect(result.steps.map(\.outcome) == [.written, .notReached, .notReached])
    // Steps were written, so it is not the refusal that says nothing was: the cause says how many were made.
    #expect(interrupted?.cause as? SceneMembershipSlotChanged == SceneMembershipSlotChanged(device: lamp, made: 1, total: 3))
    #expect((interrupted?.cause as? SceneMembershipSlotChanged)?.description.contains("after 1 of 3 steps were made") == true)
    #expect((interrupted?.cause as? SceneMembershipSlotChanged)?.description.contains("Nothing was written") == false)
    // The record someone else wrote there is not written over.
    #expect(await modem.record(of: lamp, at: 0x0FF7) == responder(group: 8))
  }

  // MARK: Failures, a step at a time

  @Test func refusesAsStaleWhenTheSlotOfTheFirstStepChangedBeforeAnythingWasWritten() async throws {
    let memory = await modem()
    let freed = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0x22), group: 0, address: InsteonAddress(0, 0, 0), data1: 0, data2: 0, data3: 0)
    await memory.setDatabase([0x0FFF: responder(group: 3), 0x0FF7: freed], of: lamp)
    let damaging = DamagingModem(memory)
    let network = network(damaging)
    let plan = try await plan(add(lamp), on: network)
    #expect(plan.steps.first?.record.memoryAddress == 0x0FF7)
    // Someone writes the slot after the comparison read and before the step's own read of it.
    await damaging.setAfterRead { read in
      if case .database(lamp) = read { await memory.setDatabase([0x0FFF: responder(group: 3), 0x0FF7: responder(group: 8)], of: lamp) }
    }

    let error = await #expect(throws: SceneMembershipRefusal.self) { try await network.linking.apply(plan, consent: consent(plan)) }

    #expect(error == .planStale(lamp))
    #expect(await memory.writes.isEmpty)
  }

  @Test func refusesAsStaleWhenAnotherWriterExtendedTheDatabaseBeyondItsEndBeforeTheFirstStep() async throws {
    let memory = await modem()
    let damaging = DamagingModem(memory)
    let network = network(damaging)
    let plan = try await plan(add(lamp), on: network)
    #expect(plan.steps.first?.kind == .markEndOfDatabase)
    // After the comparison read, another writer puts a record in the slot below the end that the first step marks.
    await damaging.setAfterRead { read in
      if case .database(lamp) = read { await memory.setDatabase([0x0FFF: responder(group: 3), 0x0FEF: responder(group: 8)], of: lamp) }
    }

    let error = await #expect(throws: SceneMembershipRefusal.self) { try await network.linking.apply(plan, consent: consent(plan)) }

    #expect(error == .planStale(lamp))
    #expect(await memory.writes.isEmpty)
    #expect(await memory.record(of: lamp, at: 0x0FEF) == responder(group: 8))
  }

  @Test func stopsBeforeAWriteBeyondTheEndWhenAnotherWriterExtendedAnotherDevicesDatabaseMidRun() async throws {
    let memory = await modem()
    let damaging = DamagingModem(memory)
    let network = network(damaging)
    let plan = try await plan(add(lamp, fan), on: network)
    let reads = Counter()
    // After the lamp's steps, another writer puts a record below the fan's end, in the slot the fan's first step marks.
    await damaging.setAfterRead { read in
      if case .group = read, await reads.next() == 2 { await memory.setDatabase([0x0FFF: responder(group: 3), 0x0FEF: responder(group: 8)], of: fan) }
    }

    let interrupted = await #expect(throws: SceneMembershipInterrupted.self) { try await network.linking.apply(plan, consent: consent(plan)) }

    #expect(interrupted?.cause as? SceneMembershipSlotChanged == SceneMembershipSlotChanged(device: fan, made: 3, total: 6))
    #expect(await memory.writes.contains { $0.device == fan } == false)
    #expect(await memory.record(of: fan, at: 0x0FEF) == responder(group: 8))
  }

  @Test func stopsAtTheFirstStepThatReadsBackDifferentlyTwiceAndMakesNoStepAfterIt() async throws {
    let modem = await modem()
    let network = network(modem)
    let plan = try await plan(add(lamp, fan), on: network)
    await modem.setForgetful(lamp)

    let result = try await network.linking.apply(plan, consent: consent(plan))

    #expect(!result.isComplete)
    // Marking the end writes a record the slot already holds, so it reads back as written even from a device that keeps nothing.
    #expect(result.steps.map(\.outcome) == [.written, .notWritten, .notReached, .notReached, .notReached, .notReached])
    #expect(result.madeSteps.map(\.kind) == [.markEndOfDatabase])
    #expect(await modem.writes.map(\.address) == [0x0FEF, 0x0FF7, 0x0FF7])
    #expect(await modem.writes.contains { $0.device == fan } == false)
    #expect(await modem.modemRecords.contains(controller(group: 4, lamp)) == false)
  }

  @Test func writesAStepOnceMoreWhenItReadsBackDifferentlyOnceAndNeverAThirdTime() async throws {
    let modem = await modem()
    let network = network(modem)
    let plan = try await plan(add(lamp), on: network)
    // The lamp forgets its first two writes: the end's marker, which reads back as written anyway, and the record.
    await modem.setForgetful(lamp, writes: 2)

    let result = try await network.linking.apply(plan, consent: consent(plan))

    #expect(result.isComplete)
    #expect(result.steps.map(\.outcome) == [.written, .writtenOnRetry, .written])
    #expect(await modem.writes.count == 3)
  }

  @Test func countsAStepThatTookWithoutAnAcknowledgmentAsWrittenBecauseItReadsBack() async throws {
    let modem = await modem()
    let network = network(modem)
    let plan = try await plan(add(lamp), on: network)
    await modem.setUnacknowledged(lamp, writes: 2)

    let result = try await network.linking.apply(plan, consent: consent(plan))

    #expect(result.steps.map(\.outcome) == [.written, .written, .written])
    #expect(result.isComplete)
  }

  @Test func stopsWhenADeviceRejectsMidPlanAndSendsNothingToTheNextDevice() async throws {
    let modem = await modem()
    let network = network(modem)
    let plan = try await plan(add(lamp, fan), on: network)
    // The lamp stops answering after its second stored write, so the second step's write can't be read back.
    await modem.setUnlinked(lamp, afterWrites: 2)

    let result = try await network.linking.apply(plan, consent: consent(plan))

    #expect(!result.isComplete)
    #expect(result.steps.map(\.outcome).prefix(2) == [.written, .unanswered])
    #expect(result.steps.dropFirst(2).allSatisfy { $0.outcome == .notReached })
    #expect(await modem.writes.contains { $0.device == fan } == false)
    #expect(await modem.modemRecords.contains(controller(group: 4, fan)) == false)
    #expect(result.deviceChecks[lamp] == .unanswered)
  }

  @Test func leavesAStepNotReachedWhenTheDeviceDoesNotAnswerTheReadOfItsSlotBecauseNothingWasWrittenForIt() async throws {
    let memory = await modem()
    let damaging = DamagingModem(memory)
    let network = network(damaging)
    let plan = try await plan(add(lamp), on: network)
    await damaging.setFailingReads([ModemError.deviceTimedOut(lamp)], at: 0x0FF7, of: lamp)

    let interrupted = await #expect(throws: SceneMembershipInterrupted.self) { try await network.linking.apply(plan, consent: consent(plan)) }

    let result = try #require(interrupted?.result)
    #expect(result.steps.map(\.outcome) == [.written, .notReached, .notReached])
    #expect(interrupted?.cause as? ModemError == .deviceTimedOut(lamp))
    // The step before it was written, so the databases are read again and the result says what they hold.
    #expect(result.isModemChecked)
    #expect(result.deviceChecks == [lamp: .checked])
    #expect(await memory.writes.count == 1)
    #expect(await memory.modemRecords.contains(controller(group: 4, lamp)) == false)
  }

  @Test func refusesAsNotAnsweringWhenTheDeviceDoesNotAnswerTheReadOfTheFirstSlotBecauseNothingWasWritten() async throws {
    let memory = await modem()
    let freed = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0x22), group: 0, address: InsteonAddress(0, 0, 0), data1: 0, data2: 0, data3: 0)
    await memory.setDatabase([0x0FFF: responder(group: 3), 0x0FF7: freed], of: lamp)
    let damaging = DamagingModem(memory)
    let network = network(damaging)
    let plan = try await plan(add(lamp), on: network)
    await damaging.setFailingReads([ModemError.deviceTimedOut(lamp)], at: 0x0FF7, of: lamp)

    let error = await #expect(throws: SceneMembershipRefusal.self) { try await network.linking.apply(plan, consent: consent(plan)) }

    #expect(error == .deviceNotAnswering(lamp))
    #expect(await memory.writes.isEmpty)
    #expect(await memory.modemRecords.contains(controller(group: 4, lamp)) == false)
  }

  @Test func throwsWhatStoppedTheStepsWithEachStepsOutcomeWhenTheModemFails() async throws {
    let modem = await modem()
    let network = network(modem)
    let plan = try await plan(add(lamp), on: network)
    await modem.setBeforeOperation { operation in
      if Self.isAddingModemRecord(operation) { throw ModemError.connectionClosed }
    }

    let interrupted = await #expect(throws: SceneMembershipInterrupted.self) { try await network.linking.apply(plan, consent: consent(plan)) }

    let result = try #require(interrupted?.result)
    #expect(result.steps.map(\.outcome) == [.written, .written, .unanswered])
    #expect(result.madeSteps.map(\.kind) == [.markEndOfDatabase, .addDeviceRecord])
    #expect(result.unmadeSteps.map(\.kind) == [.addModemRecord])
    #expect(interrupted?.cause as? ModemError == .connectionClosed)
    // The lamp's records stay written: nothing is rolled back and nothing is repeated.
    #expect(await modem.record(of: lamp, at: 0x0FF7) == responder(group: 4))
    #expect(await modem.writes.count == 2)
    // The databases were read again, and they hold what the steps that were made left.
    #expect(result.mismatches.isEmpty)
    #expect(result.isModemChecked)
  }

  @Test func stopsBetweenStepsWhenCanceledAndStillComparesWhatWasWritten() async throws {
    let memory = await modem()
    let network = network(memory)
    let plan = try await plan(add(lamp), on: network)
    // The modem carries out what it is asked even when canceled, so the first write is made and then the task is canceled.
    await memory.setHonorsCancellation(false)
    let first = Flag()
    let box = TaskBox()
    await memory.setBeforeOperation { operation in
      if case .extendedRequest = operation, await first.raise() { await box.cancel() }
    }
    let running = Task { try await network.linking.apply(plan, consent: consent(plan)) }
    await box.set(running)

    let error = await #expect(throws: SceneMembershipInterrupted.self) { try await running.value }

    let result = try #require(error?.result)
    #expect(error?.cause is CancellationError)
    #expect(result.steps.map(\.outcome) == [.written, .notReached, .notReached])
    // A step was written, so both databases are read again to say what it left, even though the request was canceled.
    #expect(result.isModemChecked)
    #expect(result.deviceChecks == [lamp: .checked])
    #expect(result.mismatches.isEmpty)
    #expect(await memory.writes.count == 1)
    // The text says it was canceled, as an interrupted link does, and how many steps were made.
    #expect(error?.description.contains("canceled") == true)
    #expect(error?.description.contains("1 of 3 steps were made") == true)
  }

  @Test func stillReadsTheDatabasesAgainWhenTheRequestIsCanceledAfterTheLastStepAndReportsTheApplyAsMade() async throws {
    let memory = await modem()
    let damaging = DamagingModem(memory)
    let network = network(damaging)
    let plan = try await plan(add(lamp), on: network)
    let box = TaskBox()
    // The task is canceled once the last step, the modem's record, has read back, before the final read: the step
    // reads the modem's records for the device before it writes and after, and only the second read cancels.
    let reads = Flag()
    await damaging.setAfterRead { read in
      if case .group = read, await reads.raise() == false { await box.cancel() }
    }
    let running = Task { try await network.linking.apply(plan, consent: consent(plan)) }
    await box.set(running)

    let result = try await running.value

    #expect(result.steps.map(\.outcome) == [.written, .written, .written])
    #expect(result.isModemChecked)
    #expect(result.deviceChecks == [lamp: .checked])
    #expect(result.mismatches.isEmpty)
    #expect(result.isComplete)
  }

  @Test func saysTheApplyIsUnverifiedWhenEveryStepWasMadeAndADeviceDidNotAnswerTheFinalRead() async throws {
    let memory = await modem()
    let damaging = DamagingModem(memory)
    let network = network(damaging)
    let plan = try await plan(add(lamp), on: network)
    // The lamp answers the read before the writes and not the one after.
    await damaging.setFailingDatabaseReads([nil, ModemError.deviceTimedOut(lamp)], of: lamp)

    let result = try await network.linking.apply(plan, consent: consent(plan))

    #expect(result.steps.map(\.outcome) == [.written, .written, .written])
    #expect(result.mismatches.isEmpty)
    #expect(result.deviceChecks == [lamp: .unanswered])
    #expect(!result.isComplete)
    #expect(result.isUnverified)
  }

  @Test func doesNotCallAnApplyUnverifiedWhenAStepFailedOrARecordIsOtherThanExpected() async throws {
    let modem = await modem()
    let network = network(modem)
    let plan = try await plan(add(lamp), on: network)
    await modem.setBeforeOperation { [self] operation in
      if Self.isAddingModemRecord(operation) { await modem.setModemRecords(await modem.modemRecords + [controller(group: 9, stranger)]) }
    }

    let result = try await network.linking.apply(plan, consent: consent(plan))

    #expect(!result.mismatches.isEmpty)
    #expect(!result.isUnverified)
    #expect(!result.isComplete)
  }

  @Test func reportsARecordTheFinalReadFoundThatNoStepWrote() async throws {
    let modem = await modem()
    let network = network(modem)
    let plan = try await plan(add(lamp), on: network)
    // Another controller adds a record to the modem as the plan's last step is made.
    await modem.setBeforeOperation { [self] operation in
      if Self.isAddingModemRecord(operation) { await modem.setModemRecords(await modem.modemRecords + [controller(group: 9, stranger)]) }
    }

    let result = try await network.linking.apply(plan, consent: consent(plan))

    #expect(result.steps.map(\.outcome) == [.written, .written, .written])
    #expect(!result.isComplete)
    #expect(result.mismatches.count == 1)
    #expect(result.mismatches.first?.device == nil)
    #expect(result.mismatches.first?.mismatch.found?.address == stranger)
    #expect(result.mismatches.first?.mismatch.expected == nil)
  }

  @Test func keepsWhatTheFinalReadFoundWhenALaterReadFails() async throws {
    let modem = await modem()
    let network = network(modem)
    let plan = try await plan(add(lamp), on: network)
    let reads = Flag()
    await modem.setBeforeOperation { [self] operation in
      if Self.isAddingModemRecord(operation) { await modem.setDatabase([0x0FFF: responder(group: 7), 0x0FF7: responder(group: 4)], of: lamp) }
      // The first read of the modem's database is the one before the writes; the second is the final one.
      if case .readModemDatabase = operation, await reads.raise() == false { throw ModemError.connectionClosed }
    }

    let interrupted = await #expect(throws: SceneMembershipInterrupted.self) { try await network.linking.apply(plan, consent: consent(plan)) }

    let result = try #require(interrupted?.result)
    #expect(interrupted?.cause as? ModemError == .connectionClosed)
    // The lamp was read again and compared before the modem's read failed, and what it found is kept.
    #expect(result.deviceChecks == [lamp: .checked])
    #expect(result.mismatches.map(\.device) == [lamp])
    #expect(result.isModemChecked == false)
    #expect(result.steps.map(\.outcome) == [.written, .written, .written])
  }

  @Test func reportsADeviceRecordTheFinalReadFoundDifferentlyFromWhatWasWritten() async throws {
    let modem = await modem()
    let network = network(modem)
    let plan = try await plan(add(lamp), on: network)
    // The lamp's other record changes (someone presses its SET button) while the steps are made.
    await modem.setBeforeOperation { [self] operation in
      if Self.isAddingModemRecord(operation) { await modem.setDatabase([0x0FFF: responder(group: 7), 0x0FF7: responder(group: 4)], of: lamp) }
    }

    let result = try await network.linking.apply(plan, consent: consent(plan))

    #expect(!result.isComplete)
    #expect(result.mismatches.map(\.device) == [lamp])
    #expect(result.mismatches.first?.mismatch.memoryAddress == 0x0FFF)
  }
}

/// A moment a test sets.
private final class Moment: @unchecked Sendable {
  private let lock = NSLock()
  private var date: Date
  init(_ date: Date) { self.date = date }
  var value: Date {
    get { lock.withLock { date } }
    set { lock.withLock { date = newValue } }
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
  private var task: Task<SceneMembershipResult, any Error>?
  private var canceledEarly = false
  func set(_ task: Task<SceneMembershipResult, any Error>) {
    self.task = task
    if canceledEarly { task.cancel() }
  }
  func cancel() {
    canceledEarly = true
    task?.cancel()
  }
}
