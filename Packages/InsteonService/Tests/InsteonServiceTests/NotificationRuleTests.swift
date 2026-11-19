import Foundation
import InsteonCore
import InsteonDeviceCatalog
import InsteonLinkingTestSupport
import InsteonProtocol
import InsteonTestSupport
import Testing
@testable import InsteonService

/// The service evaluates its notification rules against what devices report and publishes a numbered
/// `notification` event. Nothing waits on time: the device clock and the service's clock are moved by hand,
/// and each test reads the service's own events, which say what happened and in what order.
@Suite(.timeLimit(.minutes(1)))
struct NotificationRuleTests {
  let sensor = InsteonAddress(0x5C, 0x6D, 0x01)
  let neighbor = InsteonAddress(0x5C, 0x6D, 0x02)
  let start = Date(timeIntervalSince1970: 1_800_000_000)

  /// A made-up water sensor, whose model and identity no real product has.
  static let profile = DeviceProfile(
    model: "9201",
    name: "Example Water Sensor",
    identities: [DeviceIdentity(category: 0x10, subcategory: 0x7A)],
    groups: [
      DeviceProfile.Group(number: 1, name: "Dry", role: .controller),
      DeviceProfile.Group(number: 2, name: "Wet", role: .controller)
    ],
    capabilities: [
      .groupEvents([
        DeviceCapability.GroupEvent(group: 1, command1: 0x11, event: "dry"),
        DeviceCapability.GroupEvent(group: 2, command1: 0x11, event: "wet")
      ])
    ]
  )
  static let identity = ReportedIdentity(category: 0x10, subcategory: 0x7A, firmwareVersion: 0x45)

  private func leak(id: String = "basement-leak", name: String = "Basement leak", cooldown: Int = 0, enabled: Bool = true, detail: Bool = false) -> ServiceNotificationRule {
    ServiceNotificationRule(id: id, name: name, trigger: .event("wet", device: sensor), cooldownSeconds: cooldown, isEnabled: enabled, includesDetail: detail)
  }

  /// A running service over a scripted modem, the clocks that drive it and a reader of its events.
  private final class Harness: Sendable {
    let service: InsteonService
    let modem: InMemoryModem
    let deviceClock: TestClock
    let now: ManualNow
    let stop: AsyncStream<Void>.Continuation
    let finished: Task<Void, any Error>

    init(rules: (any NotificationRulePersisting)? = nil, sensor: InsteonAddress, now start: Date) {
      let modem = InMemoryModem()
      let link = ScriptedLink(modem: modem)
      let clock = TestClock()
      let now = ManualNow(start)
      let opener = ScriptedOpener([.connect(link)], catalog: DeviceCatalog(profiles: [NotificationRuleTests.profile]), clock: clock)
      let snapshot = NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [sensor: NotificationRuleTests.identity]))
      let network = DeviceNetwork(modem: InMemoryModem(), catalog: DeviceCatalog(profiles: [NotificationRuleTests.profile]), snapshot: snapshot)
      let service = InsteonService(network: network, opener: opener, reconnect: .never, now: { now.now }, notificationRules: rules)
      let (hostStopped, stop) = AsyncStream<Void>.makeStream()
      self.service = service
      self.modem = modem
      self.deviceClock = clock
      self.now = now
      self.stop = stop
      finished = Task { _ = try await service.run { for await _ in hostStopped {} } }
    }

    /// A device broadcasts `command1` to `group`, after the device clock has moved past the window in which a
    /// repeat counts as the same press.
    func broadcast(from device: InsteonAddress, group: UInt8, command1: UInt8 = 0x11) async {
      deviceClock.advance(by: .seconds(30))
      await modem.broadcastGroupCommand(from: device, group: group, command1: command1)
    }

    /// A device reports, and the call returns once the service has published the report and applied its rules to
    /// it: the service answers a question only after it has finished what it was doing, so a test can then move
    /// the clock or change the rules without racing the report. The result is what the reader saw up to the report.
    func report(from device: InsteonAddress, group: UInt8, command1: UInt8 = 0x11, to reader: inout Reader) async throws -> [ServiceEvent] {
      await broadcast(from: device, group: group, command1: command1)
      let events = try await reader.read { if case .groupCommand = $0 { true } else { false } }
      _ = await service.health()
      return events
    }

    /// Reports from a device no rule names, and returns what the reader saw up to that report: the notifications the
    /// earlier reports set off come before it, so a test that expects none still finishes.
    func settle(_ reader: inout Reader) async throws -> [ServiceEvent] {
      try await report(from: Self.bystander, group: 9, to: &reader)
    }

    static let bystander = InsteonAddress(0x5C, 0x6D, 0x09)

    func shutDown() async {
      stop.finish()
      _ = try? await finished.value
    }
  }

  /// Items of a service's sequenced events, read in order after the modem is connected.
  private struct Reader {
    var iterator: SequencedEvents.AsyncIterator

    /// The next event, skipping positions.
    mutating func next() async throws -> (event: ServiceEvent, cursor: EventCursor) {
      while let item = try await iterator.next() {
        if case let .event(event, cursor) = item { return (event, cursor) }
      }
      throw CancellationError()
    }

    /// Events up to and including the next one that satisfies `matches`.
    mutating func read(through matches: (ServiceEvent) -> Bool) async throws -> [ServiceEvent] {
      var events: [ServiceEvent] = []
      while true {
        let (event, _) = try await next()
        events.append(event)
        if matches(event) { return events }
      }
    }
  }

  private func subscribe(_ harness: Harness) async throws -> Reader {
    var iterator = await harness.service.sequencedEvents(after: nil).makeAsyncIterator()
    guard case let .position(cursor)? = try await iterator.next() else { throw CancellationError() }
    var reader = Reader(iterator: iterator)
    // The service announces the connection, as the run's first event, after it has subscribed to the modem, so a
    // report sent once the connection is announced is heard. A subscription that starts at the run's beginning is
    // told of it; one that starts later missed it.
    if cursor.sequence == 0 { _ = try await reader.read { $0 == .modemReconnected } }
    return reader
  }

  private func kind(_ event: ServiceEvent) -> String {
    switch event {
    case .groupCommand: "report"
    case .notification: "notification"
    default: "other"
    }
  }

  private func isNotification(_ event: ServiceEvent) -> Bool {
    if case .notification = event { true } else { false }
  }

  private func isGroupCommand(_ event: ServiceEvent) -> Bool {
    if case .groupCommand = event { true } else { false }
  }

  // MARK: Firing

  @Test func aRuleFiresOnceWhenItsDeviceReportsTheEventItNames() async throws {
    let harness = Harness(sensor: sensor, now: start)
    try await harness.service.putNotificationRule(leak())
    var reader = try await subscribe(harness)
    _ = try await harness.report(from: sensor, group: 2, to: &reader)
    let events = try await harness.settle(&reader)
    #expect(events == [.notification(ServiceNotification(ruleID: "basement-leak", ruleName: "Basement leak", device: sensor, firedAt: start, eventName: nil)), events[1]])
    #expect(kind(events[1]) == "report")
    await harness.shutDown()
  }

  @Test func theNotificationCarriesNoDeviceDetailUnlessTheRuleOptsIn() async throws {
    let harness = Harness(sensor: sensor, now: start)
    try await harness.service.putNotificationRule(leak(id: "quiet"))
    try await harness.service.putNotificationRule(leak(id: "detailed", detail: true))
    var reader = try await subscribe(harness)
    _ = try await harness.report(from: sensor, group: 2, to: &reader)
    let events = try await harness.settle(&reader)
    let notes = events.compactMap { event -> ServiceNotification? in if case let .notification(note) = event { note } else { nil } }
    #expect(notes.map(\.ruleID) == ["quiet", "detailed"])
    #expect(notes.map(\.eventName) == [nil, "wet"])
    await harness.shutDown()
  }

  @Test func aDeviceOrEventTheRuleDoesNotNameFiresNothing() async throws {
    let harness = Harness(sensor: sensor, now: start)
    try await harness.service.putNotificationRule(leak())
    var reader = try await subscribe(harness)
    var log: [ServiceEvent] = []
    log += try await harness.report(from: sensor, group: 1, to: &reader)
    log += try await harness.report(from: neighbor, group: 2, to: &reader)
    // A report that does fire, so the log runs past the two that didn't.
    log += try await harness.report(from: sensor, group: 2, to: &reader)
    log += try await harness.settle(&reader)
    #expect(log.map(kind) == ["report", "report", "report", "notification", "report"])
    await harness.shutDown()
  }

  @Test func aGroupCommandRuleFiresOnTheCommandAndGroupItNames() async throws {
    let harness = Harness(sensor: sensor, now: start)
    try await harness.service.putNotificationRule(ServiceNotificationRule(id: "paddle", name: "Paddle", trigger: .groupCommand(command1: 0x13, group: 5, device: sensor)))
    var reader = try await subscribe(harness)
    var log: [ServiceEvent] = []
    log += try await harness.report(from: sensor, group: 5, command1: 0x11, to: &reader)
    log += try await harness.report(from: sensor, group: 6, command1: 0x13, to: &reader)
    log += try await harness.report(from: sensor, group: 5, command1: 0x13, to: &reader)
    log += try await harness.settle(&reader)
    #expect(log.map(kind) == ["report", "report", "report", "notification", "report"])
    #expect(log.first(where: isNotification) == .notification(ServiceNotification(ruleID: "paddle", ruleName: "Paddle", device: sensor, firedAt: start, eventName: nil)))
    await harness.shutDown()
  }

  // MARK: Cooldown

  @Test func aReportInsideTheCooldownPublishesNoSecondNotification() async throws {
    let harness = Harness(sensor: sensor, now: start)
    try await harness.service.putNotificationRule(leak(cooldown: 300))
    var reader = try await subscribe(harness)
    var log: [ServiceEvent] = []
    log += try await harness.report(from: sensor, group: 2, to: &reader)
    harness.now.advance(by: 120)
    log += try await harness.report(from: sensor, group: 2, to: &reader)
    harness.now.advance(by: 200)
    log += try await harness.report(from: sensor, group: 2, to: &reader)
    log += try await harness.settle(&reader)
    // The first report notifies, the one 120 seconds later is inside the cooldown, the one at 320 seconds is not.
    #expect(log.map(kind) == ["report", "notification", "report", "report", "notification", "report"])
    if case let .notification(note)? = log.last(where: isNotification) { #expect(note.firedAt == start.addingTimeInterval(320)) }
    await harness.shutDown()
  }

  @Test func renamingARuleKeepsItsCooldownRunning() async throws {
    let harness = Harness(sensor: sensor, now: start)
    try await harness.service.putNotificationRule(leak(cooldown: 300))
    var reader = try await subscribe(harness)
    var log: [ServiceEvent] = []
    log += try await harness.report(from: sensor, group: 2, to: &reader)
    try await harness.service.putNotificationRule(leak(name: "Basement water", cooldown: 300))
    harness.now.advance(by: 10)
    log += try await harness.report(from: sensor, group: 2, to: &reader)
    harness.now.advance(by: 400)
    log += try await harness.report(from: sensor, group: 2, to: &reader)
    log += try await harness.settle(&reader)
    #expect(log.map(kind) == ["report", "notification", "report", "report", "notification", "report"])
    if case let .notification(note)? = log.last(where: isNotification) { #expect(note.ruleName == "Basement water") }
    await harness.shutDown()
  }

  // MARK: Editing while running

  @Test func aRuleAddedWhileRunningFiresWithoutARestart() async throws {
    let harness = Harness(sensor: sensor, now: start)
    var reader = try await subscribe(harness)
    var log: [ServiceEvent] = []
    log += try await harness.report(from: sensor, group: 2, to: &reader)
    try await harness.service.putNotificationRule(leak())
    log += try await harness.report(from: sensor, group: 2, to: &reader)
    log += try await harness.settle(&reader)
    #expect(log.map(kind) == ["report", "report", "notification", "report"])
    await harness.shutDown()
  }

  @Test func aRemovedRuleStopsFiringAtOnce() async throws {
    let harness = Harness(sensor: sensor, now: start)
    try await harness.service.putNotificationRule(leak())
    var reader = try await subscribe(harness)
    try await harness.service.removeNotificationRule(id: "basement-leak")
    var log: [ServiceEvent] = []
    log += try await harness.report(from: sensor, group: 2, to: &reader)
    // A report of another device follows, so a notification for the first would be in the log.
    log += try await harness.report(from: neighbor, group: 2, to: &reader)
    #expect(log.map(kind) == ["report", "report"])
    await harness.shutDown()
  }

  @Test func aDisabledRuleStopsFiringAtOnceAndFiresAgainWhenEnabled() async throws {
    let harness = Harness(sensor: sensor, now: start)
    try await harness.service.putNotificationRule(leak())
    var reader = try await subscribe(harness)
    var log: [ServiceEvent] = []
    try await harness.service.putNotificationRule(leak(enabled: false))
    log += try await harness.report(from: sensor, group: 2, to: &reader)
    try await harness.service.putNotificationRule(leak(enabled: true))
    log += try await harness.report(from: sensor, group: 2, to: &reader)
    log += try await harness.settle(&reader)
    #expect(log.map(kind) == ["report", "report", "notification", "report"])
    await harness.shutDown()
  }

  // MARK: Numbering and resuming

  @Test func aNotificationIsNumberedAndRetainedLikeEveryOtherEvent() async throws {
    let harness = Harness(sensor: sensor, now: start)
    try await harness.service.putNotificationRule(leak())
    var reader = try await subscribe(harness)
    await harness.broadcast(from: sensor, group: 2)
    let (report, reportCursor) = try await reader.next()
    #expect(kind(report) == "report")
    // A report no rule names follows, so the next event exists whether or not the first report notified.
    await harness.broadcast(from: Harness.bystander, group: 9)
    let (event, noteCursor) = try await reader.next()
    #expect(isNotification(event))
    #expect(noteCursor.sequence == reportCursor.sequence + 1)
    #expect(noteCursor.runID == reportCursor.runID)

    // A client that saw only the report resumes and is given the notification it missed.
    var resumed = Reader(iterator: await harness.service.sequencedEvents(after: reportCursor).makeAsyncIterator())
    let replayed = try await resumed.next()
    #expect(replayed.event == event)
    #expect(replayed.cursor == noteCursor)
    await harness.shutDown()
  }

  @Test func aClientThatFellTooFarBehindIsToldToRefreshInsteadOfMissingNotificationsSilently() async throws {
    let harness = Harness(sensor: sensor, now: start)
    // A cooldown of a day lets the first report notify and the rest publish only their own events.
    try await harness.service.putNotificationRule(leak(cooldown: 86_400))
    var reader = try await subscribe(harness)
    await harness.broadcast(from: sensor, group: 2)
    let (_, first) = try await reader.next()
    for _ in 0..<InsteonService.retainedEventCount {
      _ = try await harness.report(from: sensor, group: 2, to: &reader)
    }
    var behind = await harness.service.sequencedEvents(after: first).makeAsyncIterator()
    guard case .gap(.tooOld, _)? = try await behind.next() else {
      Issue.record("expected a gap")
      await harness.shutDown()
      return
    }
    await harness.shutDown()
  }

  // MARK: Persistence

  @Test func rulesSurviveARestart() async throws {
    let storage = InMemoryNotificationRules()
    let first = Harness(rules: storage, sensor: sensor, now: start)
    try await first.service.putNotificationRule(leak(cooldown: 60))
    await first.shutDown()

    let second = Harness(rules: storage, sensor: sensor, now: start)
    #expect(try await second.service.notificationRules() == [leak(cooldown: 60)])
    var reader = try await subscribe(second)
    _ = try await second.report(from: sensor, group: 2, to: &reader)
    let events = try await second.settle(&reader)
    #expect(events.map(kind) == ["notification", "report"])
    await second.shutDown()
  }

  @Test func aRuleThatCouldNotBeSavedChangesNothing() async throws {
    let storage = InMemoryNotificationRules(failsToSave: true)
    let harness = Harness(rules: storage, sensor: sensor, now: start)
    await #expect(throws: NotificationRuleError.notSaved) { try await harness.service.putNotificationRule(leak()) }
    #expect(try await harness.service.notificationRules().isEmpty)
    var reader = try await subscribe(harness)
    var log: [ServiceEvent] = []
    log += try await harness.report(from: sensor, group: 2, to: &reader)
    // A report of another device follows the first, so a notification for the first would be in the log.
    log += try await harness.report(from: neighbor, group: 2, to: &reader)
    #expect(log.map(kind) == ["report", "report"])
    await harness.shutDown()
  }

  @Test func rulesThatCouldNotBeReadAreNeitherServedNorOverwritten() async throws {
    let storage = InMemoryNotificationRules(failsToLoad: true)
    let harness = Harness(rules: storage, sensor: sensor, now: start)
    await #expect(throws: NotificationRuleError.notSaved) { _ = try await harness.service.notificationRules() }
    await #expect(throws: NotificationRuleError.notSaved) { try await harness.service.putNotificationRule(leak()) }
    #expect(await storage.saves == 0)
    await harness.shutDown()
  }

  // MARK: Validation

  @Test(arguments: [
    ServiceNotificationRule(id: "", name: "Leak", trigger: .event("wet", device: InsteonAddress(0x5C, 0x6D, 0x01)), cooldownSeconds: 0, isEnabled: true, includesDetail: false),
    ServiceNotificationRule(id: "has space", name: "Leak", trigger: .event("wet", device: InsteonAddress(0x5C, 0x6D, 0x01)), cooldownSeconds: 0, isEnabled: true, includesDetail: false),
    ServiceNotificationRule(id: String(repeating: "a", count: 65), name: "Leak", trigger: .event("wet", device: InsteonAddress(0x5C, 0x6D, 0x01)), cooldownSeconds: 0, isEnabled: true, includesDetail: false),
    ServiceNotificationRule(id: "leak", name: "", trigger: .event("wet", device: InsteonAddress(0x5C, 0x6D, 0x01)), cooldownSeconds: 0, isEnabled: true, includesDetail: false),
    ServiceNotificationRule(id: "leak", name: "   ", trigger: .event("wet", device: InsteonAddress(0x5C, 0x6D, 0x01)), cooldownSeconds: 0, isEnabled: true, includesDetail: false),
    ServiceNotificationRule(id: "leak", name: String(repeating: "n", count: 65), trigger: .event("wet", device: InsteonAddress(0x5C, 0x6D, 0x01)), cooldownSeconds: 0, isEnabled: true, includesDetail: false),
    ServiceNotificationRule(id: "leak", name: "Bad\u{0007}name", trigger: .event("wet", device: InsteonAddress(0x5C, 0x6D, 0x01)), cooldownSeconds: 0, isEnabled: true, includesDetail: false),
    ServiceNotificationRule(id: "leak", name: "Leak", trigger: .event("wet", device: InsteonAddress(0x5C, 0x6D, 0x01)), cooldownSeconds: -1, isEnabled: true, includesDetail: false),
    ServiceNotificationRule(id: "leak", name: "Leak", trigger: .event("wet", device: InsteonAddress(0x5C, 0x6D, 0x01)), cooldownSeconds: ServiceNotificationRule.longestCooldownSeconds + 1, isEnabled: true, includesDetail: false),
    ServiceNotificationRule(id: "leak", name: "Leak", trigger: .event("Wet Floor", device: InsteonAddress(0x5C, 0x6D, 0x01)), cooldownSeconds: 0, isEnabled: true, includesDetail: false),
    ServiceNotificationRule(id: "leak", name: "Leak", trigger: .event("opened", device: InsteonAddress(0x5C, 0x6D, 0x01)), cooldownSeconds: 0, isEnabled: true, includesDetail: false),
    ServiceNotificationRule(id: "leak", name: "Leak", trigger: .groupCommand(command1: 0x11, group: 0, device: InsteonAddress(0x5C, 0x6D, 0x01)), cooldownSeconds: 0, isEnabled: true, includesDetail: false),
    ServiceNotificationRule(id: "leak", name: "Leak", trigger: .groupCommand(command1: 0x11, group: 256, device: InsteonAddress(0x5C, 0x6D, 0x01)), cooldownSeconds: 0, isEnabled: true, includesDetail: false)
  ])
  func aMalformedRuleIsRefusedAndNothingIsStored(_ rule: ServiceNotificationRule) async throws {
    let harness = Harness(sensor: sensor, now: start)
    await #expect(throws: NotificationRuleError.invalidRule) { try await harness.service.putNotificationRule(rule) }
    #expect(try await harness.service.notificationRules().isEmpty)
    await harness.shutDown()
  }

  @Test func aRuleForADeviceTheServiceDoesNotKnowIsRefused() async throws {
    let harness = Harness(sensor: sensor, now: start)
    let stranger = ServiceNotificationRule(id: "leak", name: "Leak", trigger: .event("wet", device: InsteonAddress(0x77, 0x77, 0x77)), cooldownSeconds: 0, isEnabled: true, includesDetail: false)
    await #expect(throws: NotificationRuleError.unknownDevice) { try await harness.service.putNotificationRule(stranger) }
    await harness.shutDown()
  }

  @Test func theServiceKeepsAtMostAFixedNumberOfRulesAndStillReplacesOne() async throws {
    let harness = Harness(sensor: sensor, now: start)
    for index in 0..<ServiceNotificationRule.maximumCount {
      try await harness.service.putNotificationRule(leak(id: "rule-\(index)", name: "Rule \(index)"))
    }
    await #expect(throws: NotificationRuleError.limitReached) { try await harness.service.putNotificationRule(leak(id: "one-too-many")) }
    try await harness.service.putNotificationRule(leak(id: "rule-0", name: "Renamed"))
    let rules = try await harness.service.notificationRules()
    #expect(rules.count == ServiceNotificationRule.maximumCount)
    #expect(rules.first { $0.id == "rule-0" }?.name == "Renamed")
    await harness.shutDown()
  }

  @Test func removingARuleThatDoesNotExistIsRefused() async throws {
    let harness = Harness(sensor: sensor, now: start)
    await #expect(throws: NotificationRuleError.unknownRule) { try await harness.service.removeNotificationRule(id: "nothing") }
    await harness.shutDown()
  }

  @Test func rulesAreListedInTheOrderTheyWereAdded() async throws {
    let harness = Harness(sensor: sensor, now: start)
    try await harness.service.putNotificationRule(leak(id: "b", name: "B"))
    try await harness.service.putNotificationRule(leak(id: "a", name: "A"))
    try await harness.service.putNotificationRule(leak(id: "b", name: "B again"))
    #expect(try await harness.service.notificationRules().map(\.id) == ["b", "a"])
    await harness.shutDown()
  }
}

/// Rules kept in memory, which can be made to fail.
actor InMemoryNotificationRules: NotificationRulePersisting {
  private var stored: [ServiceNotificationRule]?
  private let failsToLoad: Bool
  private let failsToSave: Bool
  private(set) var saves = 0

  init(failsToLoad: Bool = false, failsToSave: Bool = false) {
    self.failsToLoad = failsToLoad
    self.failsToSave = failsToSave
  }

  struct Failure: Error {}

  func load() throws -> [ServiceNotificationRule]? {
    if failsToLoad { throw Failure() }
    return stored
  }

  func save(_ rules: [ServiceNotificationRule]) throws {
    if failsToSave { throw Failure() }
    saves += 1
    stored = rules
  }
}

/// A date a test moves by hand.
final class ManualNow: @unchecked Sendable {
  private let lock = NSLock()
  private var date: Date

  init(_ date: Date) { self.date = date }

  var now: Date { lock.withLock { date } }

  func advance(by seconds: TimeInterval) { lock.withLock { date = date.addingTimeInterval(seconds) } }
}
