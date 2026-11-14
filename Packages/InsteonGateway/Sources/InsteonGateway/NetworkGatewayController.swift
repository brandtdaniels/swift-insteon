import Foundation
import InsteonCore

/// A persistent gateway controller using the same device API as the CLI.
///
/// One instance owns a network and a snapshot store. It serializes explicit operations,
/// rejects unknown addresses, preserves catalog restrictions, and never retries controls.
public actor NetworkGatewayController: GatewayControlling {
  private let network: DeviceNetwork
  private let store: (any NetworkSnapshotStore)?
  private var busy = false

  /// Creates a controller for an already-open modem session and its restored network.
  public init(network: DeviceNetwork, store: (any NetworkSnapshotStore)? = nil) {
    self.network = network
    self.store = store
  }

  /// Lists cached devices without asking the modem or a device for information.
  /// Unidentified devices have no switching controls until explicitly identified.
  public func devices() async throws -> [GatewayDevice] {
    guard !busy else { throw GatewayControlError.busy }
    busy = true
    defer { busy = false }
    let snapshot = await network.snapshot()
    let addresses = Self.addresses(in: snapshot)
    var devices: [GatewayDevice] = []
    for address in addresses {
      // A known registry entry makes capabilities() use its identity without hardware I/O.
      let known = await network.registry.device(address)
      let capabilities = known == nil ? nil : try await network.device(address).capabilities()
      let state = snapshot.devices[address]
      devices.append(GatewayDevice(
        address: address.description,
        productName: capabilities?.productName,
        canTurnOnAndOff: capabilities?.canTurnOnAndOff ?? false,
        canDim: capabilities?.canDim ?? false,
        value: state?.level,
        lastAnsweredAt: state?.lastSeen
      ))
    }
    return devices
  }

  /// Executes a command on a known device's main group, then saves the learned state.
  /// A store failure is reported as a failure even if the device already acted.
  public func perform(_ command: GatewayCommand) async throws -> GatewayCommandResult {
    guard !busy else { throw GatewayControlError.busy }
    busy = true
    defer { busy = false }
    guard let address = InsteonAddress(command.address), Self.addresses(in: await network.snapshot()).contains(address) else {
      throw GatewayControlError.unknownDevice
    }
    if let level = command.levelPercent, command.action != .on || !(0...100).contains(level) {
      throw GatewayControlError.invalidLevel
    }
    let device = network.device(address)
    let result: GatewayCommandResult
    switch command.action {
    case .identify:
      _ = try await network.identify(address)
      result = GatewayCommandResult(address: address.description, outcome: .read, status: nil)
    case .status:
      let reading = try await device.status()
      let text: String
      switch reading.reading {
      case let .percent(value): text = String(value) + "%"
      case let .onOff(value): text = value ? "On" : "Off"
      case let .named(value): text = value
      case .raw: text = "Value " + String(reading.value)
      }
      result = GatewayCommandResult(address: address.description, outcome: .read, status: text)
    case .on, .off:
      let capabilities = try await device.capabilities()
      guard capabilities.canTurnOnAndOff else { throw GatewayControlError.unsupportedControl }
      if command.levelPercent != nil, !capabilities.canDim { throw GatewayControlError.invalidLevel }
      if command.action == .on {
        _ = try await device.turnOn(level: command.levelPercent)
      } else {
        try await device.turnOff()
      }
      result = GatewayCommandResult(address: address.description, outcome: .acknowledged, status: nil)
    }
    try await saveState()
    return result
  }

  /// Saves the network. Call outside active commands, such as at startup and shutdown.
  public func save() async throws {
    guard !busy else { throw GatewayControlError.busy }
    busy = true
    defer { busy = false }
    try await saveState()
  }

  private func saveState() async throws {
    if let store { try await store.saveNetwork(await network.snapshot()) }
  }

  /// Subscribes to named device events from the call on. Read each returned stream in one task.
  /// Events don't claim that cached device levels have been refreshed.
  public func events() async -> AsyncCompactMapSequence<AsyncStream<DeviceMonitorEvent>, GatewayEvent> {
    await network.monitor.changes().compactMap { GatewayEvent($0) }
  }

  private static func addresses(in snapshot: NetworkSnapshot) -> [InsteonAddress] {
    let linked = snapshot.modemDatabase?.filter { $0.flags.contains(.inUse) }.map { $0.address } ?? []
    return Set(snapshot.registry.identities.keys).union(snapshot.devices.keys).union(linked).sorted { $0.description < $1.description }
  }
}

/// A live notification, without raw protocol messages or stored event history.
public struct GatewayEvent: Codable, Equatable, Sendable {
  /// The event format's version.
  public let version: Int
  /// The event type: identified, setButtonPressed, groupCommand, heartbeat or statusChanged.
  public let kind: String
  /// The originating device.
  public let address: String
  /// The device's group, if present.
  public let group: Int?
  /// The catalog's event name, if present.
  public let name: String?

  init?(_ event: DeviceMonitorEvent) {
    self.version = 1
    switch event {
    case let .identified(address, _):
      self.kind = "identified"; self.address = address.description; self.group = nil; self.name = nil
    case let .setButtonPressed(press):
      self.kind = "setButtonPressed"; self.address = press.device.description; self.group = nil; self.name = nil
    case let .groupCommand(command):
      self.kind = "groupCommand"; self.address = command.device.description; self.group = command.group; self.name = command.event ?? command.commandName
    case let .heartbeat(address, group):
      self.kind = "heartbeat"; self.address = address.description; self.group = group; self.name = nil
    case let .heartbeatBroadcast(address, _):
      self.kind = "heartbeat"; self.address = address.description; self.group = nil; self.name = nil
    case let .statusChanged(address):
      self.kind = "statusChanged"; self.address = address.description; self.group = nil; self.name = nil
    case .message, .modem, .rawMessage, .rawReply:
      return nil
    }
  }
}
