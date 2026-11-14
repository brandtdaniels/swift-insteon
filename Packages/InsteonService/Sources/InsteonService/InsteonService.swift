import InsteonCore

/// One persistent Insteon network's operations, monitoring and snapshot policy.
///
/// The service has no authentication, HTTP, HTML or wire-format responsibilities. Its one
/// admission gate applies to all callers, regardless of transport. The host keeps the
/// supplied modem session open for the service's lifetime.
public actor InsteonService: InsteonServiceAPI {
  private let network: DeviceNetwork
  private let persistence: (any SnapshotPersisting)?
  private var busy = false
  private var running = false

  /// The latest snapshot outcome, independent of any device acknowledgment or reading.
  public private(set) var persistenceOutcome: PersistenceOutcome

  /// Creates a service for an open session's restored network and an optional persistence policy.
  public init(network: DeviceNetwork, persistence: (any SnapshotPersisting)? = nil) {
    self.network = network
    self.persistence = persistence
    self.persistenceOutcome = persistence == nil ? .notConfigured : .notAttempted
  }

  /// Lists cached devices. Unidentified devices have no switching controls until identified.
  public func devices() async throws -> [ServiceDevice] {
    guard !busy else { throw ServiceControlError.busy }
    busy = true
    defer { busy = false }
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
  public func execute(_ command: ServiceCommand) async throws -> CommandReceipt {
    guard !busy else { throw ServiceControlError.busy }
    busy = true
    defer { busy = false }
    guard Self.addresses(in: await network.snapshot()).contains(command.address) else { throw ServiceControlError.unknownDevice }
    if let level = command.levelPercent, command.action != .on || !(0...100).contains(level) { throw ServiceControlError.invalidLevel }
    let device = network.device(command.address)
    let outcome: CommandReceipt.Outcome
    let status: DeviceStatus?
    switch command.action {
    case .identify:
      _ = try await network.identify(command.address)
      outcome = .read; status = nil
    case .status:
      status = try await device.status()
      outcome = .read
    case .on, .off:
      let capabilities = try await device.capabilities()
      guard capabilities.canTurnOnAndOff else { throw ServiceControlError.unsupportedControl }
      if command.levelPercent != nil, !capabilities.canDim { throw ServiceControlError.invalidLevel }
      if command.action == .on { _ = try await device.turnOn(level: command.levelPercent) }
      else { try await device.turnOff() }
      outcome = .acknowledged; status = nil
    }
    let saved = await persist()
    return CommandReceipt(address: command.address, outcome: outcome, status: status, persistence: saved)
  }

  /// Saves a snapshot through the same admission gate as operations. Storage failure is data.
  public func checkpoint() async throws -> PersistenceOutcome {
    guard !busy else { throw ServiceControlError.busy }
    busy = true
    defer { busy = false }
    return await persist()
  }

  /// Subscribes to typed events. Each subscription is iterated by one caller task.
  public func events() async -> AsyncCompactMapSequence<AsyncStream<DeviceMonitorEvent>, ServiceEvent> {
    await network.monitor.changes().compactMap { ServiceEvent($0) }
  }

  /// Prepares the modem, monitors it while a host body runs, then checkpoints on shutdown.
  /// The body can host HTTP or any other adapter. No server framework is required.
  public func run(_ body: @escaping @Sendable () async throws -> Void) async throws -> PersistenceOutcome {
    guard !running else { throw ServiceLifecycleError.alreadyRunning }
    running = true
    defer { running = false }
    try await prepare()
    // Subscribe before starting the host so events from the call on aren't missed.
    let changes = await network.monitor.changes()
    _ = try await checkpoint()
    do {
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { try await body() }
        group.addTask {
          for await _ in changes { try Task.checkCancellation() }
          try Task.checkCancellation()
          throw ServiceLifecycleError.connectionEnded
        }
        defer { group.cancelAll() }
        _ = try await group.next()
      }
    } catch {
      _ = try? await checkpoint()
      throw error
    }
    return try await checkpoint()
  }

  private func prepare() async throws {
    guard !busy else { throw ServiceControlError.busy }
    busy = true
    defer { busy = false }
    _ = try await network.modemInfo()
    _ = try await network.modemDatabase()
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
