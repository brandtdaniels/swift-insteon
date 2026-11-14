import Foundation
import InsteonCore
import InsteonLinkingTestSupport
import InsteonProtocol
import Testing
@testable import InsteonService

@Suite(.timeLimit(.minutes(1)))
struct ServiceTests {
  let address = InsteonAddress(0x1A, 0x2B, 0x3C)

  @Test func softwareControlsNotifyEverySubscriberWithoutInventingAStatusReading() async throws {
    let service = InsteonService(network: network(InMemoryModem()))
    let first = await service.events()
    let second = await service.events()
    let command = ServiceCommand(address: address, action: .on, levelPercent: 50)
    let receipt = try await service.execute(command)
    var firstReader = first.makeAsyncIterator()
    var secondReader = second.makeAsyncIterator()
    #expect(try await firstReader.next() == .commandCompleted(command, receipt))
    #expect(try await secondReader.next() == .commandCompleted(command, receipt))
    #expect(receipt.outcome == .acknowledged)
    #expect(receipt.status == nil)
    #expect(try await service.devices().first?.value == 128)
  }

  @Test func failedPersistenceDoesNotSuppressConfirmedStatusEvents() async throws {
    let service = InsteonService(network: network(InMemoryModem()), persistence: NetworkSnapshotPersistence(store: MemoryStore(fails: true)))
    let events = await service.events()
    let command = ServiceCommand(address: address, action: .status)
    let receipt = try await service.execute(command)
    var reader = events.makeAsyncIterator()
    #expect(try await reader.next() == .commandCompleted(command, receipt))
    #expect(receipt.outcome == .read)
    #expect(receipt.status != nil)
    #expect(receipt.persistence == .failed)
  }

  @Test func failedCommandsAreNotPublishedAsCompletions() async throws {
    let service = InsteonService(network: network(InMemoryModem()))
    let events = await service.events()
    await #expect(throws: ServiceControlError.invalidLevel) {
      try await service.execute(ServiceCommand(address: address, action: .on, levelPercent: 101))
    }
    let successful = ServiceCommand(address: address, action: .off)
    let receipt = try await service.execute(successful)
    var reader = events.makeAsyncIterator()
    #expect(try await reader.next() == .commandCompleted(successful, receipt))
  }

  @Test func slowSubscribersEndWithAnExplicitGapInsteadOfSilentlyMissingCompletions() async throws {
    let service = InsteonService(network: network(InMemoryModem()))
    let events = await service.events()
    for _ in 0..<65 {
      _ = try await service.execute(ServiceCommand(address: address, action: .off))
    }
    await #expect(throws: ServiceEventError.slowConsumer) {
      for try await _ in events {}
    }
  }

  @Test func subscriptionsHaveNoCommandHistory() async throws {
    let service = InsteonService(network: network(InMemoryModem()))
    _ = try await service.execute(ServiceCommand(address: address, action: .on))
    let events = await service.events()
    let command = ServiceCommand(address: address, action: .off)
    let receipt = try await service.execute(command)
    var reader = events.makeAsyncIterator()
    #expect(try await reader.next() == .commandCompleted(command, receipt))
  }

  @Test func modemStreamEndingAlsoEndsTheIdleCommandSubscription() async throws {
    let monitor = AsyncStream<DeviceMonitorEvent> { $0.finish() }
    let events = ServiceEvents(monitor: monitor, subscription: CommandEventSubscription())
    var reader = events.makeAsyncIterator()
    #expect(try await reader.next() == nil)
  }

  @Test func cancelingOneSubscriberDoesNotStopOtherSubscribersOrCommands() async throws {
    let service = InsteonService(network: network(InMemoryModem()))
    let canceled = await service.events()
    let active = await service.events()
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        withUnsafeCurrentTask { $0?.cancel() }
        var reader = canceled.makeAsyncIterator()
        do {
          #expect(try await reader.next() == nil)
        } catch is CancellationError {
          // Cancellation can end the sequence or throw, depending on the active input.
        } catch {
          Issue.record(error)
        }
      }
      try await group.waitForAll()
    }
    let command = ServiceCommand(address: address, action: .on)
    let receipt = try await service.execute(command)
    var reader = active.makeAsyncIterator()
    #expect(try await reader.next() == .commandCompleted(command, receipt))
  }

  @Test func cachedQueriesDoNotSendHardwareRequests() async throws {
    let modem = InMemoryModem()
    let service = InsteonService(network: network(modem))
    let devices = try await service.devices()
    #expect(devices.first?.address == address)
    #expect(devices.first?.canDim == true)
    #expect(await modem.linkingSteps.isEmpty)
  }

  @Test func successfulControlsAndStatusHaveTypedResults() async throws {
    let modem = InMemoryModem()
    let store = MemoryStore()
    let service = InsteonService(network: network(modem), persistence: NetworkSnapshotPersistence(store: store))
    let receipt = try await service.execute(ServiceCommand(address: address, action: .on, levelPercent: 50))
    #expect(receipt.outcome == .acknowledged)
    #expect(receipt.status == nil)
    #expect(receipt.persistence == .saved)
    #expect(await modem.levels[address] == 128)
    #expect(await store.saved?.devices[address]?.level == 128)
    let status = try await service.execute(ServiceCommand(address: address, action: .status))
    #expect(status.outcome == .read)
    #expect(status.status?.reading == .percent(50))
    #expect(status.status?.value == 128)
  }

  @Test func failedPersistencePreservesAcknowledgmentAndTypedReadings() async throws {
    let modem = InMemoryModem()
    let service = InsteonService(network: network(modem), persistence: NetworkSnapshotPersistence(store: MemoryStore(fails: true)))
    let receipt = try await service.execute(ServiceCommand(address: address, action: .on, levelPercent: 50))
    #expect(receipt.outcome == .acknowledged)
    #expect(receipt.persistence == .failed)
    let reading = try await service.execute(ServiceCommand(address: address, action: .status))
    #expect(reading.outcome == .read)
    #expect(reading.status?.reading == .percent(50))
    #expect(reading.persistence == .failed)
    #expect(await service.persistenceOutcome == .failed)
    #expect(await modem.levels[address] == 128)
  }

  @Test func invalidOperationsNeverReachHardware() async throws {
    let modem = InMemoryModem()
    let service = InsteonService(network: network(modem))
    await #expect(throws: ServiceControlError.invalidLevel) {
      try await service.execute(ServiceCommand(address: address, action: .on, levelPercent: 101))
    }
    await #expect(throws: ServiceControlError.invalidLevel) {
      try await service.execute(ServiceCommand(address: address, action: .off, levelPercent: 20))
    }
    await #expect(throws: ServiceControlError.unknownDevice) {
      try await service.execute(ServiceCommand(address: InsteonAddress(0x11, 0x22, 0x44), action: .off))
    }
    #expect(await modem.linkingSteps.isEmpty)
  }

  @Test func theServiceOwnsAdmissionAcrossAllClients() async throws {
    let modem = InMemoryModem()
    let gate = OperationGate()
    await modem.setBeforeOperation { _ in await gate.pause() }
    let service = InsteonService(network: network(modem))
    let command = ServiceCommand(address: address, action: .on)
    try await withThrowingTaskGroup(of: CommandReceipt.self) { group in
      group.addTask { try await service.execute(command) }
      await gate.waitUntilPaused()
      await #expect(throws: ServiceControlError.busy) { try await service.devices() }
      await #expect(throws: ServiceControlError.busy) { try await service.checkpoint() }
      await gate.release()
      let receipt = try await group.next()
      #expect(receipt?.outcome == .acknowledged)
    }
  }

  @Test func eventsLearnIdentityWithoutInventingStatus() async throws {
    let modem = InMemoryModem()
    let network = network(modem)
    let service = InsteonService(network: network)
    let events = await service.events()
    let other = InsteonAddress(0x1A, 0x2B, 0x44)
    await modem.setIdentity(SetButtonPressed(sender: other, role: .responder, category: 1, subcategory: 125, firmwareVersion: 69))
    await modem.broadcastIdentity(of: other)
    var iterator = events.makeAsyncIterator()
    #expect(try await iterator.next() == .setButtonPressed(other))
    #expect(await network.registry.device(other) != nil)
    #expect(await network.state(of: other)?.lastSeen == nil)
  }

  @Test func runtimePreparesAndSavesWithoutAnyHTTPHost() async throws {
    let store = MemoryStore()
    let service = InsteonService(network: network(InMemoryModem()), persistence: NetworkSnapshotPersistence(store: store))
    let outcome = try await service.run {}
    #expect(outcome == .saved)
    #expect(await store.writes == 2)
  }

  @Test func aFailedHostStillCheckpointsBeforeTheRuntimeExits() async throws {
    struct HostFailure: Error {}
    let store = MemoryStore()
    let service = InsteonService(network: network(InMemoryModem()), persistence: NetworkSnapshotPersistence(store: store))
    await #expect(throws: HostFailure.self) {
      try await service.run { throw HostFailure() }
    }
    #expect(await store.writes == 2)
  }

  private func network(_ modem: InMemoryModem) -> DeviceNetwork {
    DeviceNetwork(modem: modem, catalog: nil, snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [address: ReportedIdentity(category: 1, subcategory: 125, firmwareVersion: 69)])), now: { Date(timeIntervalSince1970: 1_800_000_000) })
  }
}

private actor MemoryStore: NetworkSnapshotStore {
  var saved: NetworkSnapshot?
  var writes = 0
  let fails: Bool
  init(fails: Bool = false) { self.fails = fails }
  func loadNetwork() async throws -> NetworkSnapshot { saved ?? NetworkSnapshot() }
  func saveNetwork(_ snapshot: NetworkSnapshot) async throws {
    writes += 1
    if fails { throw StoreFailure() }
    saved = snapshot
  }
  struct StoreFailure: Error {}
}

private actor OperationGate {
  private var paused = false
  private var started: CheckedContinuation<Void, Never>?
  private var continuation: CheckedContinuation<Void, Never>?
  func pause() async {
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
