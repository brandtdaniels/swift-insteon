import Foundation
import InsteonCore
import InsteonModem

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
  private let persistence: (any SnapshotPersisting)?
  private var busy = false
  private var running = false
  private var subscriptions: [WeakCommandSubscription] = []
  private var connection: ModemConnectionState
  private var hasConnected: Bool
  private var lastExchange: Date?
  private var lastPoll: Date?
  private var informationUpdated: Date?
  private var attemptConnected = false

  /// The latest snapshot outcome, independent of any device acknowledgment or reading.
  public private(set) var persistenceOutcome: PersistenceOutcome

  /// Creates a service for a network whose connection the host keeps open, and an optional
  /// persistence policy. The run ends if that connection does.
  public init(network: DeviceNetwork, persistence: (any SnapshotPersisting)? = nil, clock: any Clock<Duration> = ContinuousClock()) {
    self.init(network: network, opener: FixedNetworkOpener(network: network), persistence: persistence, snapshotSavedAt: nil, reconnect: .never, clock: clock, now: { Date() }, jitter: { 0 }, isConnected: true)
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
  public init(
    network: DeviceNetwork,
    opener: any NetworkOpening,
    persistence: (any SnapshotPersisting)? = nil,
    snapshotSavedAt: Date? = nil,
    reconnect: ReconnectPolicy = .standard,
    clock: any Clock<Duration> = ContinuousClock(),
    now: @escaping @Sendable () -> Date = { Date() },
    jitter: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) }
  ) {
    self.init(network: network, opener: opener, persistence: persistence, snapshotSavedAt: snapshotSavedAt, reconnect: reconnect, clock: clock, now: now, jitter: jitter, isConnected: false)
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
    isConnected: Bool
  ) {
    self.network = network
    self.opener = opener
    self.reconnect = reconnect
    self.clock = clock
    self.now = now
    self.jitter = jitter
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
      _ = subscription.publish(.modemUnavailable(cause))
    }
    subscriptions.append(WeakCommandSubscription(value: subscription))
    return ServiceEvents(subscription: subscription)
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
      case let .retry(reason): cause = reason
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
    // Subscribe before announcing the connection so nothing heard from then on is missed.
    let changes = await candidate.monitor.changes()
    await connected(to: candidate)
    for await event in changes {
      try Task.checkCancellation()
      lastExchange = now()
      if let event = ServiceEvent(event) { publish(event) }
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
    subscriptions.removeAll { entry in
      guard let subscription = entry.value else { return true }
      return !subscription.publish(event)
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
