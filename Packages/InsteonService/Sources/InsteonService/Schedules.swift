import Foundation
import InsteonProtocol
import InsteonScheduling

/// A switching command a schedule or a timer sends: turn a device's main group on, optionally at a
/// percentage, or off.
///
/// An action is one of the service's own commands, so it is sent the way a client's command is and
/// reports the way one does. The service checks it against the device when it stores it.
public struct ScheduledAction: Hashable, Sendable {
  /// What the action does.
  public enum Kind: Hashable, Sendable {
    /// Turn the main group on, at a percentage when the group dims.
    case on(levelPercent: Int?)
    /// Turn the main group off.
    case off
  }

  /// The device the action is for.
  public var device: InsteonAddress
  /// What it does.
  public var kind: Kind

  /// Creates an action.
  public init(device: InsteonAddress, kind: Kind) {
    self.device = device
    self.kind = kind
  }

  /// The service command the action sends.
  var command: ServiceCommand {
    switch kind {
    case let .on(level): ServiceCommand(address: device, action: .on, levelPercent: level)
    case .off: ServiceCommand(address: device, action: .off)
    }
  }
}

/// A command the service sends at the same time on chosen days, such as "turn the porch light on 15
/// minutes after sunset".
///
/// A clock time means wall-clock time in the network's time zone, so it follows daylight saving time
/// with no edit. Sunrise and sunset are worked out for the network's location.
public struct ServiceSchedule: Hashable, Sendable {
  /// The most schedules the service keeps.
  public static let maximumCount = 64
  /// The longest a schedule's identifier or name is, in characters.
  public static let longestTextLength = 64
  /// The furthest a sunrise or sunset offset reaches, in seconds: 12 hours either way.
  public static let longestOffsetSeconds = 43_200
  /// How long after its time a run still counts as on time, in seconds.
  public static let onTimeSeconds = 60
  /// How long after its time a run with ``catchUp`` still runs, in seconds.
  public static let catchUpSeconds = 900

  /// The schedule's identifier: letters, digits, `-`, `_` and `.`, at most 64 characters. A client chooses it.
  public var id: String
  /// What people call the schedule, 1 through 64 characters without control characters.
  public var name: String
  /// Whether the schedule runs at all.
  public var isEnabled: Bool
  /// The days and the time of day.
  public var when: Schedule
  /// What it sends.
  public var action: ScheduledAction
  /// Whether a run the service missed while it was stopped still happens, when it is less than
  /// 15 minutes late. Off, a missed run is skipped.
  public var catchUp: Bool

  /// Creates a schedule. The service validates it when it is stored.
  public init(id: String, name: String, isEnabled: Bool = true, when: Schedule, action: ScheduledAction, catchUp: Bool = false) {
    self.id = id
    self.name = name
    self.isEnabled = isEnabled
    self.when = when
    self.action = action
    self.catchUp = catchUp
  }
}

/// A command the service sends once, after a delay, such as "turn the light off in 10 minutes".
///
/// A timer counts elapsed time, so a change of the clock neither lengthens nor shortens it. It
/// is removed when it fires. It survives a restart: the time the service was running counts, and
/// the time it was stopped doesn't.
public struct ServiceTimer: Hashable, Sendable {
  /// The most timers the service keeps.
  public static let maximumCount = 64
  /// The longest delay, in seconds: one week.
  public static let longestDelaySeconds = 604_800

  /// The timer's identifier, with the same rules as a schedule's.
  public var id: String
  /// What people call the timer, with the same rules as a schedule's.
  public var name: String
  /// How long after it is stored the timer fires, in seconds from 1 through ``longestDelaySeconds``.
  public var delaySeconds: Int
  /// What it sends.
  public var action: ScheduledAction

  /// Creates a timer. The service validates it when it is stored.
  public init(id: String, name: String, delaySeconds: Int, action: ScheduledAction) {
    self.id = id
    self.name = name
    self.delaySeconds = delaySeconds
    self.action = action
  }
}

/// A stored schedule and the next time it runs.
public struct ScheduleEntry: Equatable, Sendable {
  /// The schedule.
  public let schedule: ServiceSchedule
  /// When it runs next, or `nil` when it is disabled or has no run to come.
  public let nextRun: Date?

  /// Creates an entry.
  public init(schedule: ServiceSchedule, nextRun: Date?) {
    self.schedule = schedule
    self.nextRun = nextRun
  }
}

/// A stored timer and when it fires.
public struct TimerEntry: Equatable, Sendable {
  /// The timer.
  public let timer: ServiceTimer
  /// When it fires, by the service's clock. A change of the clock moves this time, not the
  /// moment the timer fires.
  public let dueAt: Date
  /// The seconds left, counted in elapsed time.
  public let remainingSeconds: Int

  /// Creates an entry.
  public init(timer: ServiceTimer, dueAt: Date, remainingSeconds: Int) {
    self.timer = timer
    self.dueAt = dueAt
    self.remainingSeconds = remainingSeconds
  }
}

/// What happened at one run of a schedule or a timer. It is published as a numbered event.
public struct ScheduleRun: Equatable, Sendable {
  /// Whether a schedule or a timer ran.
  public enum Source: Equatable, Sendable {
    /// A schedule.
    case schedule
    /// A timer.
    case timer
  }

  /// What came of the run.
  public enum Outcome: Equatable, Sendable {
    /// The device acknowledged the command.
    case acknowledged
    /// The service wasn't running at the run time, or the clock moved past it, so the run didn't happen.
    case missed
    /// The modem or Hub isn't connected, so nothing was sent.
    case unavailable(ModemUnavailability)
    /// The service refused the command before sending it, such as a device that isn't linked. Nothing was sent.
    case refused(ServiceControlError)
    /// The command may have reached the device, and its outcome is unknown. It isn't repeated.
    case unknown
  }

  /// Whether a schedule or a timer ran.
  public let source: Source
  /// The schedule's or timer's identifier.
  public let id: String
  /// Its name.
  public let name: String
  /// The device the action was for.
  public let device: InsteonAddress
  /// What came of the run.
  public let outcome: Outcome
  /// When the service handled the run.
  public let firedAt: Date
  /// When the schedule runs next, or `nil` for a timer, a disabled schedule or one with no run to come.
  public let nextRun: Date?

  /// Creates a run.
  public init(source: Source, id: String, name: String, device: InsteonAddress, outcome: Outcome, firedAt: Date, nextRun: Date?) {
    self.source = source
    self.id = id
    self.name = name
    self.device = device
    self.outcome = outcome
    self.firedAt = firedAt
    self.nextRun = nextRun
  }
}

/// Why a change to the schedules or timers was refused.
public enum ScheduleError: Error, Equatable, Sendable {
  /// The schedule breaks a limit: its identifier, name, days, time, offset or action isn't one the service accepts.
  case invalidSchedule
  /// The timer breaks a limit: its identifier, name, delay or action isn't one the service accepts.
  case invalidTimer
  /// The action's device isn't one the service knows.
  case unknownDevice
  /// The device doesn't offer the action: it can't be switched, or doesn't dim.
  case unsupportedAction
  /// The schedule is relative to sunrise or sunset, and the service has no location.
  case locationMissing
  /// The network's time zone isn't in the host's time zone database, so the service can't work out a time of day.
  case timeZoneUnavailable
  /// No schedule has that identifier.
  case unknownSchedule
  /// No timer has that identifier.
  case unknownTimer
  /// The service already keeps ``ServiceSchedule/maximumCount`` schedules.
  case scheduleLimitReached
  /// The service already keeps ``ServiceTimer/maximumCount`` timers.
  case timerLimitReached
  /// The schedules couldn't be read or saved, so nothing changed.
  case notSaved
}

/// The role of a service that keeps schedules and timers.
public protocol ScheduleManaging: Sendable {
  /// The schedules, in the order they were added, each with its next run.
  func schedules() async throws -> [ScheduleEntry]
  /// Adds a schedule, or replaces the schedule with its identifier. The change takes effect at once, and a
  /// replacement keeps nothing of the old schedule's last run.
  func putSchedule(_ schedule: ServiceSchedule) async throws -> ScheduleEntry
  /// Removes a schedule, which stops at once.
  func removeSchedule(id: String) async throws
  /// The timers that haven't fired, in the order they were added.
  func timers() async throws -> [TimerEntry]
  /// Starts a timer, or restarts the timer with its identifier.
  func putTimer(_ timer: ServiceTimer) async throws -> TimerEntry
  /// Cancels a timer.
  func removeTimer(id: String) async throws
}

/// Where the network's place and time zone come from, and what the service remembers of them.
public struct ScheduleSettings: Equatable, Sendable {
  /// The IANA time zone's identifier, such as `America/Los_Angeles`, or `nil` for the host's.
  public var timeZoneIdentifier: String?
  /// The network's latitude and longitude, or `nil` when unknown. Without it, sunrise and sunset schedules are refused.
  public var location: GeographicCoordinate?

  /// Creates settings.
  public init(timeZoneIdentifier: String? = nil, location: GeographicCoordinate? = nil) {
    self.timeZoneIdentifier = timeZoneIdentifier
    self.location = location
  }

  /// These settings, with what they leave out taken from `other`.
  func filled(from other: ScheduleSettings) -> ScheduleSettings {
    ScheduleSettings(timeZoneIdentifier: timeZoneIdentifier ?? other.timeZoneIdentifier, location: location ?? other.location)
  }
}

/// A timer as it is stored: with the time it has left, so a restart picks up where it stopped.
public struct StoredTimer: Equatable, Sendable {
  /// The timer.
  public var timer: ServiceTimer
  /// The seconds it had left when it was stored.
  public var remainingSeconds: Double

  /// Creates a stored timer.
  public init(timer: ServiceTimer, remainingSeconds: Double) {
    self.timer = timer
    self.remainingSeconds = remainingSeconds
  }
}

/// Everything the service keeps of its schedules.
public struct StoredSchedules: Equatable, Sendable {
  /// The schedules, in the order they were added.
  public var schedules: [ServiceSchedule]
  /// The timers that haven't fired.
  public var timers: [StoredTimer]
  /// The last moment the service had looked for runs. A run between then and the next start is missed.
  public var checkedThrough: Date?
  /// The settings the service ran with last.
  public var settings: ScheduleSettings

  /// Creates a document.
  public init(schedules: [ServiceSchedule] = [], timers: [StoredTimer] = [], checkedThrough: Date? = nil, settings: ScheduleSettings = ScheduleSettings()) {
    self.schedules = schedules
    self.timers = timers
    self.checkedThrough = checkedThrough
    self.settings = settings
  }
}

/// Where the schedules and timers live between runs.
public protocol ScheduleStoring: Sendable {
  /// The stored document, or `nil` when none has been stored.
  func load() async throws -> StoredSchedules?
  /// Replaces the stored document.
  func save(_ stored: StoredSchedules) async throws
}

/// How the service's scheduler is set up.
public struct ScheduleConfiguration: Sendable {
  /// The time zone and location the host chose. What it leaves out comes from the stored settings.
  public var settings: ScheduleSettings
  /// Where schedules and timers are kept, if anywhere. Without it they last as long as the service.
  public var store: (any ScheduleStoring)?
  /// The clock that sleeps between runs and counts the time a timer has left. Its own, so what drives
  /// the service's reconnection never moves a schedule.
  public var clock: any Clock<Duration>
  /// The time zone to use when neither the host nor the stored settings name one.
  public var systemTimeZoneIdentifier: String
  /// Makes the source of sunrise and sunset for a location.
  public var sunTimes: @Sendable (GeographicCoordinate) -> any SunTimes

  /// Creates a configuration.
  public init(
    settings: ScheduleSettings = ScheduleSettings(),
    store: (any ScheduleStoring)? = nil,
    clock: any Clock<Duration> = ContinuousClock(),
    systemTimeZoneIdentifier: String = TimeZone.current.identifier,
    sunTimes: @escaping @Sendable (GeographicCoordinate) -> any SunTimes = { SolarCalculator(location: $0) }
  ) {
    self.settings = settings
    self.store = store
    self.clock = clock
    self.systemTimeZoneIdentifier = systemTimeZoneIdentifier
    self.sunTimes = sunTimes
  }
}

/// Something the service reports about its health beside readiness, which doesn't change what it can do.
public enum ServiceHealthNote: Equatable, Sendable {
  /// The configured time zone isn't in the host's time zone database, so schedules with a time of day are refused.
  case timeZoneUnavailable(String)
  /// The Hub's clock differs from the service's by this many seconds, more than a minute.
  case hubClockDrift(seconds: Int)
}
