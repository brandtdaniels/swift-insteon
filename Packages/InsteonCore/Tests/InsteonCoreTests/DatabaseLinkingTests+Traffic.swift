import Testing
@testable import InsteonCore
import InsteonLinking
import InsteonLinkingTestSupport
import InsteonModem
import InsteonProtocol

/// The exact calls ``DeviceLinkingCoordinator/apply(_:)`` makes, in order.
extension DatabaseLinkingTests {

  var timeout: Duration { Modem.defaultExtendedRequestTimeout }

  func write(_ record: AllLinkRecord, at address: UInt16) -> RecordingModem.Call {

    .extendedRequest(AllLinkDatabaseRequest.write(record, address: address).message(to: device), timeout: timeout)

  }

  func read(at address: UInt16) -> RecordingModem.Call {

    .readAllLinkRecord(device, address: address, timeout: timeout)

  }

  /// The reads that check the modem and both databases against the plan before any step.
  var checksThePlan: [RecordingModem.Call] {

    [.readAllLinkDatabase(device, timeout: timeout), .modemInfo, .readModemDatabase]

  }

  /// The reads that compare both databases with what the steps should have left.
  var verifies: [RecordingModem.Call] {

    [.readAllLinkDatabase(device, timeout: timeout), .readModemDatabase]

  }

  /// Plans with `plan` on a recording modem, then applies the plan, and returns the calls the
  /// apply made.
  func applyCalls(
    _ memory: InMemoryModem,
    plan: (DeviceLinkingCoordinator) async throws -> DatabaseLinkPlan,
    beforeApplying: (DamagingModem) async -> Void = { _ in }
  ) async throws -> [RecordingModem.Call] {

    try await applying(memory, plan: plan, beforeApplying: beforeApplying).calls

  }

  /// Plans with `plan` on a recording modem, then applies the plan, and returns the calls the
  /// apply made and its result. `beforeApplying` runs after the plan, and can set the
  /// single-record reads that arrive damaged.
  func applying(
    _ memory: InMemoryModem,
    plan: (DeviceLinkingCoordinator) async throws -> DatabaseLinkPlan,
    beforeApplying: (DamagingModem) async -> Void = { _ in }
  ) async throws -> (calls: [RecordingModem.Call], result: DatabaseLinkResult) {

    let damaging = DamagingModem(memory)
    let modem = RecordingModem(damaging)
    let linking: DeviceLinkingCoordinator = DeviceNetwork(modem: modem, catalog: DatabaseLinkingExample.catalog, clock: clock).linking
    let planned: DatabaseLinkPlan = try await plan(linking)

    await beforeApplying(damaging)
    await modem.clear()

    let result: DatabaseLinkResult = try await linking.apply(planned)

    return (await modem.calls, result)

  }

  @Test func applyingALinkReadsEachSlotBeforeWritingItAndEachRecordBack() async throws {

    let added: AllLinkRecord = responder(0x00, naming: modemAddress, data: [0xFF, 0x1C, 0x01])
    let calls: [RecordingModem.Call] = try await applyCalls(await partlyLinked()) { try await $0.planDatabaseLink(device) }

    #expect(calls == checksThePlan + [
      read(at: 0x0FF7),
      write(added, at: 0x0FF7),
      read(at: 0x0FF7),
      .readModemRecords(group: 0x00, device: device),
      .send(.manageAllLinkRecord(action: .modifyFirstControllerOrAdd, record: controller(0x00, naming: device))),
      .readModemRecords(group: 0x00, device: device),
      .readModemRecords(group: 0x01, device: device),
      .send(.manageAllLinkRecord(action: .modifyFirstResponderOrAdd, record: responder(0x01, naming: device))),
      .readModemRecords(group: 0x01, device: device)
    ] + verifies)

  }

  @Test func applyingALinkAtTheEndWritesTheNewEndFirst() async throws {

    let memory: InMemoryModem = await modem()

    await memory.setDatabase([0x0FFF: controller(0x01, naming: modemAddress)], of: device)
    await memory.setModemRecords([controller(0x00, naming: device), responder(0x01, naming: device)])

    let added: AllLinkRecord = responder(0x00, naming: modemAddress, data: [0xFF, 0x1C, 0x01])
    let calls: [RecordingModem.Call] = try await applyCalls(memory) { try await $0.planDatabaseLink(device) }

    // The slot below the end was never read, so there's nothing to check it against.
    #expect(calls == checksThePlan + [
      write(end, at: 0x0FEF),
      read(at: 0x0FEF),
      read(at: 0x0FF7),
      write(added, at: 0x0FF7),
      read(at: 0x0FF7)
    ] + verifies)

  }

  @Test func applyingWritesARecordOnceMoreWhenItReadsBackDifferently() async throws {

    let memory: InMemoryModem = await partlyLinked()

    await memory.setModemRecords([controller(0x00, naming: device), responder(0x01, naming: device)])

    let added: AllLinkRecord = responder(0x00, naming: modemAddress, data: [0xFF, 0x1C, 0x01])
    let calls: [RecordingModem.Call] = try await applyCalls(memory) {

      try await $0.planDatabaseLink(device)

    } beforeApplying: { _ in

      await memory.setForgetful(device, writes: 1)

    }

    #expect(calls == checksThePlan + [
      read(at: 0x0FF7),
      write(added, at: 0x0FF7),
      read(at: 0x0FF7),
      write(added, at: 0x0FF7),
      read(at: 0x0FF7)
    ] + verifies)

  }

  @Test func applyingReadsADamagedSlotOnceMoreThenStops() async throws {

    let memory: InMemoryModem = await partlyLinked()
    let device: InsteonAddress = self.device

    let (calls, result): ([RecordingModem.Call], DatabaseLinkResult) = try await applying(memory) {

      try await $0.planDatabaseLink(device)

    } beforeApplying: { _ in

      // The slot arrives damaged once both databases are checked against the plan.
      await memory.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

        if case .readModemDatabase = operation {

          await memory.setDamaged(true, record: 0x0FF7, of: device)

        }

      }

    }

    #expect(calls == checksThePlan + [
      read(at: 0x0FF7),
      read(at: 0x0FF7)
    ] + verifies)
    #expect(result.steps.map { $0.outcome } == [.unanswered, .notReached, .notReached])
    #expect(!result.isComplete)

  }

  @Test func applyingReadsADamagedSlotOfAnI2CSDeviceOnceMoreThenWrites() async throws {

    let memory: InMemoryModem = await partlyLinked()
    let device: InsteonAddress = self.device

    await memory.setModemRecords([controller(0x00, naming: device), responder(0x01, naming: device)])

    let added: AllLinkRecord = responder(0x00, naming: modemAddress, data: [0xFF, 0x1C, 0x01])
    let (calls, result): ([RecordingModem.Call], DatabaseLinkResult) = try await applying(memory) {

      try await $0.planDatabaseLink(device)

    } beforeApplying: { (damaging: DamagingModem) async -> Void in

      // The slot check and the read-back each arrive damaged, then intact.
      await damaging.setDamagedReads([true, false, true, false], at: 0x0FF7, of: device)

    }

    #expect(calls == checksThePlan + [
      read(at: 0x0FF7),
      read(at: 0x0FF7),
      write(added, at: 0x0FF7),
      read(at: 0x0FF7),
      read(at: 0x0FF7)
    ] + verifies)
    #expect(result.steps.map { $0.outcome } == [.written])

  }

  @Test func applyingReadsADamagedSlotOfAnI2DeviceOnce() async throws {

    let memory: InMemoryModem = await modem(identity: DatabaseLinkingExample.older, engine: .i2)
    let device: InsteonAddress = self.device

    await memory.setDatabase([
      0x0FFF: controller(0x01, naming: modemAddress),
      0x0FF7: deleted(responder(0x09, naming: DatabaseLinkingExample.lamp))
    ], of: device)
    await memory.setModemRecords([controller(0x00, naming: device), responder(0x01, naming: device)])

    let added: AllLinkRecord = responder(0x00, naming: modemAddress, data: [0xFF, 0x1C, 0x01])
    let (calls, result): ([RecordingModem.Call], DatabaseLinkResult) = try await applying(memory) {

      try await $0.planDatabaseLink(device)

    } beforeApplying: { (damaging: DamagingModem) async -> Void in

      // The slot check and the read-back each arrive damaged; a read after either would
      // arrive intact.
      await damaging.setDamagedReads([true, true, false], at: 0x0FF7, of: device)

    }

    #expect(calls == checksThePlan + [
      read(at: 0x0FF7),
      write(added, at: 0x0FF7),
      read(at: 0x0FF7)
    ] + verifies)
    #expect(result.steps.map { $0.outcome } == [.written])

  }

  @Test func applyingAnUnlinkDeletesTheModemsRecordsThenClearsTheDevicesSlots() async throws {

    let calls: [RecordingModem.Call] = try await applyCalls(await linked()) { try await $0.planDatabaseUnlink(device) }
    let key: AllLinkRecord = AllLinkRecord(flags: [], group: 0x01, address: device)

    #expect(calls == checksThePlan + [
      .readModemRecords(group: 0x01, device: device),
      .send(.manageAllLinkRecord(action: .deleteFirst, record: key)),
      .readModemRecords(group: 0x01, device: device),
      .readModemRecords(group: 0x01, device: device),
      .send(.manageAllLinkRecord(action: .deleteFirst, record: key)),
      .readModemRecords(group: 0x01, device: device),
      read(at: 0x0FFF),
      write(deleted(controller(0x01, naming: modemAddress)), at: 0x0FFF),
      read(at: 0x0FFF),
      read(at: 0x0FF7),
      write(deleted(responder(0x00, naming: modemAddress, data: [0xFF, 0x1C, 0x01])), at: 0x0FF7),
      read(at: 0x0FF7)
    ] + verifies)

  }

}
