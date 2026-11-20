import Foundation
import InsteonProtocol
import InsteonScheduling
import InsteonTestSupport
@testable import InsteonService

/// The wall clock a scheduler reads, set by hand.
final class WallClock: @unchecked Sendable {
  private let lock = NSLock()
  private var date: Date

  init(_ iso8601: String) { date = Self.parse(iso8601) }

  var now: Date { lock.withLock { date } }

  func set(_ iso8601: String) { lock.withLock { date = Self.parse(iso8601) } }

  func set(_ moment: Date) { lock.withLock { date = moment } }

  func advance(by seconds: TimeInterval) { lock.withLock { date = date.addingTimeInterval(seconds) } }

  static func parse(_ iso8601: String) -> Date { try! Date(iso8601, strategy: .iso8601) }
}

/// Stands in for the service a scheduler belongs to: it knows some devices, records the commands sent and
/// the runs published, and answers each command as the test says.
final class FakeScheduleHost: @unchecked Sendable {
  static let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)
  static let relay = InsteonAddress(0x1A, 0x2B, 0x3D)
  static let sensor = InsteonAddress(0x1A, 0x2B, 0x3E)

  private let lock = NSLock()
  private var sent: [ServiceCommand] = []
  private var published: [ScheduleRun] = []
  private var failure: (any Error)?
  private let continuation: AsyncStream<ScheduleRun>.Continuation
  /// Every published run, in order, for a test to wait on.
  let runs: AsyncStream<ScheduleRun>

  init() { (runs, continuation) = AsyncStream.makeStream() }

  var commands: [ServiceCommand] { lock.withLock { sent } }
  var events: [ScheduleRun] { lock.withLock { published } }

  /// Makes every later command fail with `error`, or succeed with `nil`.
  func fail(with error: (any Error)?) { lock.withLock { failure = error } }

  var host: ScheduleHost {
    ScheduleHost(
      devices: {
        [
          ServiceDevice(address: Self.lamp, productName: "Lamp", canTurnOnAndOff: true, canDim: true, value: nil, lastAnsweredAt: nil),
          ServiceDevice(address: Self.relay, productName: "Relay", canTurnOnAndOff: true, canDim: false, value: nil, lastAnsweredAt: nil),
          ServiceDevice(address: Self.sensor, productName: "Sensor", canTurnOnAndOff: false, canDim: false, value: nil, lastAnsweredAt: nil)
        ]
      },
      execute: { [self] command in
        let error: (any Error)? = lock.withLock {
          sent.append(command)
          return failure
        }
        if let error { throw error }
        return CommandReceipt(address: command.address, outcome: .acknowledged, status: nil)
      },
      publish: { [self] run in
        lock.withLock { published.append(run) }
        continuation.yield(run)
      }
    )
  }
}

/// Schedules and timers in memory, counting what is saved.
final class MemoryScheduleStore: ScheduleStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var document: StoredSchedules?
  private var saved = 0
  private var loadFails = false
  private var saveFails = false

  init(_ document: StoredSchedules? = nil) { self.document = document }

  var stored: StoredSchedules? { lock.withLock { document } }
  var saves: Int { lock.withLock { saved } }

  func failLoading(_ fails: Bool) { lock.withLock { loadFails = fails } }
  func failSaving(_ fails: Bool) { lock.withLock { saveFails = fails } }

  struct Failure: Error {}

  func load() async throws -> StoredSchedules? {
    try lock.withLock {
      if loadFails { throw Failure() }
      return document
    }
  }

  func save(_ stored: StoredSchedules) async throws {
    try lock.withLock {
      if saveFails { throw Failure() }
      document = stored
      saved += 1
    }
  }
}

/// Sunrise at 7:00 and sunset at 19:00 local time, every day.
struct FixedSunTimes: SunTimes {
  func sunrise(on day: Date, in calendar: Calendar) -> Date? { calendar.date(bySettingHour: 7, minute: 0, second: 0, of: day) }
  func sunset(on day: Date, in calendar: Calendar) -> Date? { calendar.date(bySettingHour: 19, minute: 0, second: 0, of: day) }
}

/// A scheduler over a hand-set wall clock, a test clock, a fake host and a memory store.
struct SchedulerHarness {
  let scheduler: Scheduler
  let wall: WallClock
  let clock: TestClock
  let host: FakeScheduleHost
  let store: MemoryScheduleStore

  init(
    zone: String? = "America/Los_Angeles",
    at start: String = "2026-03-07T20:00:00Z",
    location: GeographicCoordinate? = GeographicCoordinate(latitude: 34.05, longitude: -118.24),
    store: MemoryScheduleStore = MemoryScheduleStore(),
    wall: WallClock? = nil,
    clock: TestClock = TestClock(),
    host: FakeScheduleHost = FakeScheduleHost(),
    sunTimes: @escaping @Sendable (GeographicCoordinate) -> any SunTimes = { SolarCalculator(location: $0) }
  ) {
    let wall = wall ?? WallClock(start)
    let configuration = ScheduleConfiguration(settings: ScheduleSettings(timeZoneIdentifier: zone, location: location), store: store, clock: clock, systemTimeZoneIdentifier: "UTC", sunTimes: sunTimes)
    scheduler = Scheduler(configuration: configuration, now: { wall.now }, host: host.host)
    self.wall = wall
    self.clock = clock
    self.host = host
    self.store = store
  }

  /// A scheduler that starts later over the same store, clocks and host, as after a restart.
  func restarted(zone: String? = "America/Los_Angeles", location: GeographicCoordinate? = GeographicCoordinate(latitude: 34.05, longitude: -118.24), clock: TestClock? = nil) -> SchedulerHarness {
    SchedulerHarness(zone: zone, location: location, store: store, wall: wall, clock: clock ?? self.clock, host: host)
  }
}

func daily(_ hour: Int, _ minute: Int, on weekdays: Set<Weekday> = Set(Weekday.allCases)) -> Schedule {
  Schedule(time: .clock(hour: hour, minute: minute), weekdays: weekdays)
}

func lampSchedule(_ id: String = "porch", when: Schedule, enabled: Bool = true, catchUp: Bool = false, action: ScheduledAction = ScheduledAction(device: FakeScheduleHost.lamp, kind: .on(levelPercent: 80))) -> ServiceSchedule {
  ServiceSchedule(id: id, name: "Porch light", isEnabled: enabled, when: when, action: action, catchUp: catchUp)
}

func utc(_ iso8601: String) -> Date { WallClock.parse(iso8601) }
