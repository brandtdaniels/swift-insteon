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
  private var network: DeviceNetwork
  private let opener: any NetworkOpening
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

  /// How many of the newest events the service keeps for a client to resume from. Memory is
  /// bounded by this count; nothing is kept on disk, and a restart forgets every event.
  public static let retainedEventCount = 256

  /// The latest snapshot outcome, independent of any device acknowledgment or reading.
  public private(set) var persistenceOutcome: PersistenceOutcome

  /// Creates a service for a network whose connection the host keeps open, and an optional
  /// persistence policy. The run ends if that connection does.
  public init(network: DeviceNetwork, persistence: (any SnapshotPersisting)? = nil, clock: any Clock<Duration> = ContinuousClock(), runID: String? = nil) {
    self.init(network: network, opener: FixedNetworkOpener(network: network), persistence: persistence, snapshotSavedAt: nil, reconnect: .never, clock: clock, now: { Date() }, jitter: { 0 }, isConnected: true, runID: runID)
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
  public init(
    network: DeviceNetwork,
    opener: any NetworkOpening,
    persistence: (any SnapshotPersisting)? = nil,
    snapshotSavedAt: Date? = nil,
    reconnect: ReconnectPolicy = .standard,
    clock: any Clock<Duration> = ContinuousClock(),
    now: @escaping @Sendable () -> Date = { Date() },
    jitter: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) },
    throughHub: Bool = false,
    runID: String? = nil,
    notificationRules: (any NotificationRulePersisting)? = nil
  ) {
    self.init(network: network, opener: opener, persistence: persistence, snapshotSavedAt: snapshotSavedAt, reconnect: reconnect, clock: clock, now: now, jitter: jitter, isConnected: false, throughHub: throughHub, runID: runID, notificationRules: notificationRules)
  }

  private init(
    network: DeviceNetwork,
    opener: any NetworkOpening,
    persistence: (any SnapshotPersisting)?,
    snapshotSavedAt: Date?,
    reconnect: ReconnectPolicy,
    clock: any Clock<Duration>,
    now: @escaping @Sendable () -> Date,
    jitter: @escaping @Sendable () -> Double,
    isConnected: Bool,
    throughHub: Bool = false,
    runID: String? = nil,
    notificationRules: (any NotificationRulePersisting)? = nil
  ) {
    self.notificationPersistence = notificationRules
    self.network = network
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
      let known = await network.registry.device(address)
      let capabilities = known == nil ? nil : try await network.device(address).capabilities()
      result.append(ServiceDevice(address: address, productName: capabilities?.productName, canTurnOnAndOff: capabilities?.canTurnOnAndOff ?? false, canDim: capabilities?.canDim ?? false, value: snapshot.devices[address]?.level, lastAnsweredAt: snapshot.devices[address]?.lastSeen))
    }
    return result
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
    let device = network.device(command.address)
    let outcome: CommandReceipt.Outcome
    let status: DeviceStatus?
    do {
      switch command.action {
      case .identify:
        _ = try await network.identify(command.address)
        outcome = .read; status = nil
      case .status:
        do {
          status = try await device.status()
        } catch ModemError.deviceTimedOut {
          // A device that never reported what it is and doesn't answer a read has no identity to act on.
          if await network.registry.device(command.address) == nil { throw ServiceControlError.notIdentified }
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
  private func eventNames(of device: InsteonAddress, in network: DeviceNetwork) async -> Set<String>? {
    guard let identity = await network.registry.device(device)?.identity, let catalog = await network.registry.catalog,
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

  /// Reports readiness, the modem's state, and the times of the last hardware exchange, the last
  /// answered poll and the last confirmation of the cached device information. It sends nothing
  /// to hardware and doesn't take the admission gate.
  public func health() -> ServiceHealth {
    let readiness: ServiceHealth.Readiness
    switch connection {
    case .connected: readiness = .ready
    case .unavailable: readiness = hasConnected ? .degraded : .starting
    }
    return ServiceHealth(readiness: readiness, modem: connection, lastHardwareExchange: lastExchange, lastPoll: lastPoll, deviceInformationUpdated: informationUpdated, persistence: persistenceOutcome, checkedAt: now())
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
        try await opener.withNetwork(snapshot: snapshot, onPollSucceeded: { await self.pollSucceeded() }) { candidate in try await self.serve(candidate) }
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
  private func serve(_ candidate: DeviceNetwork) async throws {
    _ = try await candidate.modemInfo()
    _ = try await candidate.modemDatabase()
    // A rules file that can't be read leaves the rules off; changing them reports why.
    try? await loadNotificationRules()
    // Subscribe before announcing the connection so nothing heard from then on is missed.
    let changes = await candidate.monitor.changes()
    await connected(to: candidate)
    for await event in changes {
      try Task.checkCancellation()
      lastExchange = now()
      if let event = ServiceEvent(event) { publish(event) }
      evaluateNotificationRules(for: event)
    }
    try Task.checkCancellation()
  }

  private func pollSucceeded() {
    lastPoll = now()
  }

  private func connected(to candidate: DeviceNetwork) async {
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
