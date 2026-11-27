import Foundation
import InsteonCore
import InsteonHubClient
import InsteonLinkingTestSupport
import InsteonModem
import InsteonProtocol
import InsteonTestSupport
import Testing
@testable import InsteonService

/// The service keeps serving while the Hub or modem is away and reconnects by itself. Time
/// comes from a test clock and every wait is on a signal: an attempt starting, a sleep
/// beginning or an event arriving.
@Suite(.timeLimit(.minutes(1)))
struct ReconnectionTests {
  let address = InsteonAddress(0x1A, 0x2B, 0x3C)
  let clock = TestClock()
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  let hubAway = HubStoppedAnswering(underlyingError: URLError(.timedOut))

  private func service(opener: ScriptedOpener, store: (any NetworkSnapshotStore)? = nil, savedAt: Date? = nil, policy: ReconnectPolicy = .standard, now clockNow: (@Sendable () -> Date)? = nil) -> InsteonService {
    let identity = ReportedIdentity(category: 1, subcategory: 125, firmwareVersion: 69)
    let snapshot = NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [address: identity]), devices: [address: NetworkDeviceState(level: 77, lastSeen: now)])
    let current = now
    return InsteonService(
      network: DeviceNetwork.offline(catalog: nil, snapshot: snapshot, hub: nil),
      opener: opener,
      persistence: store.map(NetworkSnapshotPersistence.init(store:)),
      snapshotSavedAt: savedAt,
      reconnect: policy,
      clock: clock,
      now: clockNow ?? { current },
      jitter: { 0 }
    )
  }

  /// Runs the service with a host that waits until the test is done. The test's events are
  /// subscribed before the runtime starts, so none are missed.
  private func running(_ service: InsteonService, _ test: @escaping @Sendable (ServiceEvents) async throws -> Void) async throws {
    let events = await service.events()
    try await withThrowingTaskGroup(of: Void.self) { group in
      let hostStopped = AsyncStream<Void>.makeStream()
      group.addTask { _ = try await service.run { for await _ in hostStopped.0 {} } }
      do { try await test(events) } catch { hostStopped.1.finish(); group.cancelAll(); throw error }
      hostStopped.1.finish()
      try await group.waitForAll()
    }
  }

  @Test func theHubBeingAwayAtStartDoesNotStopTheServiceAndRefusesCommandsBeforeSendingAnything() async throws {
    let opener = ScriptedOpener([.fail(hubAway)])
    let service = service(opener: opener)
    try await running(service) { events in
      var attempts = opener.started.makeAsyncIterator()
      #expect(await attempts.next() == 1)
      await clock.waitForSleeper(until: .seconds(1))
      await #expect(throws: ServiceControlError.modemUnavailable(.hubUnreachable)) {
        try await service.execute(ServiceCommand(address: address, action: .on))
      }
      await #expect(throws: ServiceControlError.modemUnavailable(.hubUnreachable)) {
        try await service.execute(ServiceCommand(address: address, action: .status))
      }
      // The saved device list is served, with the cached level.
      let devices = try await service.devices()
      #expect(devices.map(\.address) == [address])
      #expect(devices.first?.value == 77)
    }
  }

  @Test func refusesASceneRefreshWhileTheHubIsAwayBeforeSendingAnything() async throws {
    let opener = ScriptedOpener([.fail(hubAway)])
    let service = service(opener: opener)
    try await running(service) { events in
      var attempts = opener.started.makeAsyncIterator()
      #expect(await attempts.next() == 1)
      await clock.waitForSleeper(until: .seconds(1))
      await #expect(throws: ServiceControlError.modemUnavailable(.hubUnreachable)) {
        try await service.refreshScenes()
      }
    }
  }

  @Test func healthSaysStartingWithTheCauseUntilTheFirstConnectionAndNeverTouchesHardware() async throws {
    let modem = InMemoryModem()
    let opener = ScriptedOpener([.fail(hubAway), .connect(ScriptedLink(modem: modem))])
    let saved = now.addingTimeInterval(-3_600)
    let service = service(opener: opener, savedAt: saved)
    try await running(service) { events in
      var attempts = opener.started.makeAsyncIterator()
      _ = await attempts.next()
      await clock.waitForSleeper(until: .seconds(1))
      let away = await service.health()
      #expect(away.readiness == .starting)
      #expect(away.modem == .unavailable(.hubUnreachable))
      #expect(away.lastHardwareExchange == nil)
      #expect(away.deviceInformationUpdated == saved)
      #expect(away.checkedAt == now)

      clock.advance(by: .seconds(1))
      var reader = events.makeAsyncIterator()
      let event1 = try await reader.next()
      #expect(event1 == .modemUnavailable(.hubUnreachable))
      let event2 = try await reader.next()
      #expect(event2 == .modemReconnected)

      let ready = await service.health()
      #expect(ready.readiness == .ready)
      #expect(ready.modem == .connected)
      #expect(ready.lastHardwareExchange == now)
      #expect(ready.deviceInformationUpdated == now)
      #expect(await modem.linkingSteps.isEmpty)
    }
  }

  @Test func healthSaysWhenTheLinkLastAnsweredAPollApartFromTheLastExchange() async throws {
    let opener = ScriptedOpener([.connect(ScriptedLink())])
    let start = now
    let clock = clock
    let service = service(opener: opener, now: { start.addingTimeInterval(Double(clock.now.offset.components.seconds)) })
    try await running(service) { events in
      var reader = events.makeAsyncIterator()
      let reconnected = try await reader.next()
      #expect(reconnected == .modemReconnected)
      let connected = await service.health()
      #expect(connected.lastHardwareExchange == start)
      #expect(connected.lastPoll == nil)

      clock.advance(by: .seconds(90))
      await opener.poll()
      let polled = await service.health()
      #expect(polled.lastPoll == start.addingTimeInterval(90))
      #expect(polled.lastHardwareExchange == start)

      clock.advance(by: .seconds(30))
      let quiet = await service.health()
      #expect(quiet.lastPoll == start.addingTimeInterval(90))
      #expect(quiet.checkedAt == start.addingTimeInterval(120))
    }
  }

  @Test func theNextSuccessfulAttemptRestoresCommandsWithoutARestartAndTellsClientsToRefresh() async throws {
    let modem = InMemoryModem()
    let opener = ScriptedOpener([.fail(hubAway), .connect(ScriptedLink(modem: modem))])
    let store = MemoryStore()
    let service = service(opener: opener, store: store)
    try await running(service) { events in
      var attempts = opener.started.makeAsyncIterator()
      _ = await attempts.next()
      await clock.waitForSleeper(until: .seconds(1))
      clock.advance(by: .seconds(1))
      var reader = events.makeAsyncIterator()
      let event3 = try await reader.next()
      #expect(event3 == .modemUnavailable(.hubUnreachable))
      let event4 = try await reader.next()
      #expect(event4 == .modemReconnected)

      let command = ServiceCommand(address: address, action: .on, levelPercent: 50)
      let receipt = try await service.execute(command)
      #expect(receipt.outcome == .acknowledged)
      #expect(await modem.levels[address] == 128)
      let event5 = try await reader.next()
      #expect(event5 == .commandCompleted(command, receipt))
      // The refreshed device information is saved once on connecting.
      #expect(await store.writes >= 1)
      #expect(await modem.modemDatabaseReads == 1)
    }
  }

  @Test func aLostConnectionKeepsTheServiceUpAnnouncesItAndReconnectsFromTheLatestSnapshot() async throws {
    let first = ScriptedLink()
    let second = ScriptedLink()
    let opener = ScriptedOpener([.connect(first), .connect(second)])
    let service = service(opener: opener)
    try await running(service) { events in
      var attempts = opener.started.makeAsyncIterator()
      _ = await attempts.next()
      var reader = events.makeAsyncIterator()
      let event6 = try await reader.next()
      #expect(event6 == .modemReconnected)
      _ = try await service.execute(ServiceCommand(address: address, action: .off))
      let event7 = try await reader.next()
      #expect(event7 != nil)

      first.drop(with: hubAway)
      let event8 = try await reader.next()
      #expect(event8 == .modemUnavailable(.hubUnreachable))
      #expect(await service.health().readiness == .degraded)
      await #expect(throws: ServiceControlError.modemUnavailable(.hubUnreachable)) {
        try await service.execute(ServiceCommand(address: address, action: .on))
      }
      #expect(try await service.devices().count == 1)

      await clock.waitForSleeper(until: .seconds(1))
      clock.advance(by: .seconds(1))
      let event9 = try await reader.next()
      #expect(event9 == .modemReconnected)
      #expect(await service.health().readiness == .ready)
      // The new connection starts from what the first one learned.
      let snapshots = await opener.snapshots
      #expect(snapshots.count == 2)
      #expect(snapshots[1].devices[address]?.level == 0)
      _ = try await service.execute(ServiceCommand(address: address, action: .on))
      #expect(await second.modem.levels[address] == 0xFF)
    }
  }

  @Test func aCommandThatFailedWhenTheConnectionDroppedIsNeverReplayedOnTheNextConnection() async throws {
    let first = ScriptedLink()
    let second = ScriptedLink()
    await first.modem.setBeforeOperation { operation in
      if case .standardRequest = operation { throw URLError(.timedOut) }
    }
    let opener = ScriptedOpener([.connect(first), .connect(second)])
    let service = service(opener: opener)
    try await running(service) { events in
      var attempts = opener.started.makeAsyncIterator()
      _ = await attempts.next()
      var reader = events.makeAsyncIterator()
      let event10 = try await reader.next()
      #expect(event10 == .modemReconnected)
      await #expect(throws: (any Error).self) {
        try await service.execute(ServiceCommand(address: address, action: .on))
      }
      first.drop(with: hubAway)
      let event11 = try await reader.next()
      #expect(event11 == .modemUnavailable(.hubUnreachable))
      await clock.waitForSleeper(until: .seconds(1))
      clock.advance(by: .seconds(1))
      let event12 = try await reader.next()
      #expect(event12 == .modemReconnected)
      #expect(await second.modem.levels.isEmpty)
      #expect(await second.modem.linkingSteps.isEmpty)
    }
  }

  @Test func retriesBackOffExponentiallyToACap() async throws {
    let opener = ScriptedOpener([])
    let service = service(opener: opener, policy: ReconnectPolicy(initialDelay: .seconds(1), maximumDelay: .seconds(5), credentialsDelay: .seconds(900), jitter: 0.25, reconnects: true))
    try await running(service) { events in
      var attempts = opener.started.makeAsyncIterator()
      var deadline = Duration.zero
      for delay in [1, 2, 4, 5, 5] {
        _ = await attempts.next()
        deadline += .seconds(delay)
        await clock.waitForSleeper(until: deadline)
        clock.advance(by: .seconds(delay))
      }
      #expect(await service.health().modem == .unavailable(.connectionLost))
    }
  }

  @Test func rejectedCredentialsAreReportedAndRetriedSlowlyNotInATightLoop() async throws {
    let opener = ScriptedOpener([.fail(HubError.unexpectedStatus(401))])
    let service = service(opener: opener)
    try await running(service) { events in
      var attempts = opener.started.makeAsyncIterator()
      _ = await attempts.next()
      await clock.waitForSleeper(until: ReconnectPolicy.standard.credentialsDelay)
      #expect(await service.health().modem == .unavailable(.credentialsRejected))
      await #expect(throws: ServiceControlError.modemUnavailable(.credentialsRejected)) {
        try await service.execute(ServiceCommand(address: address, action: .on))
      }
      clock.advance(by: ReconnectPolicy.standard.credentialsDelay)
    }
  }

  @Test func aTransientHubErrorStatusRetriesQuicklyAndNamesTheStatus() async throws {
    let opener = ScriptedOpener([.fail(HubError.unexpectedStatus(503))])
    let service = service(opener: opener)
    try await running(service) { events in
      var attempts = opener.started.makeAsyncIterator()
      _ = await attempts.next()
      await clock.waitForSleeper(until: .seconds(1))
      #expect(await service.health().modem == .unavailable(.hubErrorStatus(503)))
      clock.advance(by: .seconds(1))
    }
  }

  @Test func aFailedDatabaseReadAtStartupDoesNotAbortTheServiceAndTheSnapshotListStaysAvailable() async throws {
    let broken = InMemoryModem()
    await broken.setBeforeOperation { operation in
      if case .readModemDatabase = operation { throw ModemError.timedOut(.getFirstAllLinkRecord) }
    }
    let opener = ScriptedOpener([.connect(ScriptedLink(modem: broken)), .connect(ScriptedLink())])
    let service = service(opener: opener)
    try await running(service) { events in
      var attempts = opener.started.makeAsyncIterator()
      _ = await attempts.next()
      await clock.waitForSleeper(until: .seconds(1))
      #expect(await service.health().readiness == .starting)
      #expect(await service.health().modem == .unavailable(.modemUnreachable))
      #expect(try await service.devices().map(\.address) == [address])
      clock.advance(by: .seconds(1))
      var reader = events.makeAsyncIterator()
      let event13 = try await reader.next()
      #expect(event13 == .modemUnavailable(.modemUnreachable))
      let event14 = try await reader.next()
      #expect(event14 == .modemReconnected)
    }
  }

  @Test func aSubscriberThatArrivesWhileTheHubIsAwayIsToldAtOnce() async throws {
    let opener = ScriptedOpener([.fail(hubAway)])
    let service = service(opener: opener)
    try await running(service) { _ in
      var attempts = opener.started.makeAsyncIterator()
      _ = await attempts.next()
      await clock.waitForSleeper(until: .seconds(1))
      var late = await service.events().makeAsyncIterator()
      let event15 = try await late.next()
      #expect(event15 == .modemUnavailable(.hubUnreachable))
    }
  }

  @Test func aConfigurationErrorIsFatalInsteadOfRetriedForever() async throws {
    let opener = ScriptedOpener([.fail(HubAddressRefused(host: "example.com"))])
    let service = service(opener: opener)
    let (stream, continuation) = AsyncStream<Void>.makeStream()
    defer { continuation.finish() }
    await #expect(throws: HubAddressRefused.self) {
      _ = try await service.run { for await _ in stream {} }
    }
  }
}

private actor MemoryStore: NetworkSnapshotStore {
  var saved: NetworkSnapshot?
  var writes = 0
  func loadNetwork() async throws -> NetworkSnapshot { saved ?? NetworkSnapshot() }
  func saveNetwork(_ snapshot: NetworkSnapshot) async throws {
    writes += 1
    saved = snapshot
  }
}
