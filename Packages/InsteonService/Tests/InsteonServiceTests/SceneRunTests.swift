import Foundation
import InsteonCore
import InsteonLinkingTestSupport
import InsteonModem
import InsteonProtocol
import Testing
@testable import InsteonService

/// Running a scene sends its group one command through the modem, and nothing to any device.
@Suite(.timeLimit(.minutes(1)))
struct SceneRunTests {
  let modemAddress = InsteonAddress(0x11, 0x22, 0x33)
  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)
  let keypad = InsteonAddress(0x4D, 0x5E, 0x6F)
  let identity = ReportedIdentity(category: 1, subcategory: 125, firmwareVersion: 69)
  let firedAt = Date(timeIntervalSince1970: 1_800_000_000)

  private func service(_ modem: InMemoryModem, persistence: (any SnapshotPersisting)? = nil) -> InsteonService {
    let identities = [lamp: identity, keypad: identity]
    let network = DeviceNetwork(modem: modem, catalog: nil, snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: identities)), now: { firedAt })
    return InsteonService(network: network, persistence: persistence)
  }

  private func responder(group: UInt8) -> AllLinkRecord {
    AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: AllLinkGroupNumber(rawValue: group), address: modemAddress, data1: 0xFF, data2: 0x1F, data3: 0x01)
  }

  /// A modem whose scene 3 has the lamp and the keypad as members, with both halves of each link in place.
  private func modemWithScenes() async -> InMemoryModem {
    let modem = InMemoryModem()
    await modem.setModemRecords([
      AllLinkRecord(flags: [.inUse, .controller], group: 3, address: lamp, data1: 0, data2: 0, data3: 0),
      AllLinkRecord(flags: [.inUse, .controller], group: 3, address: keypad, data1: 0, data2: 0, data3: 0)
    ])
    await modem.setDatabase([0x0FFF: responder(group: 3)], of: lamp)
    await modem.setDatabase([0x0FFF: responder(group: 3)], of: keypad)
    return modem
  }

  @Test func sendsTheGroupOneLightOnAtFullLevelAndAnswersTheCleanupReport() async throws {
    let modem = await modemWithScenes()
    await modem.setGroupReport(AllLinkCleanupReport(acknowledged: [lamp], unacknowledged: [keypad], isComplete: true))
    let service = service(modem)
    _ = try await service.refreshScenes()

    let receipt = try await service.runScene(SceneCommand(number: 3, action: .on))

    #expect(await modem.groupCommands.map(\.group) == [3])
    #expect(await modem.groupCommands.map(\.command) == [Command(command1: 0x11, command2: 0xFF)])
    #expect(receipt == SceneReceipt(scene: 3, action: .on, acknowledged: [lamp], unacknowledged: [keypad], isComplete: true, responderCount: 2, persistence: .notConfigured))
  }

  @Test func sendsLightOffForOff() async throws {
    let modem = await modemWithScenes()
    let service = service(modem)
    _ = try await service.refreshScenes()

    _ = try await service.runScene(SceneCommand(number: 3, action: .off))

    #expect(await modem.groupCommands.map(\.group) == [3])
    #expect(await modem.groupCommands.map(\.command) == [Command(command1: 0x13, command2: 0x00)])
  }

  @Test func sendsNothingToAnyDeviceAndDoesNotReadOneAgain() async throws {
    let modem = await modemWithScenes()
    let service = service(modem)
    _ = try await service.refreshScenes()
    let reads = await modem.databaseReads

    _ = try await service.runScene(SceneCommand(number: 3, action: .on))

    #expect(await modem.writes.isEmpty)
    #expect(await modem.levels.isEmpty)
    #expect(await modem.databaseReads == reads)
  }

  @Test func sendsTheGroupCommandOnceAndNeverAgainByItself() async throws {
    let modem = await modemWithScenes()
    let service = service(modem)
    _ = try await service.refreshScenes()

    _ = try await service.runScene(SceneCommand(number: 3, action: .on))

    #expect(await modem.groupCommands.count == 1)
  }

  @Test func savesACheckpointAndReportsHowItWent() async throws {
    let modem = await modemWithScenes()
    let store = RecordingStore()
    let service = service(modem, persistence: NetworkSnapshotPersistence(store: store))
    _ = try await service.refreshScenes()

    let receipt = try await service.runScene(SceneCommand(number: 3, action: .on))

    #expect(receipt.persistence == .saved)
    #expect(await store.saved != nil)
  }

  @Test func publishesASceneEventAfterTheRunWithWhatTheModemReported() async throws {
    let modem = await modemWithScenes()
    await modem.setGroupReport(AllLinkCleanupReport(acknowledged: [lamp, keypad], unacknowledged: [], isComplete: true))
    let service = service(modem)
    _ = try await service.refreshScenes()
    let events = await service.events()

    let receipt = try await service.runScene(SceneCommand(number: 3, action: .off))

    var reader = events.makeAsyncIterator()
    let event = try await reader.next()
    guard case let .scene(run)? = event else { Issue.record("expected a scene event, got \(String(describing: event))"); return }
    #expect(run.number == 3)
    #expect(run.name == nil)
    #expect(run.source == .api)
    #expect(run.action == .off)
    #expect(run.receipt == receipt)
    #expect(abs(run.firedAt.timeIntervalSinceNow) < 60)
  }

  @Test func publishesNoEventWhenTheRunFails() async throws {
    let modem = await modemWithScenes()
    let service = service(modem)
    _ = try await service.refreshScenes()
    await modem.setRejectsGroupCommands(true)
    let events = await service.events()

    await #expect(throws: ModemError.rejected(.sendAllLinkCommand)) { try await service.runScene(SceneCommand(number: 3, action: .on)) }
    await modem.setRejectsGroupCommands(false)
    let receipt = try await service.runScene(SceneCommand(number: 3, action: .on))

    var reader = events.makeAsyncIterator()
    guard case let .scene(run)? = try await reader.next() else { Issue.record("expected the scene event of the second run"); return }
    #expect(run.receipt == receipt)
  }

  // MARK: Refusals, each before anything is sent

  @Test func refusesASceneTheListingDoesNotHold() async throws {
    let modem = await modemWithScenes()
    let service = service(modem)
    _ = try await service.refreshScenes()

    await #expect(throws: ServiceControlError.unknownScene) { try await service.runScene(SceneCommand(number: 9, action: .on)) }
    #expect(await modem.groupCommands.isEmpty)
  }

  @Test func refusesEverySceneBeforeTheScenesAreRead() async throws {
    let modem = await modemWithScenes()
    let service = service(modem)

    await #expect(throws: ServiceControlError.unknownScene) { try await service.runScene(SceneCommand(number: 3, action: .on)) }
    #expect(await modem.groupCommands.isEmpty)
  }

  @Test func refusesAGroupADeviceControlsBecauseTheModemCannotRunIt() async throws {
    let modem = await modemWithScenes()
    await modem.setDatabase([
      0x0FFF: responder(group: 3),
      0x0FF7: AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 7, address: keypad, data1: 0, data2: 0, data3: 0)
    ], of: lamp)
    await modem.setDatabase([
      0x0FFF: responder(group: 3),
      0x0FF7: AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 7, address: lamp, data1: 0xFF, data2: 0x1F, data3: 0x01)
    ], of: keypad)
    let service = service(modem)
    let listing = try await service.refreshScenes()
    #expect(listing.scenes.contains { $0.number == 7 && !$0.isWritable })

    await #expect(throws: ServiceControlError.unknownScene) { try await service.runScene(SceneCommand(number: 7, action: .on)) }
    #expect(await modem.groupCommands.isEmpty)
  }

  @Test func refusesASceneWithNoMembersAndSendsNothing() async throws {
    let modem = InMemoryModem()
    // The modem controls group 5 for the lamp, but the lamp holds no responder record for it.
    await modem.setModemRecords([AllLinkRecord(flags: [.inUse, .controller], group: 5, address: lamp, data1: 0, data2: 0, data3: 0)])
    let service = service(modem)
    let listing = try await service.refreshScenes()
    #expect(listing.scenes.first { $0.number == 5 }?.members.isEmpty == true)

    await #expect(throws: ServiceControlError.sceneEmpty) { try await service.runScene(SceneCommand(number: 5, action: .on)) }
    #expect(await modem.groupCommands.isEmpty)
  }

  @Test func refusesWhileAnotherOperationHoldsTheGateAndQueuesNothing() async throws {
    let modem = await modemWithScenes()
    let service = service(modem)
    _ = try await service.refreshScenes()
    let pause = Pause()
    await modem.setBeforeOperation { operation in
      if case .sendAllLinkCommand = operation { await pause.wait() }
    }
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask { _ = try await service.runScene(SceneCommand(number: 3, action: .on)) }
      await pause.waitUntilPaused()
      await #expect(throws: ServiceControlError.busy) { try await service.runScene(SceneCommand(number: 3, action: .off)) }
      await #expect(throws: ServiceControlError.busy) { try await service.execute(ServiceCommand(address: lamp, action: .on)) }
      await #expect(throws: ServiceControlError.busy) { try await service.refreshScenes() }
      await pause.release()
      try await group.waitForAll()
    }
    #expect(await modem.groupCommands.count == 1)
  }

  @Test func holdsTheGateWhileAnotherOperationRunsSoARunIsRefusedAsBusy() async throws {
    let modem = await modemWithScenes()
    let service = service(modem)
    _ = try await service.refreshScenes()
    let pause = Pause()
    await modem.setBeforeOperation { operation in
      if case .readModemDatabase = operation { await pause.wait() }
    }
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask { _ = try await service.refreshScenes() }
      await pause.waitUntilPaused()
      await #expect(throws: ServiceControlError.busy) { try await service.runScene(SceneCommand(number: 3, action: .on)) }
      await pause.release()
      try await group.waitForAll()
    }
    #expect(await modem.groupCommands.isEmpty)
  }

  // MARK: Failures

  @Test func passesOnTheModemsRefusalAndReleasesTheGate() async throws {
    let modem = await modemWithScenes()
    await modem.setRejectsGroupCommands(true)
    let service = service(modem)
    _ = try await service.refreshScenes()

    await #expect(throws: ModemError.rejected(.sendAllLinkCommand)) { try await service.runScene(SceneCommand(number: 3, action: .on)) }
    await modem.setRejectsGroupCommands(false)

    _ = try await service.runScene(SceneCommand(number: 3, action: .on))
  }

  @Test func passesOnALostConnectionAndSendsOnlyOnce() async throws {
    let modem = await modemWithScenes()
    let service = service(modem)
    _ = try await service.refreshScenes()
    await modem.setBeforeOperation { operation in
      if case .sendAllLinkCommand = operation { throw ModemError.connectionClosed }
    }

    await #expect(throws: ModemError.connectionClosed) { try await service.runScene(SceneCommand(number: 3, action: .on)) }
    #expect(await modem.groupCommands.isEmpty)
  }

  @Test func refusesBeforeSendingWhileTheModemIsAway() async throws {
    let modem = await modemWithScenes()
    let service = InsteonService(
      network: DeviceNetwork(modem: modem, catalog: nil, snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [lamp: identity]))),
      opener: AwayOpener()
    )

    await #expect(throws: ServiceControlError.modemUnavailable(.connecting)) { try await service.runScene(SceneCommand(number: 3, action: .on)) }
    #expect(await modem.groupCommands.isEmpty)
  }
}

/// An opener that is never asked, since the service in the test isn't run.
private struct AwayOpener: ServedNetworkOpening {
  func withServedNetwork(snapshot: NetworkSnapshot, onPollSucceeded: @escaping @Sendable () async -> Void, _ body: @escaping @Sendable (any ServedNetwork) async throws -> Void) async throws { throw ModemError.connectionClosed }
}
