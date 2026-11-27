import Foundation
import InsteonCore
import InsteonDeviceCatalog
import InsteonModem
import InsteonNotifications
import InsteonProtocol

/// One persistent Insteon network's operations, monitoring and snapshot policy.
///
/// The service has no authentication, HTTP, HTML or wire-format responsibilities. Its one
/// admission gate applies to every operation that talks to hardware or saves the snapshot, for
/// all callers, regardless of transport. Reads of the cache never take it.
///
/// A service made with an opener owns the modem connection. While it runs it opens the modem,
/// reads its ALL-Link database, and monitors it. When the Hub or modem goes away, it keeps
/// serving the cached device list, refuses commands with
/// ``ServiceControlError/modemUnavailable(_:)`` before anything is sent, tells subscribers, and
/// opens the connection again after a capped, jittered delay. A command is never repeated by a
/// reconnection. A service made with a network leaves the connection to its host.
public actor InsteonService: InsteonServiceAPI {
  private var network: any ServedNetwork
  private let opener: any ServedNetworkOpening
  private let reconnect: ReconnectPolicy
  private let clock: any Clock<Duration>
  private let now: @Sendable () -> Date
  private let jitter: @Sendable () -> Double
  private let throughHub: Bool
  private let persistence: (any SnapshotPersisting)?
  private var busy = false
  private var running = false
  private var subscriptions: [WeakCommandSubscription] = []
  private let runID: String
  private var sequence: UInt64 = 0
  private var retained: [(sequence: UInt64, event: ServiceEvent)] = []
  private var connection: ModemConnectionState
  private var hasConnected: Bool
  private var lastExchange: Date?
  private var lastPoll: Date?
  private var informationUpdated: Date?
  private var attemptConnected = false
  private let notificationPersistence: (any NotificationRulePersisting)?
  private var ruleBook: NotificationRuleBook?
  private var rulesAreBeingEdited = false
  private var waitingToEditRules: [CheckedContinuation<Void, Never>] = []
  private let scheduling: ScheduleConfiguration
  private let tuning: ServiceTuning
  private let tuningSources: [String: TuningSource]
  private var scheduler: Scheduler?
  private var hubClock: (reported: String, readAt: Date)?
  /// Why the last refresh left each device unread. It lives in memory: the saved snapshot keeps
  /// no reason, so a restart reports ``BackupUnreadableReason/notCached`` until the next refresh.
  private var unreadReasons: [InsteonAddress: BackupUnreadableReason] = [:]
  /// The membership plans a client could apply, newest last, each with when it expires. They live in
  /// memory: a restart forgets them.
  private var openPlans: [(plan: SceneMembershipPlan, expiresAt: Date)] = []

  /// How long the service keeps a membership plan.
  static let planLifetime: TimeInterval = 300
  /// How many membership plans the service keeps at once. The oldest goes first.
  static let maximumOpenPlans = 8

  /// How many of the newest events the service keeps for a client to resume from. Memory is
  /// bounded by this count; nothing is kept on disk, and a restart forgets every event.
  public static let retainedEventCount = 256

  /// The latest snapshot outcome, independent of any device acknowledgment or reading.
  public private(set) var persistenceOutcome: PersistenceOutcome

  /// Creates a service for a network whose connection the host keeps open, and an optional
  /// persistence policy. The run ends if that connection does. `tuning` and `tuningSources` are as for
  /// ``init(network:opener:persistence:snapshotSavedAt:reconnect:clock:now:jitter:throughHub:runID:notificationRules:scheduling:tuning:tuningSources:)``.
  public init(network: DeviceNetwork, persistence: (any SnapshotPersisting)? = nil, clock: any Clock<Duration> = ContinuousClock(), now: @escaping @Sendable () -> Date = { Date() }, runID: String? = nil, scheduling: ScheduleConfiguration = ScheduleConfiguration(), tuning: ServiceTuning = .standard, tuningSources: [String: TuningSource] = [:]) {
    self.init(network: network, opener: FixedNetworkOpener(network: network), persistence: persistence, snapshotSavedAt: nil, reconnect: .never, clock: clock, now: now, jitter: { 0 }, isConnected: true, runID: runID, scheduling: scheduling, tuning: tuning, tuningSources: tuningSources)
  }

  /// Creates a service that opens and reopens its own modem connection.
  ///
  /// - Parameters:
  ///   - network: What the service serves until the first connection succeeds, such as
  ///     `DeviceNetwork/offline(catalog:snapshot:hub:)` over the saved snapshot.
  ///   - opener: Opens each connection.
  ///   - persistence: Where snapshots are saved, if anywhere.
  ///   - snapshotSavedAt: When the saved snapshot was written, if known.
  ///   - reconnect: How long to wait between attempts.
  ///   - clock: Times the waits between attempts.
  ///   - now: The current time.
  ///   - jitter: Random numbers from 0 up to, not including, 1 for the delay's jitter.
  ///   - runID: Names this run in event ids. Defaults to a random token, so every start has its own.
  ///   - throughHub: Whether the modem is reached through a Hub. A modem that doesn't answer is then
  ///     reported as ``ModemUnavailability/hubUnreachable``, because the Hub is what to check.
  ///   - notificationRules: Where the notification rules are kept, if anywhere. Without it they last as long as the service.
  ///   - scheduling: The network's time zone and location and where schedules and timers are kept. Schedules and timers run on `clock` and `now`.
  ///   - tuning: How long scene runs wait. Check it with ``ServiceTuning/validated()`` first; the service uses it as given.
  ///   - tuningSources: Where each tuning value came from, by name such as `scenes.echoWaitMs`, for health. A value with no entry is a default.
  public init(
    network: DeviceNetwork,
    opener: any ServedNetworkOpening,
    persistence: (any SnapshotPersisting)? = nil,
    snapshotSavedAt: Date? = nil,
    reconnect: ReconnectPolicy = .standard,
    clock: any Clock<Duration> = ContinuousClock(),
    now: @escaping @Sendable () -> Date = { Date() },
    jitter: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) },
    throughHub: Bool = false,
    runID: String? = nil,
    notificationRules: (any NotificationRulePersisting)? = nil,
    scheduling: ScheduleConfiguration = ScheduleConfiguration(),
    tuning: ServiceTuning = .standard,
    tuningSources: [String: TuningSource] = [:]
  ) {
    self.init(network: network, opener: opener, persistence: persistence, snapshotSavedAt: snapshotSavedAt, reconnect: reconnect, clock: clock, now: now, jitter: jitter, isConnected: false, throughHub: throughHub, runID: runID, notificationRules: notificationRules, scheduling: scheduling, tuning: tuning, tuningSources: tuningSources)
  }

  private init(
    network: DeviceNetwork,
    opener: any ServedNetworkOpening,
    persistence: (any SnapshotPersisting)?,
    snapshotSavedAt: Date?,
    reconnect: ReconnectPolicy,
    clock: any Clock<Duration>,
    now: @escaping @Sendable () -> Date,
    jitter: @escaping @Sendable () -> Double,
    isConnected: Bool,
    throughHub: Bool = false,
    runID: String? = nil,
    notificationRules: (any NotificationRulePersisting)? = nil,
    scheduling: ScheduleConfiguration = ScheduleConfiguration(),
    tuning: ServiceTuning = .standard,
    tuningSources: [String: TuningSource] = [:]
  ) {
    self.tuning = tuning
    self.tuningSources = tuningSources
    self.scheduling = scheduling
    self.notificationPersistence = notificationRules
    self.network = ModemServedNetwork(network: network)
    self.opener = opener
    self.reconnect = reconnect
    self.clock = clock
    self.now = now
    self.jitter = jitter
    self.throughHub = throughHub
    self.runID = runID ?? Self.randomRunID()
    self.persistence = persistence
    self.persistenceOutcome = persistence == nil ? .notConfigured : .notAttempted
    self.connection = isConnected ? .connected : .unavailable(.connecting)
    self.hasConnected = isConnected
    self.informationUpdated = snapshotSavedAt
  }

  /// Lists cached devices, without asking hardware, whether or not the modem is connected.
  /// Unidentified devices have no switching controls until identified.
  ///
  /// A read never takes the admission gate: it answers from the cache while an operation is in
  /// flight, and it never makes an operation refuse.
  public func devices() async throws -> [ServiceDevice] {
    let network = network
    let snapshot = await network.snapshot()
    var result: [ServiceDevice] = []
    for address in Self.addresses(in: snapshot) {
      let known = await network.registeredDevice(address)
      let capabilities = known == nil ? nil : try await network.operations(of: address).capabilities()
      result.append(ServiceDevice(address: address, productName: capabilities?.productName, canTurnOnAndOff: capabilities?.canTurnOnAndOff ?? false, canDim: capabilities?.canDim ?? false, value: snapshot.devices[address]?.level, lastAnsweredAt: snapshot.devices[address]?.lastSeen))
    }
    return result
  }

  /// A backup of what the service has cached, without asking hardware and without taking the
  /// admission gate, whether or not the modem is connected.
  public func networkBackup() async -> NetworkBackup {
    let network = network
    return await NetworkBackupReader.backup(from: await network.snapshot(), modem: await network.modemIdentity(), catalog: await network.catalog(), createdAt: now())
  }

  /// The scenes of the network, from the ALL-Link databases the service has cached, without asking
  /// hardware and without taking the admission gate, whether or not the modem is connected.
  public func scenes() async -> SceneListing {
    await listing()
  }

  /// The listing of the cached databases, with the reason the last refresh left each unreadable
  /// device unread in place of "not cached".
  private func listing() async -> SceneListing {
    var listing = SceneListing(await networkBackup())
    for address in listing.unreadable where listing.unreadableReasons[address] == .notCached {
      if let reason = unreadReasons[address] { listing.unreadableReasons[address] = reason }
    }
    return listing
  }

  /// Reads the ALL-Link databases of the modem and of each device from the hardware, saves a
  /// checkpoint, and lists the scenes from what was read. Nothing is written to the modem or to a
  /// device.
  ///
  /// It takes the admission gate the way ``execute(_:)`` does and holds it for the whole read, so
  /// another operation is refused as ``ServiceControlError/busy`` and nothing is queued. While
  /// the modem isn't connected it throws ``ServiceControlError/modemUnavailable(_:)`` before
  /// sending anything. A device that doesn't answer is listed as unreadable. A refresh that fails
  /// partway saves a checkpoint of what it read, then throws the original error.
  public func refreshScenes() async throws -> SceneListing {
    guard !busy else { throw ServiceControlError.busy }
    busy = true
    defer { busy = false }
    if case let .unavailable(cause) = connection { throw ServiceControlError.modemUnavailable(cause) }
    do {
      unreadReasons = try await network.refreshDatabases()
    } catch {
      // What was read before the failure is already in the cache, so it is saved too.
      lastExchange = now()
      _ = await persist()
      throw error
    }
    lastExchange = now()
    _ = await persist()
    return await listing()
  }

  /// Runs a scene the modem controls. It takes the admission gate the way ``execute(_:)`` does, checks the
  /// scene against the listing the service holds, and sends the group once. A run that fails is never
  /// repeated, and publishes no event.
  public func runScene(_ command: SceneCommand) async throws -> SceneReceipt {
    guard !busy else { throw ServiceControlError.busy }
    busy = true
    defer { busy = false }
    if case let .unavailable(cause) = connection { throw ServiceControlError.modemUnavailable(cause) }
    guard let scene = await listing().scenes.first(where: { $0.number == command.number && $0.isWritable }) else { throw ServiceControlError.unknownScene }
    guard !scene.members.isEmpty else { throw ServiceControlError.sceneEmpty }
    // A run that went out has the count of the modem's controller records in its result. A failure has no
    // result, so the listing's members stand in, each device once. A responder the listing could not read is
    // not in it, so the two counts can differ.
    let listedMembers = Set(scene.members.map(\.address)).count
    let result: SceneResult
    do {
      let wait = AllLinkCleanupWait(echo: tuning.scenes.echoWait, quietPeriod: tuning.scenes.cleanupQuietPeriod, cap: tuning.scenes.cleanupCap)
      result = try await network.runScene(group: AllLinkGroupNumber(rawValue: command.number), turningOn: command.action == .on, wait: wait)
    } catch let ModemError.rejected(refused) {
      // The modem refused the command, so nothing went out.
      throw ModemError.rejected(refused)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      // The command may have gone out and the modem stopped answering, so the members may have changed.
      // Say so, so a client reads them again, and save what the service knows. The failure is still the answer.
      lastExchange = now()
      let saved = await persist()
      let unknown = SceneReceipt(scene: command.number, action: command.action, acknowledged: [], unacknowledged: [], isComplete: false, responderCount: listedMembers, persistence: saved)
      publish(.scene(SceneRun(number: command.number, name: nil, source: .api, action: command.action, receipt: unknown, firedAt: now())))
      throw error
    }
    lastExchange = now()
    let saved = await persist()
    let receipt = SceneReceipt(scene: command.number, action: command.action, acknowledged: result.acknowledged, unacknowledged: result.unacknowledged, isComplete: result.isComplete, responderCount: result.responderCount, persistence: saved, statusReportAfter: result.statusReportAfter, failureReportedAfter: result.failureReportedAfter)
    // No suspension between publishing and releasing admission in defer, as for a device command.
    publish(.scene(SceneRun(number: command.number, name: nil, source: .api, action: command.action, receipt: receipt, firedAt: now())))
    return receipt
  }

  public func planSceneMembership(_ change: SceneMembershipChange) async throws -> SceneMembershipPlanReceipt {
    let network = network
    guard network.servesDatabases else { throw ServiceControlError.databasesUnavailable }
    let backup = await networkBackup()
    // A group a device controls is read only. A number nothing controls is a scene to create.
    let scenes = SceneListing(backup).scenes.filter { $0.number == change.scene }
    if !scenes.isEmpty, !scenes.contains(where: \.isWritable) { throw ServiceControlError.unknownScene }
    var registered: [InsteonAddress: RegisteredDevice] = [:]
    for address in change.additions.map(\.device) + change.removals {
      if let device = await network.registeredDevice(address) { registered[address] = device }
    }
    var modemLinkData: ModemLinkData?
    if let modem = await network.modemIdentity(), let identity = modem.identity {
      modemLinkData = await network.catalog()?.profile(category: identity.category, subcategory: identity.subcategory, firmwareVersion: identity.firmwareVersion)?.modemLinkData
    }
    let plan = SceneMembershipPlanner.plan(change, from: backup, devices: registered, modemLinkData: modemLinkData)
    let expiresAt = now().addingTimeInterval(Self.planLifetime)
    keepOpenPlans(adding: plan.isApplicable ? (plan, expiresAt) : nil)
    return SceneMembershipPlanReceipt(plan: plan, expiresAt: expiresAt)
  }

  /// The plan with this identifier, if the service still keeps it: one it made less than five minutes
  /// ago that could be applied.
  func openSceneMembershipPlan(_ id: String) -> SceneMembershipPlan? {
    keepOpenPlans(adding: nil)
    return openPlans.first { $0.plan.id == id }?.plan
  }

  /// Drops the plans that expired and the oldest beyond the limit, then keeps `added`. A plan made
  /// again takes its place as the newest, with its new expiry.
  private func keepOpenPlans(adding added: (SceneMembershipPlan, Date)?) {
    let moment = now()
    openPlans.removeAll { $0.expiresAt <= moment }
    if let added {
      openPlans.removeAll { $0.plan.id == added.0.id }
      openPlans.append((added.0, added.1))
      if openPlans.count > Self.maximumOpenPlans { openPlans.removeFirst(openPlans.count - Self.maximumOpenPlans) }
    }
  }

  /// What a scene member's link data bytes mean, from the catalog and the identity the service
  /// has recorded for the device, without asking hardware.
  public func meaning(ofMemberData data: [UInt8], of device: InsteonAddress, group: UInt8) async -> LinkDataMeaning? {
    await network.registeredDevice(device)?.info.meaning(ofResponderData: data, group: group)
  }

  /// Executes an operation through InsteonCore and preserves its result if persistence fails.
  /// While the modem isn't connected it throws ``ServiceControlError/modemUnavailable(_:)``
  /// before sending anything. A device that isn't identified or isn't linked to the modem throws
  /// ``ServiceControlError/notIdentified`` or ``ServiceControlError/notLinked``. A failed
  /// operation is never repeated.
  public func execute(_ command: ServiceCommand) async throws -> CommandReceipt {
    guard !busy else { throw ServiceControlError.busy }
    busy = true
    defer { busy = false }
    let network = network
    guard Self.addresses(in: await network.snapshot()).contains(command.address) else { throw ServiceControlError.unknownDevice }
    if let level = command.levelPercent, command.action != .on || !(0...100).contains(level) { throw ServiceControlError.invalidLevel }
    if case let .unavailable(cause) = connection { throw ServiceControlError.modemUnavailable(cause) }
    let device = network.operations(of: command.address)
    let outcome: CommandReceipt.Outcome
    let status: DeviceStatus?
    do {
      switch command.action {
      case .identify:
        try await network.identifyDevice(command.address)
        outcome = .read; status = nil
      case .status:
        do {
          status = try await device.status()
        } catch ModemError.deviceTimedOut {
          // A device that never reported what it is and doesn't answer a read has no identity to act on.
          if await network.registeredDevice(command.address) == nil { throw ServiceControlError.notIdentified }
          throw ModemError.deviceTimedOut(command.address)
        }
        outcome = .read
      case .on, .off:
        let capabilities = try await device.capabilities()
        guard capabilities.isIdentified else { throw ServiceControlError.notIdentified }
        guard capabilities.canTurnOnAndOff else { throw ServiceControlError.unsupportedControl }
        if command.levelPercent != nil, !capabilities.canDim { throw ServiceControlError.invalidLevel }
        if command.action == .on { _ = try await device.turnOn(level: command.levelPercent) }
        else { try await device.turnOff() }
        outcome = .acknowledged; status = nil
      }
    } catch DeviceControlError.notLinked {
      throw ServiceControlError.notLinked
    } catch DeviceControlError.notIdentified {
      throw ServiceControlError.notIdentified
    } catch let ModemError.deviceRejected(_, reason) where reason == .notLinked {
      throw ServiceControlError.notLinked
    }
    lastExchange = now()
    let saved = await persist()
    let receipt = CommandReceipt(address: command.address, outcome: outcome, status: status, persistence: saved)
    // No suspension between publishing and releasing admission in defer. A subscriber
    // can query the updated cache as soon as its actor call is served.
    publish(.commandCompleted(command, receipt))
    return receipt
  }

  /// Saves a snapshot through the same admission gate as operations. Storage failure is data.
  public func checkpoint() async throws -> PersistenceOutcome {
    guard !busy else { throw ServiceControlError.busy }
    busy = true
    defer { busy = false }
    return await persist()
  }

  // MARK: Notification rules

  /// The rules, in the order they were added.
  ///
  /// - Throws: ``NotificationRuleError/notSaved`` when the stored rules can't be read.
  public func notificationRules() async throws -> [ServiceNotificationRule] {
    try await loadNotificationRules()
    return ruleBook?.rules ?? []
  }

  /// Validates a rule and stores it, so it applies to the next device report.
  ///
  /// A rule with the identifier of an existing one replaces it, and keeps its cooldown running when the trigger
  /// is the same. The rules are saved before they change, so a failure to save changes nothing.
  ///
  /// - Throws: ``NotificationRuleError``.
  public func putNotificationRule(_ rule: ServiceNotificationRule) async throws {
    try await loadNotificationRules()
    try await editingRules {
      let rule = try await validated(rule)
      var updated = ruleBook ?? NotificationRuleBook()
      guard updated.contains(rule.id) || updated.rules.count < ServiceNotificationRule.maximumCount else { throw NotificationRuleError.limitReached }
      updated.put(rule)
      try await save(updated)
      ruleBook = updated
    }
  }

  /// Removes a rule, which stops firing at once.
  ///
  /// - Throws: ``NotificationRuleError/unknownRule`` when no rule has the identifier.
  public func removeNotificationRule(id: String) async throws {
    try await loadNotificationRules()
    try await editingRules {
      var updated = ruleBook ?? NotificationRuleBook()
      guard updated.contains(id) else { throw NotificationRuleError.unknownRule }
      updated.remove(id)
      try await save(updated)
      ruleBook = updated
    }
  }

  /// Reads the stored rules once. Until it succeeds, the service has no rules and refuses to change them.
  public func loadNotificationRules() async throws {
    guard ruleBook == nil else { return }
    let stored: [ServiceNotificationRule]?
    do { stored = try await notificationPersistence?.load() } catch { throw NotificationRuleError.notSaved }
    if ruleBook == nil { ruleBook = NotificationRuleBook(rules: stored ?? []) }
  }

  private func save(_ book: NotificationRuleBook) async throws {
    do { try await notificationPersistence?.save(book.rules) } catch { throw NotificationRuleError.notSaved }
  }

  /// Runs a change to the rules alone, so two changes never start from the same rules and lose one of them.
  private func editingRules<Result>(_ work: () async throws -> Result) async rethrows -> Result {
    if rulesAreBeingEdited { await withCheckedContinuation { waitingToEditRules.append($0) } } else { rulesAreBeingEdited = true }
    // The next waiter inherits the turn, so a new caller can't slip in between.
    defer { if waitingToEditRules.isEmpty { rulesAreBeingEdited = false } else { waitingToEditRules.removeFirst().resume() } }
    return try await work()
  }

  private func validated(_ rule: ServiceNotificationRule) async throws -> ServiceNotificationRule {
    var rule = rule
    let limit = ServiceNotificationRule.longestTextLength
    guard (1...limit).contains(rule.id.count), rule.id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }) else { throw NotificationRuleError.invalidRule }
    rule.name = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (1...limit).contains(rule.name.count), !rule.name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw NotificationRuleError.invalidRule }
    guard (0...ServiceNotificationRule.longestCooldownSeconds).contains(rule.cooldownSeconds) else { throw NotificationRuleError.invalidRule }
    switch rule.trigger {
    case let .event(name, _):
      guard (1...limit).contains(name.count), name.first?.isLowercase == true, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { throw NotificationRuleError.invalidRule }
    case let .groupCommand(_, group, _):
      guard (1...255).contains(group) else { throw NotificationRuleError.invalidRule }
    }
    let network = network
    guard Self.addresses(in: await network.snapshot()).contains(rule.trigger.device) else { throw NotificationRuleError.unknownDevice }
    if case let .event(name, device) = rule.trigger, let names = await eventNames(of: device, in: network), !names.contains(name) { throw NotificationRuleError.invalidRule }
    return rule
  }

  /// The events the catalog says a device's product reports, or `nil` when the catalog has no profile for the device.
  private func eventNames(of device: InsteonAddress, in network: any ServedNetwork) async -> Set<String>? {
    guard let identity = await network.registeredDevice(device)?.identity, let catalog = await network.catalog(),
          let profile = catalog.profile(category: identity.category, subcategory: identity.subcategory, firmwareVersion: identity.firmwareVersion) else { return nil }
    var names: Set<String> = []
    for case let .groupEvents(events) in profile.capabilities { names.formUnion(events.map(\.event.rawValue)) }
    return names
  }

  private func evaluateNotificationRules(for event: DeviceMonitorEvent) {
    guard var book = ruleBook, !book.rules.isEmpty, let event = DeviceEvent(event) else { return }
    let fired = book.notifications(for: event, at: now())
    ruleBook = book
    for notification in fired { publish(.notification(notification)) }
  }

  // MARK: Schedules and timers

  /// The scheduler, made on first use. It reaches back to the service through weak references, so
  /// neither keeps the other alive.
  private func schedulerInstance() -> Scheduler {
    if let scheduler { return scheduler }
    let host = ScheduleHost(
      devices: { [weak self] in try await self?.devices() ?? [] },
      execute: { [weak self] command in
        guard let self else { throw CancellationError() }
        return try await self.execute(command)
      },
      publish: { [weak self] run in await self?.publishSchedule(run) }
    )
    let made = Scheduler(configuration: scheduling, now: now, host: host)
    scheduler = made
    return made
  }

  /// The schedules, in the order they were added, each with its next run.
  ///
  /// - Throws: ``ScheduleError/notSaved`` when the stored schedules can't be read.
  public func schedules() async throws -> [ScheduleEntry] {
    try await schedulerInstance().schedules()
  }

  /// Validates a schedule against the cached devices and the network's place, stores it, and works out its next
  /// run, so it takes effect without a restart. A schedule with the identifier of an existing one replaces it
  /// and keeps nothing of its last run.
  ///
  /// - Throws: ``ScheduleError``.
  public func putSchedule(_ schedule: ServiceSchedule) async throws -> ScheduleEntry {
    try await schedulerInstance().putSchedule(schedule)
  }

  /// Removes a schedule, which stops at once.
  ///
  /// - Throws: ``ScheduleError/unknownSchedule`` when no schedule has the identifier.
  public func removeSchedule(id: String) async throws {
    try await schedulerInstance().removeSchedule(id: id)
  }

  /// The timers that haven't fired, in the order they were added.
  public func timers() async throws -> [TimerEntry] {
    try await schedulerInstance().timers()
  }

  /// Starts a timer, or restarts the timer with its identifier.
  ///
  /// - Throws: ``ScheduleError``.
  public func putTimer(_ timer: ServiceTimer) async throws -> TimerEntry {
    try await schedulerInstance().putTimer(timer)
  }

  /// Cancels a timer.
  ///
  /// - Throws: ``ScheduleError/unknownTimer`` when no timer has the identifier.
  public func removeTimer(id: String) async throws {
    try await schedulerInstance().removeTimer(id: id)
  }

  private func publishSchedule(_ run: ScheduleRun) {
    publish(.schedule(run))
  }

  private func healthNotes() async -> [ServiceHealthNote] {
    let scheduler = schedulerInstance()
    var notes = await scheduler.notes
    if let hubClock, let zone = await scheduler.homeTimeZone, let seconds = HubClockDrift.seconds(reported: hubClock.reported, in: zone, at: hubClock.readAt) {
      notes.append(.hubClockDrift(seconds: seconds))
    }
    return notes
  }

  /// Reports readiness, the modem's state, and the times of the last hardware exchange, the last
  /// answered poll and the last confirmation of the cached device information. It sends nothing
  /// to hardware and doesn't take the admission gate.
  public func health() async -> ServiceHealth {
    let readiness: ServiceHealth.Readiness
    switch connection {
    case .connected: readiness = .ready
    case .unavailable: readiness = hasConnected ? .degraded : .starting
    }
    return ServiceHealth(readiness: readiness, modem: connection, lastHardwareExchange: lastExchange, lastPoll: lastPoll, deviceInformationUpdated: informationUpdated, persistence: persistenceOutcome, checkedAt: now(), notes: await healthNotes(), tuning: tuning.entries(sources: tuningSources))
  }

  /// Subscribes to typed events. Each subscription is iterated by one caller task. A subscriber
  /// that arrives while the modem is unreachable is told so first.
  public func events() async -> ServiceEvents {
    subscriptions.removeAll { $0.value == nil }
    let subscription = CommandEventSubscription()
    if case let .unavailable(cause) = connection, cause != .connecting {
      _ = subscription.publish(.event(.modemUnavailable(cause), currentCursor))
    }
    subscriptions.append(WeakCommandSubscription(value: subscription))
    return ServiceEvents(subscription: subscription)
  }

  /// Subscribes to numbered events, resuming from `cursor`.
  ///
  /// With no cursor, the subscription starts at the call with the run's current position, and a subscriber that arrives while the
  /// modem is unreachable is told so first, at the run's current number. With a cursor of this
  /// run whose missed events are still kept (the newest ``retainedEventCount``), the subscription
  /// starts with them, in order, then continues with live events. With any other cursor it starts
  /// with a gap saying why and the run's current position, then the modem's state if it is
  /// unreachable, then live events. Events and the replay are delivered without a gap between
  /// them: the service admits one call at a time.
  ///
  /// - Parameter cursor: The last position the client saw.
  public func sequencedEvents(after cursor: EventCursor? = nil) async -> SequencedEvents {
    subscriptions.removeAll { $0.value == nil }
    var backlog: [SequencedItem] = []
    var announce = true
    if cursor == nil { backlog.append(.position(currentCursor)) }
    if let cursor {
      switch coverage(of: cursor) {
      case let .covered(missed):
        backlog = missed.map { .event($0.event, EventCursor(runID: runID, sequence: $0.sequence)) }
        announce = false
      case let .gap(reason):
        backlog = [.gap(reason, current: currentCursor)]
      }
    }
    if announce, case let .unavailable(cause) = connection, cause != .connecting {
      backlog.append(.event(.modemUnavailable(cause), currentCursor))
    }
    let subscription = CommandEventSubscription(capacity: 64 + backlog.count)
    for item in backlog { _ = subscription.publish(item) }
    subscriptions.append(WeakCommandSubscription(value: subscription))
    return SequencedEvents(subscription: subscription)
  }

  private var currentCursor: EventCursor { EventCursor(runID: runID, sequence: sequence) }

  private enum Coverage {
    case covered([(sequence: UInt64, event: ServiceEvent)])
    case gap(EventGapReason)
  }

  private func coverage(of cursor: EventCursor) -> Coverage {
    guard cursor.runID == runID else { return .gap(.otherRun) }
    guard cursor.sequence <= sequence else { return .gap(.ahead) }
    let missed = retained.filter { $0.sequence > cursor.sequence }
    // Everything after the cursor is kept when the oldest kept event follows it directly, or none is missed.
    guard UInt64(missed.count) == sequence - cursor.sequence else { return .gap(.tooOld) }
    return .covered(missed)
  }

  private static func randomRunID() -> String {
    String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(16))
  }

  /// Keeps the modem connected and monitored while a host body runs, then checkpoints on
  /// shutdown. The body can host HTTP or any other adapter. No server framework is required.
  ///
  /// A service made with an opener starts the body at once, serving the cached device list
  /// while it connects, and keeps reconnecting until the body ends. A configuration error ends
  /// the run. A service made with a network ends the run when its connection ends.
  public func run(_ body: @escaping @Sendable () async throws -> Void) async throws -> PersistenceOutcome {
    guard !running else { throw ServiceLifecycleError.alreadyRunning }
    running = true
    defer { running = false }
    do {
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { try await body() }
        group.addTask { try await self.maintainConnection() }
        let scheduler = self.schedulerInstance()
        group.addTask { await scheduler.run() }
        defer { group.cancelAll() }
        _ = try await group.next()
      }
    } catch {
      _ = try? await checkpoint()
      throw error
    }
    return try await checkpoint()
  }

  private func maintainConnection() async throws {
    var failures = 0
    while true {
      try Task.checkCancellation()
      attemptConnected = false
      var failure: any Error = ServiceLifecycleError.connectionEnded
      do {
        let snapshot = await network.snapshot()
        try await opener.withServedNetwork(snapshot: snapshot, onPollSucceeded: { await self.pollSucceeded() }) { candidate in try await self.serve(candidate) }
      } catch {
        failure = error
      }
      try Task.checkCancellation()
      guard reconnect.reconnects else { throw failure }
      let cause: ModemUnavailability
      switch ConnectionFailure(failure) {
      case .fatal: throw (failure as? ConnectionRefusal)?.underlying ?? failure
      case let .retry(reason): cause = throughHub && reason == .modemUnreachable ? .hubUnreachable : reason
      }
      noteUnavailable(cause)
      failures = attemptConnected ? 1 : failures + 1
      try await clock.sleep(for: reconnect.delay(afterFailures: failures, cause: cause, unit: jitter()))
    }
  }

  /// Prepares one connection's network, serves it, and monitors it until the connection ends.
  /// The network replaces the previous one only after the modem answers and its ALL-Link
  /// database is read, so the cached list stays whole while connecting.
  private func serve(_ candidate: any ServedNetwork) async throws {
    try await candidate.prepare()
    // A rules file that can't be read leaves the rules off; changing them reports why.
    try? await loadNotificationRules()
    // Subscribe before announcing the connection so nothing heard from then on is missed.
    let changes = try await candidate.changes()
    // A Hub that reports its clock lets the service say when it differs; the service never sets it.
    hubClock = await candidate.reportedLocalTime().map { ($0, now()) }
    await connected(to: candidate)
    switch changes {
    case let .heard(events):
      for await event in events {
        try Task.checkCancellation()
        heard(event)
      }
    case let .polled(events):
      for try await event in events {
        try Task.checkCancellation()
        heard(event)
      }
    }
    try Task.checkCancellation()
  }

  private func heard(_ event: DeviceMonitorEvent) {
    lastExchange = now()
    if let event = ServiceEvent(event) { publish(event) }
    evaluateNotificationRules(for: event)
  }

  private func pollSucceeded() {
    lastPoll = now()
  }

  private func connected(to candidate: any ServedNetwork) async {
    network = candidate
    connection = .connected
    hasConnected = true
    attemptConnected = true
    lastExchange = now()
    informationUpdated = now()
    publish(.modemReconnected)
    _ = await persist()
  }

  private func noteUnavailable(_ cause: ModemUnavailability) {
    let state = ModemConnectionState.unavailable(cause)
    guard connection != state else { return }
    connection = state
    publish(.modemUnavailable(cause))
  }

  private func publish(_ event: ServiceEvent) {
    sequence += 1
    retained.append((sequence, event))
    if retained.count > Self.retainedEventCount { retained.removeFirst(retained.count - Self.retainedEventCount) }
    let item = SequencedItem.event(event, currentCursor)
    subscriptions.removeAll { entry in
      guard let subscription = entry.value else { return true }
      return !subscription.publish(item)
    }
  }

  private func persist() async -> PersistenceOutcome {
    guard let persistence else { return .notConfigured }
    let outcome = await persistence.save(await network.snapshot())
    persistenceOutcome = outcome
    return outcome
  }

  private static func addresses(in snapshot: NetworkSnapshot) -> [InsteonAddress] {
    let linked = snapshot.modemDatabase?.filter { $0.flags.contains(.inUse) }.map { $0.address } ?? []
    return Set(snapshot.registry.identities.keys).union(snapshot.devices.keys).union(linked).sorted { $0.description < $1.description }
  }
}
