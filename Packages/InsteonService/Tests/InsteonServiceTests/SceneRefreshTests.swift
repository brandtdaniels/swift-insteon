import Foundation
import InsteonCore
import InsteonLinkingTestSupport
import InsteonModem
import InsteonProtocol
import Testing
@testable import InsteonService

/// Refreshing the scenes reads the ALL-Link databases of the modem and of each device from
/// the hardware, one request at a time, and writes nothing.
@Suite(.timeLimit(.minutes(1)))
struct SceneRefreshTests {
  let modemAddress = InsteonAddress(0x11, 0x22, 0x33)
  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)
  let keypad = InsteonAddress(0x4D, 0x5E, 0x6F)
  let identity = ReportedIdentity(category: 1, subcategory: 125, firmwareVersion: 69)

  private func network(_ modem: InMemoryModem, knowing devices: [InsteonAddress]) -> DeviceNetwork {
    let identities = Dictionary(uniqueKeysWithValues: devices.map { ($0, identity) })
    return DeviceNetwork(modem: modem, catalog: nil, snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: identities)), now: { Date(timeIntervalSince1970: 1_800_000_000) })
  }

  /// A modem whose scene 3 has the lamp as a member, with both halves of the link in place.
  private func modemWithOneScene() async -> InMemoryModem {
    let modem = InMemoryModem()
    await modem.setModemRecords([AllLinkRecord(flags: [.inUse, .controller], group: 3, address: lamp, data1: 0, data2: 0, data3: 0)])
    await modem.setDatabase([0x0FFF: AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 3, address: modemAddress, data1: 0xFF, data2: 0x1F, data3: 0x01)], of: lamp)
    return modem
  }

  @Test func readsTheModemAndEachDeviceThenListsTheScenesWithTheirMembers() async throws {
    let modem = await modemWithOneScene()
    let service = InsteonService(network: network(modem, knowing: [lamp]))
    #expect(await service.scenes().scenes.isEmpty)

    let listing = try await service.refreshScenes()

    let scene = try #require(listing.scenes.first)
    #expect(scene.number == 3)
    #expect(scene.members == [SceneListing.Member(address: lamp, data: [0xFF, 0x1F, 0x01])])
    #expect(listing.isWhole)
    #expect(await service.scenes() == listing)
    #expect(await modem.modemDatabaseReads == 1)
    #expect(await modem.databaseReads[lamp] == 1)
  }

  @Test func readsADeviceOnlyTheModemNamesAsWellAsOnesTheRegistryKnows() async throws {
    let modem = await modemWithOneScene()
    await modem.setModemRecords([AllLinkRecord(flags: [.inUse, .controller], group: 3, address: lamp, data1: 0, data2: 0, data3: 0)])
    let service = InsteonService(network: network(modem, knowing: [keypad]))

    _ = try await service.refreshScenes()

    #expect(await modem.databaseReads[lamp] == 1)
    #expect(await modem.databaseReads[keypad] == 1)
    #expect(await modem.databaseReads[modemAddress] == nil)
  }

  @Test func listsADeviceThatDoesNotAnswerAsUnreadableAndStillSucceeds() async throws {
    let modem = await modemWithOneScene()
    await modem.setUnlinked(keypad)
    let service = InsteonService(network: network(modem, knowing: [lamp, keypad]))

    let listing = try await service.refreshScenes()

    #expect(listing.unreadable == [keypad])
    #expect(!listing.isWhole)
    #expect(listing.scenes.first?.members.map(\.address) == [lamp])
  }

  @Test func writesNothingToAnyDeviceOrTheModem() async throws {
    let modem = await modemWithOneScene()
    let service = InsteonService(network: network(modem, knowing: [lamp, keypad]))

    _ = try await service.refreshScenes()

    #expect(await modem.writes.isEmpty)
    #expect(await modem.linkingSteps.isEmpty)
    #expect(await modem.modemDeletions == 0)
    #expect(await modem.extendedRequests.isEmpty)
  }

  @Test func savesACheckpointOfWhatItRead() async throws {
    let modem = await modemWithOneScene()
    let store = RecordingStore()
    let service = InsteonService(network: network(modem, knowing: [lamp]), persistence: NetworkSnapshotPersistence(store: store))

    _ = try await service.refreshScenes()

    let saved = try #require(await store.saved)
    #expect(saved.modemDatabase?.count == 1)
    #expect(saved.devices[lamp]?.allLinkDatabase != nil)
  }

  @Test func refusesWhileAnotherOperationHoldsTheGateAndQueuesNothing() async throws {
    let modem = await modemWithOneScene()
    let pause = Pause()
    await modem.setBeforeOperation { operation in
      if case .readModemDatabase = operation { await pause.wait() }
    }
    let service = InsteonService(network: network(modem, knowing: [lamp]))
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask { _ = try await service.refreshScenes() }
      await pause.waitUntilPaused()
      await #expect(throws: ServiceControlError.busy) { try await service.refreshScenes() }
      await #expect(throws: ServiceControlError.busy) { try await service.execute(ServiceCommand(address: lamp, action: .on)) }
      await pause.release()
      try await group.waitForAll()
    }
    #expect(await modem.modemDatabaseReads == 1)
    #expect(await modem.levels.isEmpty)
  }

  @Test func readsNothingAndReleasesTheGateWhenCanceled() async throws {
    let modem = await modemWithOneScene()
    let pause = Pause()
    await modem.setBeforeOperation { operation in
      if case .readModemDatabase = operation { await pause.wait() }
    }
    let service = InsteonService(network: network(modem, knowing: [lamp]))
    let task = Task { try await service.refreshScenes() }
    await pause.waitUntilPaused()
    task.cancel()
    await pause.release()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(await modem.databaseReads.isEmpty)

    await modem.setBeforeOperation(nil)
    let listing = try await service.refreshScenes()
    #expect(listing.scenes.count == 1)
  }

  @Test func failsWhenTheConnectionIsLostAndReleasesTheGate() async throws {
    let modem = await modemWithOneScene()
    await modem.setBeforeOperation { operation in
      if case .readModemDatabase = operation { throw ModemError.connectionClosed }
    }
    let service = InsteonService(network: network(modem, knowing: [lamp]))
    await #expect(throws: ModemError.connectionClosed) { try await service.refreshScenes() }

    await modem.setBeforeOperation(nil)
    #expect(try await service.refreshScenes().scenes.count == 1)
  }
}

private actor RecordingStore: NetworkSnapshotStore {
  var saved: NetworkSnapshot?
  func loadNetwork() async throws -> NetworkSnapshot { saved ?? NetworkSnapshot() }
  func saveNetwork(_ snapshot: NetworkSnapshot) async throws { saved = snapshot }
}

/// Holds one operation until the test releases it, with signals in place of waits on time.
private actor Pause {
  private var paused = false
  private var started: CheckedContinuation<Void, Never>?
  private var continuation: CheckedContinuation<Void, Never>?
  func wait() async {
    await withCheckedContinuation {
      continuation = $0
      paused = true
      started?.resume()
      started = nil
    }
  }
  func waitUntilPaused() async { if !paused { await withCheckedContinuation { started = $0 } } }
  func release() { continuation?.resume(); continuation = nil }
}
