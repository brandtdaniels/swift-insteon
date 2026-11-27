import Foundation
import InsteonCore
import InsteonDeviceCatalog
import InsteonLinkingTestSupport
import InsteonModem
import InsteonProtocol
import Testing
@testable import InsteonService

/// Planning a scene's members in the service: from the cached ALL-Link databases and the catalog,
/// sending nothing, and keeping the plan in memory for five minutes on the injected clock.
@Suite(.timeLimit(.minutes(1)))
struct SceneMembershipPlanServiceTests {
  let modemAddress = InsteonAddress(0x11, 0x22, 0x33)
  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)
  let keypad = InsteonAddress(0x4D, 0x5E, 0x6F)
  let identity = ReportedIdentity(category: 0x01, subcategory: 0x7D, firmwareVersion: 0x45)

  /// A made-up catalog: one dimmer product with an on-level, a ramp rate and its own group in its responder record.
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

  /// A modem with the lamp in scene 3, and the keypad controlling group 7 that the modem responds to.
  private func modem() async -> InMemoryModem {
    let modem = InMemoryModem()
    await modem.setModemRecords([
      AllLinkRecord(flags: [.inUse, .controller], group: 3, address: lamp, data1: 0, data2: 0, data3: 0),
      AllLinkRecord(flags: [.inUse], group: 7, address: keypad, data1: 0, data2: 0, data3: 0)
    ])
    await modem.setDatabase([0x0FFF: responder(group: 3)], of: lamp)
    await modem.setDatabase([0x0FFF: AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 7, address: modemAddress, data1: 0, data2: 0, data3: 0)], of: keypad)
    return modem
  }

  private func service(_ modem: InMemoryModem, clock: WallClock, catalog: DeviceCatalog? = Self.catalog) -> InsteonService {
    let network = DeviceNetwork(modem: modem, catalog: catalog, snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [lamp: identity, keypad: identity])), now: { clock.now })
    return InsteonService(network: network, now: { clock.now })
  }

  private func change(_ scene: UInt8 = 4, add: [SceneMembershipChange.Addition] = [], remove: [InsteonAddress] = []) -> SceneMembershipChange {
    SceneMembershipChange(scene: scene, additions: add, removals: remove)!
  }

  @Test func plansFromTheCachedDatabasesAndTheCatalogAndSendsNothing() async throws {
    let clock = WallClock("2026-11-27T10:00:00Z")
    let modem = await modem()
    let service = service(modem, clock: clock)
    _ = try await service.refreshScenes()
    let reads = (await modem.modemDatabaseReads, await modem.databaseReads[lamp])
    let sent = await modem.writes.count

    let receipt = try await service.planSceneMembership(change(add: [.init(device: lamp, onLevel: 0xFF, rampRate: 0x1F)]))

    #expect(receipt.plan.isApplicable)
    // The lamp's cached database has no free slot, so the end moves down one slot first.
    #expect(receipt.plan.steps.map(\.kind) == [.markEndOfDatabase, .addDeviceRecord, .addModemRecord])
    #expect(receipt.plan.steps[1].record.data == [0xFF, 0x1F, 0x01])
    #expect(receipt.plan.steps[1].record.group == 4)
    #expect(await modem.modemDatabaseReads == reads.0)
    #expect(await modem.databaseReads[lamp] == reads.1)
    #expect(await modem.writes.count == sent)
    #expect(await modem.linkingSteps.isEmpty)
    #expect(await modem.modemDeletions == 0)
    #expect(await modem.extendedRequests.isEmpty)
  }

  @Test func refusesADeviceWhoseDatabaseWasNeverReadAndSaysToRefresh() async throws {
    let clock = WallClock("2026-11-27T10:00:00Z")
    let service = service(await modem(), clock: clock)

    let receipt = try await service.planSceneMembership(change(add: [.init(device: lamp, onLevel: nil, rampRate: nil)]))

    #expect(receipt.plan.refusals.map(\.code).contains(.databaseNotCached))
    #expect(!receipt.plan.isApplicable)
    #expect(await service.openSceneMembershipPlan(receipt.plan.id) == nil)
  }

  @Test func expiresThePlanFiveMinutesAfterItWasMadeByTheInjectedClock() async throws {
    let clock = WallClock("2026-11-27T10:00:00Z")
    let service = service(await modem(), clock: clock)
    _ = try await service.refreshScenes()

    let receipt = try await service.planSceneMembership(change(add: [.init(device: lamp, onLevel: 0xFF, rampRate: 0x1F)]))

    #expect(receipt.expiresAt == clock.now.addingTimeInterval(300))
    #expect(await service.openSceneMembershipPlan(receipt.plan.id) == receipt.plan)
    clock.advance(by: 299)
    #expect(await service.openSceneMembershipPlan(receipt.plan.id) == receipt.plan)
    clock.advance(by: 1)
    #expect(await service.openSceneMembershipPlan(receipt.plan.id) == nil)
  }

  @Test func keepsNoPlanThereIsNothingToApply() async throws {
    let clock = WallClock("2026-11-27T10:00:00Z")
    let service = service(await modem(), clock: clock)
    _ = try await service.refreshScenes()

    // The lamp is in scene 3 already, with this record.
    let receipt = try await service.planSceneMembership(change(3, add: [.init(device: lamp, onLevel: 0xFF, rampRate: 0x1F)]))

    #expect(receipt.plan.isEmpty)
    #expect(await service.openSceneMembershipPlan(receipt.plan.id) == nil)
  }

  @Test func planningTheSamePlanAgainRestartsItsFiveMinutes() async throws {
    let clock = WallClock("2026-11-27T10:00:00Z")
    let service = service(await modem(), clock: clock)
    _ = try await service.refreshScenes()
    let first = try await service.planSceneMembership(change(add: [.init(device: lamp, onLevel: 0xFF, rampRate: 0x1F)]))
    clock.advance(by: 200)

    let second = try await service.planSceneMembership(change(add: [.init(device: lamp, onLevel: 0xFF, rampRate: 0x1F)]))
    clock.advance(by: 200)

    #expect(second.plan.id == first.plan.id)
    #expect(second.expiresAt == first.expiresAt.addingTimeInterval(200))
    #expect(await service.openSceneMembershipPlan(first.plan.id) != nil)
  }

  @Test func plansAnEmptySceneNumberSoItsFirstMemberCanBeAdded() async throws {
    let clock = WallClock("2026-11-27T10:00:00Z")
    let service = service(await modem(), clock: clock)
    _ = try await service.refreshScenes()

    let receipt = try await service.planSceneMembership(change(200, add: [.init(device: lamp, onLevel: 0x80, rampRate: 0x1C)]))

    #expect(receipt.plan.steps.last?.record.group == 200)
  }

  @Test func refusesAGroupADeviceControlsAsAnUnknownScene() async throws {
    let clock = WallClock("2026-11-27T10:00:00Z")
    let service = service(await modem(), clock: clock)
    _ = try await service.refreshScenes()

    await #expect(throws: ServiceControlError.unknownScene) {
      try await service.planSceneMembership(change(7, add: [.init(device: lamp, onLevel: nil, rampRate: nil)]))
    }
  }

  @Test func keepsAtMostEightPlansAndDropsTheOldest() async throws {
    let clock = WallClock("2026-11-27T10:00:00Z")
    let service = service(await modem(), clock: clock)
    _ = try await service.refreshScenes()
    var ids: [String] = []

    for scene in UInt8(10)..<UInt8(19) {
      ids.append(try await service.planSceneMembership(change(scene, add: [.init(device: lamp, onLevel: 0xFF, rampRate: 0x1F)])).plan.id)
    }

    #expect(await service.openSceneMembershipPlan(ids[0]) == nil)
    #expect(await service.openSceneMembershipPlan(ids[1]) != nil)
    #expect(await service.openSceneMembershipPlan(ids[8]) != nil)
  }

  @Test func doesNotTakeTheAdmissionGateSoItNeverMakesAnOperationRefuse() async throws {
    let clock = WallClock("2026-11-27T10:00:00Z")
    let service = service(await modem(), clock: clock)
    _ = try await service.refreshScenes()

    _ = try await service.planSceneMembership(change(add: [.init(device: lamp, onLevel: 0xFF, rampRate: 0x1F)]))

    _ = try await service.refreshScenes()
  }
}
