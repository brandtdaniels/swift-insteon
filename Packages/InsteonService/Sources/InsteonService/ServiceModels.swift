import Foundation
import InsteonCore

/// A cached device description, independent of any transport or presentation format.
public struct ServiceDevice: Equatable, Sendable {
  /// The device's typed Insteon address.
  public let address: InsteonAddress
  /// The catalog's product name, if known.
  public let productName: String?
  /// Whether the main group can be turned on and off.
  public let canTurnOnAndOff: Bool
  /// Whether the main group accepts a percentage.
  public let canDim: Bool
  /// The last cached byte; it may come from an acknowledged control, not a status reading.
  public let value: UInt8?
  /// When the device last answered a command, not when it was passively heard.
  public let lastAnsweredAt: Date?

  /// Creates a cached description.
  public init(address: InsteonAddress, productName: String?, canTurnOnAndOff: Bool, canDim: Bool, value: UInt8?, lastAnsweredAt: Date?) {
    self.address = address
    self.productName = productName
    self.canTurnOnAndOff = canTurnOnAndOff
    self.canDim = canDim
    self.value = value
    self.lastAnsweredAt = lastAnsweredAt
  }
}

/// An explicit operation on a known device's main group.
public struct ServiceCommand: Equatable, Sendable {
  /// The operations the service exposes.
  public enum Action: Equatable, Sendable {
    /// Ask the device for its identity.
    case identify
    /// Read the device's status.
    case status
    /// Turn the main group on, optionally at a percentage.
    case on
    /// Turn the main group off.
    case off
  }
  /// The target device.
  public let address: InsteonAddress
  /// The requested operation.
  public let action: Action
  /// A percentage, valid only for On and only when the group dims.
  public let levelPercent: Int?

  /// Creates a command. The service validates percentages and device capabilities.
  public init(address: InsteonAddress, action: Action, levelPercent: Int? = nil) {
    self.address = address
    self.action = action
    self.levelPercent = levelPercent
  }
}

/// Snapshot persistence health, separate from a device operation's result.
public enum PersistenceOutcome: Equatable, Sendable {
  /// No persistence adapter was supplied.
  case notConfigured
  /// A configured adapter hasn't been called yet.
  case notAttempted
  /// The snapshot was saved.
  case saved
  /// Saving failed; any confirmed device result remains valid.
  case failed
}

/// A confirmed execution result with independent snapshot persistence health.
public struct CommandReceipt: Equatable, Sendable {
  /// What the device operation established.
  public enum Outcome: Equatable, Sendable {
    /// The device acknowledged a control, without a status readback.
    case acknowledged
    /// The device answered a status or identity request.
    case read
  }
  /// The device that answered.
  public let address: InsteonAddress
  /// Whether the operation was acknowledged or read.
  public let outcome: Outcome
  /// A typed status reading, present only for a status request.
  public let status: DeviceStatus?
  /// The independent outcome of saving the learned network state.
  public let persistence: PersistenceOutcome

  /// Creates a receipt without formatting the status for a user interface or wire protocol.
  public init(address: InsteonAddress, outcome: Outcome, status: DeviceStatus?, persistence: PersistenceOutcome = .notConfigured) {
    self.address = address
    self.outcome = outcome
    self.status = status
    self.persistence = persistence
  }
}

/// The query role of an Insteon service.
public protocol DeviceQuerying: Sendable {
  /// Lists cached information without requesting anything from hardware.
  func devices() async throws -> [ServiceDevice]
}

/// The command role of an Insteon service.
public protocol DeviceCommanding: Sendable {
  /// Executes an explicit operation without automatically retrying it.
  func execute(_ command: ServiceCommand) async throws -> CommandReceipt
}

/// The event role of an Insteon service.
public protocol DeviceEventSource: Sendable {
  /// A subscription's sequence. Its reader owns iteration and cancellation.
  associatedtype Events: AsyncSequence & Sendable where Events.Element == ServiceEvent
  /// Subscribes from the call on, without stored history or an inferred status refresh.
  func events() async -> Events
}

/// The cohesive API consumed by an adapter that needs queries, commands and events.
/// A single instance supplies all three roles, preventing mismatched device networks.
public protocol InsteonServiceAPI: DeviceQuerying, DeviceCommanding, DeviceEventSource {}

/// A refused operation, independent of HTTP status codes or display wording.
public enum ServiceControlError: Error {
  /// The device isn't known to this network.
  case unknownDevice
  /// A percentage is invalid or unsupported by the action or device.
  case invalidLevel
  /// The main group doesn't support switching.
  case unsupportedControl
  /// Another operation owns this service's admission gate. Nothing was queued.
  case busy
}

/// A service runtime failure, independent of its host.
public enum ServiceLifecycleError: Error {
  /// A runtime body is already active on this service.
  case alreadyRunning
  /// The modem's event stream ended while the runtime was active.
  case connectionEnded
}

/// Named device events, without wire-format versions, raw protocol messages or history.
public enum ServiceEvent: Equatable, Sendable {
  /// An explicit service command completed. The receipt distinguishes acknowledgment from
  /// a confirmed status reading and reports persistence independently. No automatic readback.
  case commandCompleted(ServiceCommand, CommandReceipt)
  /// A device reported its identity.
  case identified(InsteonAddress, productName: String?)
  /// A device's SET button was pressed.
  case setButtonPressed(InsteonAddress)
  /// A group command was heard, with the catalog's event or command name when available.
  case groupCommand(InsteonAddress, group: Int, name: String?)
  /// A periodic heartbeat was heard.
  case heartbeat(InsteonAddress, group: Int?)
  /// A device reported that its status changed; consumers can explicitly request status.
  case statusChanged(InsteonAddress)

  init?(_ event: DeviceMonitorEvent) {
    switch event {
    case let .identified(address, name): self = .identified(address, productName: name)
    case let .setButtonPressed(press): self = .setButtonPressed(press.device)
    case let .groupCommand(command): self = .groupCommand(command.device, group: command.group, name: command.event ?? command.commandName)
    case let .heartbeat(address, group): self = .heartbeat(address, group: group)
    case let .heartbeatBroadcast(address, _): self = .heartbeat(address, group: nil)
    case let .statusChanged(address): self = .statusChanged(address)
    case .message, .modem, .rawMessage, .rawReply: return nil
    }
  }
}
