import Foundation
import InsteonCore
import InsteonDeviceCatalog
import InsteonLinkingTestSupport
import InsteonProtocol
import InsteonTestSupport
import Testing
@testable import InsteonService

/// The service owns a scheduler: schedules run through its own command path and are published on its numbered
/// events. Nothing waits on time: the wall clock is set by hand and the service's clock is a test clock.
@Suite(.timeLimit(.minutes(1)))
struct ServiceScheduleTests {
  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)

  private struct Running {
    let service: InsteonService
    let modem: InMemoryModem
    let wall: WallClock
    let clock: TestClock
    let store: MemoryScheduleStore
    let stop: AsyncStream<Void>.Continuation
    let finished: Task<PersistenceOutcome, any Error>
  }

  private func start(zone: String? = "America/Los_Angeles", at: String = "2026-03-08T14:59:30Z", store: MemoryScheduleStore = MemoryScheduleStore()) -> Running {
    let modem = InMemoryModem()
    let clock = TestClock()
    let wall = WallClock(at)
    let identity = ReportedIdentity(category: 1, subcategory: 125, firmwareVersion: 69)
    let snapshot = NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [lamp: identity]))
    let network = DeviceNetwork(modem: InMemoryModem(), catalog: nil, snapshot: snapshot)
    let opener = ScriptedOpener([.connect(ScriptedLink(modem: modem))], clock: clock)
    let configuration = ScheduleConfiguration(settings: ScheduleSettings(timeZoneIdentifier: zone, location: nil), store: store, clock: clock, systemTimeZoneIdentifier: "UTC")
    let service = InsteonService(network: network, opener: opener, reconnect: .never, clock: clock, now: { wall.now }, scheduling: configuration)
    let (stopped, stop) = AsyncStream<Void>.makeStream()
    let finished = Task { try await service.run { for await _ in stopped {} } }
    return Running(service: service, modem: modem, wall: wall, clock: clock, store: store, stop: stop, finished: finished)
  }

  private func connected(_ running: Running) async throws -> SequencedEvents.AsyncIterator {
    var iterator = await running.service.sequencedEvents(after: nil).makeAsyncIterator()
    guard case let .position(cursor)? = try await iterator.next() else { throw CancellationError() }
    if cursor.sequence == 0 {
      while let item = try await iterator.next() {
        if case .event(.modemReconnected, _) = item { break }
      }
    }
    return iterator
  }

  private func shutDown(_ running: Running) async {
    running.stop.finish()
    _ = try? await running.finished.value
  }

  @Test func aScheduleSendsItsCommandThroughTheServiceAndPublishesANumberedEvent() async throws {
    let running = start()
    var events = try await connected(running)
    let entry = try await running.service.putSchedule(ServiceSchedule(id: "porch", name: "Porch light", when: daily(8, 0), action: ScheduledAction(device: lamp, kind: .on(levelPercent: 50))))
    #expect(entry.nextRun == utc("2026-03-08T15:00:00Z"))

    running.wall.set("2026-03-08T15:00:00Z")
    running.clock.advance(by: .seconds(30))

    var seen: [ServiceEvent] = []
    var cursors: [UInt64] = []
    while let item = try await events.next() {
      guard case let .event(event, cursor) = item else { continue }
      seen.append(event)
      cursors.append(cursor.sequence)
      if case .schedule = event { break }
    }
    await shutDown(running)

    guard case let .commandCompleted(command, _) = seen.first, case let .schedule(run) = seen.last else {
      Issue.record("expected the command, then the run: \(seen)")
      return
    }
    #expect(command == ServiceCommand(address: lamp, action: .on, levelPercent: 50))
    #expect(run == ScheduleRun(source: .schedule, id: "porch", name: "Porch light", device: lamp, outcome: .acknowledged, firedAt: utc("2026-03-08T15:00:00Z"), nextRun: utc("2026-03-09T15:00:00Z")))
    #expect(cursors == Array((cursors.first ?? 0)...(cursors.first ?? 0) + 1))
    #expect(await running.modem.levels[lamp] == 128)
  }

  @Test func refusesAnActionForADeviceTheServiceDoesntKnow() async throws {
    let running = start()
    _ = try await connected(running)

    await #expect(throws: ScheduleError.unknownDevice) {
      try await running.service.putSchedule(ServiceSchedule(id: "porch", name: "Porch light", when: daily(8, 0), action: ScheduledAction(device: InsteonAddress(0x09, 0x09, 0x09), kind: .off)))
    }
    #expect(try await running.service.schedules().isEmpty)
    await shutDown(running)
  }

  @Test func theSchedulesSurviveARestartOverTheSameStore() async throws {
    let store = MemoryScheduleStore()
    let first = start(store: store)
    _ = try await connected(first)
    _ = try await first.service.putSchedule(ServiceSchedule(id: "porch", name: "Porch light", when: daily(8, 0), action: ScheduledAction(device: lamp, kind: .off)))
    await shutDown(first)

    let second = start(store: store)
    #expect(try await second.service.schedules().map(\.schedule.id) == ["porch"])
    await shutDown(second)
  }

  @Test func healthNamesATimeZoneTheHostDoesntHave() async throws {
    let running = start(zone: "Not/AZone")
    _ = try await connected(running)

    #expect(await running.service.health().notes == [.timeZoneUnavailable("Not/AZone")])
    await shutDown(running)
  }

  @Test func healthHasNoNotesForAKnownTimeZone() async throws {
    let running = start()
    _ = try await connected(running)

    #expect(await running.service.health().notes.isEmpty)
    await shutDown(running)
  }
}
