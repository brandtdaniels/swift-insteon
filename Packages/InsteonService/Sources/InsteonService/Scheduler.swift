import Foundation
import InsteonProtocol
import InsteonScheduling

/// What the scheduler asks of the service that owns it.
struct ScheduleHost: Sendable {
  /// The cached devices, to check an action against.
  let devices: @Sendable () async throws -> [ServiceDevice]
  /// Sends one of the service's commands, the way a client's command is sent.
  let execute: @Sendable (ServiceCommand) async throws -> CommandReceipt
  /// Tells subscribers what a run came to.
  let publish: @Sendable (ScheduleRun) async -> Void
}

/// Runs the service's schedules and timers.
///
/// Time comes from three injected things: the wall clock (`now`), which says what time of day it
/// is; the `Clock` that sleeps and counts elapsed time, which times the timers; and the sunrise and
/// sunset source. The scheduler never writes a clock or a schedule to a Hub, modem or device. It
/// sends only the service's own commands.
///
/// A schedule's next run is found with ``ScheduleCalendar`` in the home's time zone. A run is on time
/// when the service handles it less than a minute late; a later one is missed and skipped, unless
/// the schedule asks to catch up and it is less than 15 minutes late. Looking again at the wall
/// clock at least every 30 seconds, the scheduler notices when the clock was set, and a run is
/// never repeated because the next run is always found after the last.
actor Scheduler {
  /// The longest the loop sleeps before it looks at the wall clock again.
  static let longestSleep = Duration.seconds(30)

  private struct RunningTimer {
    var timer: ServiceTimer
    /// The elapsed time, on the scheduler's own count, at which it fires.
    var deadline: Duration
  }

  private let configuration: ScheduleConfiguration
  private let host: ScheduleHost
  private let elapsed: ElapsedClock
  private let now: @Sendable () -> Date
  private let wakes: AsyncStream<Void>
  private let wake: AsyncStream<Void>.Continuation

  private var settings: ScheduleSettings
  private var scheduleList: [ServiceSchedule] = []
  private var nextRuns: [String: Date] = [:]
  private var timerList: [RunningTimer] = []
  private var checkedThrough: Date?
  private var loaded = false
  private var isEditing = false
  private var waitingToEdit: [CheckedContinuation<Void, Never>] = []

  init(configuration: ScheduleConfiguration, now: @escaping @Sendable () -> Date, host: ScheduleHost) {
    self.configuration = configuration
    self.host = host
    self.now = now
    self.elapsed = ElapsedClock(configuration.clock)
    self.settings = configuration.settings
    (wakes, wake) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
  }

  // MARK: Settings

  /// The time zone schedules are worked out in, or `nil` when the configured one isn't in the host's database.
  private var timeZone: TimeZone? { TimeZone(identifier: timeZoneIdentifier) }

  private var timeZoneIdentifier: String { settings.timeZoneIdentifier ?? configuration.systemTimeZoneIdentifier }

  /// The time zone schedules are worked out in, or `nil` when the host doesn't have it.
  var homeTimeZone: TimeZone? { timeZone }

  /// What the scheduler reports about itself.
  var notes: [ServiceHealthNote] {
    timeZone == nil ? [.timeZoneUnavailable(timeZoneIdentifier)] : []
  }

  private var calendar: ScheduleCalendar? {
    guard let timeZone else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return ScheduleCalendar(calendar: calendar, sunTimes: settings.location.map(configuration.sunTimes))
  }

  private func nextRun(of schedule: ServiceSchedule, after date: Date) -> Date? {
    guard schedule.isEnabled else { return nil }
    return calendar?.nextRun(of: schedule.when, after: date)
  }

  // MARK: Loading

  /// Reads what was stored, once, and works out every schedule's next run in the current time zone.
  ///
  /// Until it succeeds the scheduler has nothing and refuses changes, so a file it can't read is never overwritten.
  func load() async throws {
    guard !loaded else { return }
    let stored: StoredSchedules?
    do { stored = try await configuration.store?.load() } catch { throw ScheduleError.notSaved }
    guard !loaded else { return }
    let start = now()
    settings = configuration.settings.filled(from: stored?.settings ?? ScheduleSettings())
    scheduleList = stored?.schedules ?? []
    // A saved moment in the future means the clock was set back; looking from the current time loses no run.
    checkedThrough = min(stored?.checkedThrough ?? start, start)
    for schedule in scheduleList { nextRuns[schedule.id] = nextRun(of: schedule, after: checkedThrough ?? start) }
    let current = elapsed.now
    timerList = (stored?.timers ?? []).map { RunningTimer(timer: $0.timer, deadline: current + .seconds(max(0, $0.remainingSeconds))) }
    loaded = true
    // The settings the host chose are remembered for the next start.
    if (stored?.settings ?? ScheduleSettings()) != settings { try? await save() }
    wake.yield()
  }

  // MARK: Editing

  func schedules() async throws -> [ScheduleEntry] {
    try await load()
    return scheduleList.map { ScheduleEntry(schedule: $0, nextRun: nextRuns[$0.id]) }
  }

  func timers() async throws -> [TimerEntry] {
    try await load()
    return timerList.map(entry)
  }

  func putSchedule(_ schedule: ServiceSchedule) async throws -> ScheduleEntry {
    try await load()
    return try await editing {
      let schedule = try await validated(schedule)
      guard scheduleList.contains(where: { $0.id == schedule.id }) || scheduleList.count < ServiceSchedule.maximumCount else { throw ScheduleError.scheduleLimitReached }
      var updated = scheduleList
      if let index = updated.firstIndex(where: { $0.id == schedule.id }) { updated[index] = schedule } else { updated.append(schedule) }
      let start = now()
      let next = nextRun(of: schedule, after: start)
      try await save(schedules: updated, checkedThrough: start)
      scheduleList = updated
      nextRuns[schedule.id] = next
      checkedThrough = start
      wake.yield()
      return ScheduleEntry(schedule: schedule, nextRun: next)
    }
  }

  func removeSchedule(id: String) async throws {
    try await load()
    try await editing {
      guard scheduleList.contains(where: { $0.id == id }) else { throw ScheduleError.unknownSchedule }
      let updated = scheduleList.filter { $0.id != id }
      let start = now()
      try await save(schedules: updated, checkedThrough: start)
      scheduleList = updated
      nextRuns[id] = nil
      checkedThrough = start
      wake.yield()
    }
  }

  func putTimer(_ timer: ServiceTimer) async throws -> TimerEntry {
    try await load()
    return try await editing {
      let timer = try await validated(timer)
      guard timerList.contains(where: { $0.timer.id == timer.id }) || timerList.count < ServiceTimer.maximumCount else { throw ScheduleError.timerLimitReached }
      let running = RunningTimer(timer: timer, deadline: elapsed.now + .seconds(timer.delaySeconds))
      var updated = timerList
      if let index = updated.firstIndex(where: { $0.timer.id == timer.id }) { updated[index] = running } else { updated.append(running) }
      try await save(timers: updated)
      timerList = updated
      wake.yield()
      return entry(running)
    }
  }

  func removeTimer(id: String) async throws {
    try await load()
    try await editing {
      guard timerList.contains(where: { $0.timer.id == id }) else { throw ScheduleError.unknownTimer }
      let updated = timerList.filter { $0.timer.id != id }
      try await save(timers: updated)
      timerList = updated
      wake.yield()
    }
  }

  private func entry(_ running: RunningTimer) -> TimerEntry {
    let seconds = max(.zero, running.deadline - elapsed.now).inSeconds
    return TimerEntry(timer: running.timer, dueAt: now().addingTimeInterval(seconds), remainingSeconds: Int(seconds.rounded(.up)))
  }

  /// Runs one change at a time, so two changes never start from the same list and lose one of them.
  private func editing<Result>(_ work: () async throws -> Result) async rethrows -> Result {
    if isEditing { await withCheckedContinuation { waitingToEdit.append($0) } } else { isEditing = true }
    // The next waiter inherits the turn, so a new caller can't slip in between.
    defer { if waitingToEdit.isEmpty { isEditing = false } else { waitingToEdit.removeFirst().resume() } }
    return try await work()
  }

  // MARK: Validation

  private func validated(_ schedule: ServiceSchedule) async throws -> ServiceSchedule {
    var schedule = schedule
    guard Self.isIdentifier(schedule.id), let name = Self.cleanName(schedule.name) else { throw ScheduleError.invalidSchedule }
    schedule.name = name
    guard !schedule.when.weekdays.isEmpty else { throw ScheduleError.invalidSchedule }
    switch schedule.when.time {
    case let .clock(hour, minute):
      guard (0...23).contains(hour), (0...59).contains(minute) else { throw ScheduleError.invalidSchedule }
    case let .sunrise(offset), let .sunset(offset):
      guard abs(offset.components.seconds) <= Int64(ServiceSchedule.longestOffsetSeconds), offset.components.attoseconds == 0 else { throw ScheduleError.invalidSchedule }
      guard settings.location != nil else { throw ScheduleError.locationMissing }
    }
    guard timeZone != nil else { throw ScheduleError.timeZoneUnavailable }
    try await check(schedule.action, as: ScheduleError.invalidSchedule)
    return schedule
  }

  private func validated(_ timer: ServiceTimer) async throws -> ServiceTimer {
    var timer = timer
    guard Self.isIdentifier(timer.id), let name = Self.cleanName(timer.name), (1...ServiceTimer.longestDelaySeconds).contains(timer.delaySeconds) else { throw ScheduleError.invalidTimer }
    timer.name = name
    try await check(timer.action, as: ScheduleError.invalidTimer)
    return timer
  }

  /// Checks an action against the cached devices: the device is known, and offers the control.
  private func check(_ action: ScheduledAction, as invalid: ScheduleError) async throws {
    if case let .on(level) = action.kind, let level, !(0...100).contains(level) { throw invalid }
    let devices = try await host.devices()
    guard let device = devices.first(where: { $0.address == action.device }) else { throw ScheduleError.unknownDevice }
    guard device.canTurnOnAndOff else { throw ScheduleError.unsupportedAction }
    if case let .on(level) = action.kind, level != nil, !device.canDim { throw ScheduleError.unsupportedAction }
  }

  private static func isIdentifier(_ text: String) -> Bool {
    (1...ServiceSchedule.longestTextLength).contains(text.count) && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
  }

  private static func cleanName(_ text: String) -> String? {
    let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (1...ServiceSchedule.longestTextLength).contains(name.count), !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
    return name
  }

  // MARK: Saving

  private func save(schedules: [ServiceSchedule]? = nil, timers: [RunningTimer]? = nil, checkedThrough: Date? = nil) async throws {
    guard let store = configuration.store else { return }
    let stored = StoredSchedules(
      schedules: schedules ?? scheduleList,
      timers: (timers ?? timerList).map(storedTimer),
      checkedThrough: checkedThrough ?? self.checkedThrough,
      settings: settings
    )
    do { try await store.save(stored) } catch { throw ScheduleError.notSaved }
  }

  private func storedTimer(_ running: RunningTimer) -> StoredTimer {
    StoredTimer(timer: running.timer, remainingSeconds: max(.zero, running.deadline - elapsed.now).inSeconds)
  }

  // MARK: Running

  /// Looks for what is due, then sleeps until the next run, a timer, an edit or 30 seconds pass, until canceled.
  /// On the way out it saves the time every timer has left, so the next run picks up where this one stopped.
  func run() async {
    try? await load()
    while !Task.isCancelled {
      await tick()
      do { try await sleepUntilNeeded() } catch { break }
    }
    try? await save(checkedThrough: now())
  }

  private func sleepUntilNeeded() async throws {
    var wait = Self.longestSleep
    let start = now()
    for schedule in scheduleList where schedule.isEnabled {
      guard let run = nextRuns[schedule.id] else { continue }
      wait = min(wait, Duration.seconds(max(0, run.timeIntervalSince(start))))
    }
    let current = elapsed.now
    for running in timerList { wait = min(wait, max(.zero, running.deadline - current)) }
    // A little past the moment, so what is due is due when the loop looks.
    let pause = max(wait, .milliseconds(1))
    let sleep = elapsed.sleep
    let wakes = wakes
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask { try await sleep(pause) }
      group.addTask {
        var iterator = wakes.makeAsyncIterator()
        _ = await iterator.next()
      }
      _ = try await group.next()
      group.cancelAll()
    }
  }

  /// Handles every run and timer that is due.
  func tick() async {
    // A file that can't be read leaves the scheduler empty; a change reports why.
    try? await load()
    guard loaded else { return }
    for schedule in scheduleList { await handleDue(schedule) }
    await handleDueTimers()
  }

  private func handleDue(_ schedule: ServiceSchedule) async {
    // An edit since the pass began replaces the schedule; what was stored then is what runs.
    guard scheduleList.contains(schedule), schedule.isEnabled, var due = nextRuns[schedule.id] else { return }
    let start = now()
    guard due <= start else { return }
    let allowance = TimeInterval(schedule.catchUp ? ServiceSchedule.catchUpSeconds : ServiceSchedule.onTimeSeconds)
    var runs: [Date] = []
    var missed = false
    // A run's next is always after it, so no run repeats; a bound keeps a long stop from walking years of days.
    for _ in 0..<400 where due <= start {
      if start.timeIntervalSince(due) <= allowance { runs.append(due) } else { missed = true }
      guard let following = nextRun(of: schedule, after: due) else {
        nextRuns[schedule.id] = nil
        checkedThrough = start
        await report(schedule, runs: runs, missed: missed, at: start)
        return
      }
      due = following
    }
    nextRuns[schedule.id] = due
    checkedThrough = start
    await report(schedule, runs: runs, missed: missed, at: start)
  }

  /// Sends what is due, then publishes what came of it. The next run is stored first, so a change made while
  /// the command is out can't make it run twice.
  private func report(_ schedule: ServiceSchedule, runs: [Date], missed: Bool, at start: Date) async {
    if missed || !runs.isEmpty { try? await save(checkedThrough: start) }
    if missed {
      await host.publish(ScheduleRun(source: .schedule, id: schedule.id, name: schedule.name, device: schedule.action.device, outcome: .missed, firedAt: start, nextRun: nextRuns[schedule.id]))
    }
    for _ in runs {
      let outcome = await send(schedule.action)
      await host.publish(ScheduleRun(source: .schedule, id: schedule.id, name: schedule.name, device: schedule.action.device, outcome: outcome, firedAt: start, nextRun: nextRuns[schedule.id]))
    }
  }

  private func handleDueTimers() async {
    let current = elapsed.now
    let due = timerList.filter { $0.deadline <= current }
    guard !due.isEmpty else { return }
    timerList.removeAll { running in due.contains { $0.timer.id == running.timer.id } }
    // The timer is stored as gone before it fires, so a restart can't fire it again. A save that fails
    // still fires it: the person asked for the action, and the next edit stores the list again.
    try? await save()
    for running in due {
      let outcome = await send(running.timer.action)
      await host.publish(ScheduleRun(source: .timer, id: running.timer.id, name: running.timer.name, device: running.timer.action.device, outcome: outcome, firedAt: now(), nextRun: nil))
    }
  }

  /// Sends an action once. Whatever goes wrong is the outcome; nothing is repeated.
  private func send(_ action: ScheduledAction) async -> ScheduleRun.Outcome {
    do {
      _ = try await host.execute(action.command)
      return .acknowledged
    } catch ServiceControlError.modemUnavailable(let cause) {
      return .unavailable(cause)
    } catch let error as ServiceControlError {
      return .refused(error)
    } catch {
      return .unknown
    }
  }
}

/// A clock's elapsed time since it was made, and its sleep, without the clock's instant type.
struct ElapsedClock: Sendable {
  private let measure: @Sendable () -> Duration
  let sleep: @Sendable (Duration) async throws -> Void

  /// The time that has passed since this value was made.
  var now: Duration { measure() }

  init<C: Clock<Duration>>(_ clock: C) {
    let origin = clock.now
    measure = { origin.duration(to: clock.now) }
    sleep = { try await clock.sleep(for: $0) }
  }
}

private extension Duration {
  /// The duration in seconds, as a fraction.
  var inSeconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
