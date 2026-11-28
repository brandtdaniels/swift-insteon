import Foundation
import InsteonCore
import InsteonDeviceCatalog
import InsteonProtocol

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
  /// Subscribes to numbered events, resuming after `cursor` when the events it missed are still
  /// kept, and starting with a gap item when they aren't.
  func sequencedEvents(after cursor: EventCursor?) async -> SequencedEvents
}

/// The health role of an Insteon service.
public protocol HealthReporting: Sendable {
  /// Reports the service's state without asking hardware anything or taking the admission gate.
  func health() async -> ServiceHealth
}

/// Builds the catalog's view of a group command a monitor heard, for matching against notification rules.
extension DeviceEvent {
  init?(_ event: DeviceMonitorEvent) {
    switch event {
    case let .groupCommand(command):
      guard let group = UInt8(exactly: command.group) else { return nil }
      let controller = GroupCommand(controller: command.device, group: AllLinkGroupNumber(rawValue: group), command1: command.command1, command2: nil, source: .broadcast)
      self = .groupCommand(controller, event: command.event.map { DeviceEventName(rawValue: $0) })
    default:
      return nil
    }
  }
}

/// The backup role of an Insteon service.
public protocol NetworkBackupProviding: Sendable {
  /// A backup of what the service has cached: the modem's address and ALL-Link database, each
  /// device's ALL-Link database where the service holds a copy, and the devices' identities.
  /// It sends nothing to hardware and doesn't take the admission gate. A device with no cached
  /// copy is in the backup as not cached.
  func networkBackup() async -> NetworkBackup
}

/// An explicit command to one of the modem's scenes.
public struct SceneCommand: Equatable, Sendable {
  /// What a scene can be told to do. Each member recalls the on-level or off its own link data
  /// holds, so a scene takes no level.
  public enum Action: Equatable, Sendable {
    /// Turn the scene on.
    case on
    /// Turn the scene off.
    case off
  }
  /// The scene's ALL-Link group, from 1 through 254.
  public let number: UInt8
  /// The requested operation.
  public let action: Action

  /// Creates a command. The service checks that the modem controls the scene and that it has members.
  public init(number: UInt8, action: Action) {
    self.number = number
    self.action = action
  }
}

/// How a scene's command went, as the modem reported it. A scene is run once and never repeated by the service.
public struct SceneReceipt: Equatable, Sendable {
  /// The scene's ALL-Link group.
  public let scene: UInt8
  /// What the scene was told to do.
  public let action: SceneCommand.Action
  /// The members that acknowledged their ALL-Link cleanup. It is empty for a modem that passes no
  /// per-member acknowledgment up, so an empty list never means that no member acted.
  public let acknowledged: [InsteonAddress]
  /// The members that did not acknowledge their cleanup, and may still have acted on the broadcast.
  public let unacknowledged: [InsteonAddress]
  /// Whether the modem sent every member its cleanup. `false` when it stopped partway.
  public let isComplete: Bool
  /// How many members the scene had in the listing the run was made from.
  public let responderCount: Int
  /// The independent outcome of saving the learned network state.
  public let persistence: PersistenceOutcome
  /// How long after the modem accepted the command its cleanup status report came, or `nil` if it
  /// didn't come in time. For the log: it isn't on the wire.
  public let statusReportAfter: Duration?
  /// How long after the modem accepted the command the first cleanup failure report came, or `nil`.
  /// For the log: it isn't on the wire.
  public let failureReportedAfter: Duration?

  /// Creates a receipt.
  public init(scene: UInt8, action: SceneCommand.Action, acknowledged: [InsteonAddress], unacknowledged: [InsteonAddress], isComplete: Bool, responderCount: Int, persistence: PersistenceOutcome = .notConfigured, statusReportAfter: Duration? = nil, failureReportedAfter: Duration? = nil) {
    self.statusReportAfter = statusReportAfter
    self.failureReportedAfter = failureReportedAfter
    self.scene = scene
    self.action = action
    self.acknowledged = acknowledged
    self.unacknowledged = unacknowledged
    self.isComplete = isComplete
    self.responderCount = responderCount
    self.persistence = persistence
  }
}

/// A scene that ran, as the `scene` event reports it.
public struct SceneRun: Equatable, Sendable {
  /// What started the run.
  public enum Source: Equatable, Sendable {
    /// A client's request to the service.
    case api
  }
  /// The scene's ALL-Link group.
  public let number: UInt8
  /// The scene's name, or `nil` when it has none.
  public let name: String?
  /// What started the run.
  public let source: Source
  /// What the scene was told to do.
  public let action: SceneCommand.Action
  /// What the modem reported.
  public let receipt: SceneReceipt
  /// When the service handled the run.
  public let firedAt: Date

  /// Creates a run.
  public init(number: UInt8, name: String?, source: Source, action: SceneCommand.Action, receipt: SceneReceipt, firedAt: Date) {
    self.number = number
    self.name = name
    self.source = source
    self.action = action
    self.receipt = receipt
    self.firedAt = firedAt
  }
}

/// A scene whose members changed, as the `scene` event reports it.
public struct SceneChanged: Equatable, Sendable {
  /// What started the change.
  public enum Source: Equatable, Sendable {
    /// A client's request to apply a membership plan.
    case api
  }
  /// The scene's ALL-Link group.
  public let number: UInt8
  /// What started the change.
  public let source: Source
  /// What the apply came to. Anything but ``SceneMembershipApplication/Outcome/applied`` says the scene may hold only
  /// some of the planned members, or that what was written isn't confirmed, so a client reads the scenes again.
  public let outcome: SceneMembershipApplication.Outcome
  /// How many steps were made.
  public let stepsMade: Int
  /// How many steps were not made: failed, or not reached.
  public let stepsNotMade: Int
  /// Whether every step of the plan was made and both databases read back as expected.
  public var isComplete: Bool { outcome == .applied }
  /// When the service handled the change.
  public let firedAt: Date

  /// Creates a change.
  public init(number: UInt8, source: Source, outcome: SceneMembershipApplication.Outcome, stepsMade: Int, stepsNotMade: Int, firedAt: Date) {
    self.number = number
    self.source = source
    self.outcome = outcome
    self.stepsMade = stepsMade
    self.stepsNotMade = stepsNotMade
    self.firedAt = firedAt
  }
}

/// A plan for a scene's members and when the service stops keeping it.
public struct SceneMembershipPlanReceipt: Equatable, Sendable {
  /// What adding and removing the members would write. A plan with a refusal can't be applied.
  public let plan: SceneMembershipPlan
  /// When the service drops the plan from memory: five minutes after it was made.
  public let expiresAt: Date

  /// Creates a receipt.
  public init(plan: SceneMembershipPlan, expiresAt: Date) {
    self.plan = plan
    self.expiresAt = expiresAt
  }
}

/// What applying a scene membership plan did: each step's outcome and what reading the modem's database
/// and each device's again found.
public struct SceneMembershipApplication: Equatable, Sendable {
  /// Why the steps stopped for a reason other than a step's own failure.
  public enum Interruption: Equatable, Sendable {
    /// The request was canceled between steps or during one, so the steps after it were not made.
    case canceled
    /// The modem or the connection failed, with a description that carries no address or credential.
    case failed(String)
  }
  /// The scene's ALL-Link group.
  public let scene: UInt8
  /// The plan's identifier, which the apply request named.
  public let planId: String
  /// Each step with its outcome, and the records not as expected afterward.
  public let result: SceneMembershipResult
  /// Why the steps stopped, or `nil` when every step was tried.
  public let interruption: Interruption?
  /// The independent outcome of saving the learned network state.
  public let persistence: PersistenceOutcome

  /// Whether the service read the modem's database and the databases of the devices the steps touched into its cache
  /// afterward. `false` says the cache doesn't show what was written until the scenes are refreshed.
  public let isCacheReloaded: Bool

  /// The devices that reject the modem once their last record of it is removed, as an i2CS device does, so the service
  /// holds no copy of their databases. Expected after such a removal: it doesn't make ``isCacheReloaded`` false.
  public let expectedUnreadable: [InsteonAddress]

  /// What the apply came to.
  public enum Outcome: Equatable, Sendable {
    /// Every step was made and both databases read back as planned.
    case applied
    /// Every step was made and no record was found other than expected, but reading the databases again didn't
    /// finish, so what was written isn't confirmed.
    case appliedUnverified
    /// A step failed or wasn't reached, or a record was found other than expected.
    case incomplete
  }

  /// Whether every step was made and every database read back as expected.
  public var isComplete: Bool { interruption == nil && result.isComplete }

  /// What the apply came to: complete, made but not confirmed, or incomplete.
  public var outcome: Outcome {
    if isComplete { return .applied }
    return result.isUnverified ? .appliedUnverified : .incomplete
  }

  /// Creates an application.
  public init(scene: UInt8, planId: String, result: SceneMembershipResult, interruption: Interruption? = nil, persistence: PersistenceOutcome = .notConfigured, isCacheReloaded: Bool = true, expectedUnreadable: [InsteonAddress] = []) {
    self.isCacheReloaded = isCacheReloaded
    self.expectedUnreadable = expectedUnreadable
    self.scene = scene
    self.planId = planId
    self.result = result
    self.interruption = interruption
    self.persistence = persistence
  }
}

/// The scenes role of an Insteon service.
public protocol SceneProviding: Sendable {
  /// The scenes of the network, listed from the ALL-Link databases the service holds. It sends nothing
  /// to hardware and doesn't take the admission gate, so a device with no cached copy is reported
  /// as unreadable and the listing is not whole.
  func scenes() async -> SceneListing

  /// Reads the ALL-Link databases of the modem and of each device from the hardware, one request
  /// at a time, and lists the scenes from what was read. It only reads: nothing is written to the
  /// modem or to a device. A device that doesn't answer is listed as unreadable, and the listing
  /// is then not whole.
  ///
  /// It takes the admission gate for the whole read, and the checkpoint it saves holds what was
  /// read.
  ///
  /// - Throws: ``ServiceControlError/busy`` while another operation holds the gate,
  ///   ``ServiceControlError/modemUnavailable(_:)`` while the modem isn't connected (nothing is
  ///   sent), ``ServiceControlError/databasesUnavailable`` for a network that doesn't give out its
  ///   databases, `CancellationError` when canceled, and the modem's error when the connection is
  ///   lost.
  func refreshScenes() async throws -> SceneListing

  /// Runs a scene the modem controls: sends its group one Light On at full level or one Light Off,
  /// waits for the modem's ALL-Link cleanups, and publishes a ``ServiceEvent/scene(_:)`` event. It
  /// sends nothing to a device and doesn't read one afterward, so the cached device levels are left
  /// as they were.
  ///
  /// It takes the admission gate and is never repeated by the service.
  ///
  /// - Throws: ``ServiceControlError/busy`` while another operation holds the gate,
  ///   ``ServiceControlError/modemUnavailable(_:)`` while the modem isn't connected,
  ///   ``ServiceControlError/unknownScene`` when the listing holds no scene of that number that the
  ///   modem controls, ``ServiceControlError/sceneEmpty`` when the scene has no members (each
  ///   before anything is sent), `CancellationError` when canceled, and the modem's error when it
  ///   rejects the command or stops answering.
  func runScene(_ command: SceneCommand) async throws -> SceneReceipt

  /// Plans adding and removing a scene's members from the ALL-Link databases the service has cached
  /// and the catalog, and writes and sends nothing. The service keeps a plan it could apply in memory
  /// for five minutes.
  ///
  /// It reads only the cache, so it doesn't take the admission gate. A database the cache doesn't hold
  /// is a refusal in the plan, with the hint to refresh the scenes, not an error.
  ///
  /// - Parameter change: What to add and remove.
  /// - Returns: The plan and when it expires.
  /// - Throws: ``ServiceControlError/databasesUnavailable`` for a network that doesn't give out its
  ///   databases, as a Hub Pro's doesn't, ``ServiceControlError/unknownScene`` when the listing holds a
  ///   scene of that number that a device controls and none the modem controls. A number nothing
  ///   controls is a scene to create.
  func planSceneMembership(_ change: SceneMembershipChange) async throws -> SceneMembershipPlanReceipt

  /// Applies a plan from ``planSceneMembership(_:)``: writes its ALL-Link records, each in order, and
  /// reads each back.
  ///
  /// The plan is single use. Consent must agree to the writes and name the plan's fingerprint; an
  /// `admin` credential never stands in for it. The service takes the admission gate, reads the
  /// modem's database and each device's from the hardware, and writes nothing if any differs from
  /// what the plan was made from. It then makes each step through the same write, read-back and
  /// retry-once path as the command line's database writer, stops after the first step that fails,
  /// and reads both databases again to compare them with what the steps made should have left. A
  /// step that fails leaves the steps before it written and the steps after it unmade; the service
  /// never rolls anything back, and a client plans again from a fresh read.
  ///
  /// Afterward the service reads the databases it changed into its cache, publishes a
  /// ``ServiceEvent/sceneChanged(_:)`` event, and answers each step's outcome.
  ///
  /// - Parameters:
  ///   - scene: The scene's ALL-Link group, which the plan must be for.
  ///   - planId: The plan's identifier.
  ///   - consent: What the client granted.
  /// - Returns: The outcome of each step, whether or not every step was made.
  /// - Throws: ``ServiceControlError/unknownPlan``, ``ServiceControlError/planExpired``,
  ///   ``ServiceControlError/planAlreadyApplied``, ``ServiceControlError/planNotApplicable``,
  ///   ``ServiceControlError/consentRequired``, ``ServiceControlError/consentMismatch``,
  ///   ``ServiceControlError/busy``, ``ServiceControlError/modemUnavailable(_:)``,
  ///   ``ServiceControlError/databasesUnavailable``, ``ServiceControlError/deviceNotAnswering`` (a device didn't answer the read of the first slot, and the plan stays usable) and ``ServiceControlError/planStale``, each before
  ///   anything is written, and the modem's error when a database can't be read before the first
  ///   write.
  func applySceneMembership(scene: UInt8, planId: String, consent: DatabaseLinkConsent) async throws -> SceneMembershipApplication

  /// What the data bytes a scene's member holds mean, as the Insteon device catalog gives them for
  /// the device's identity. It sends nothing to hardware.
  ///
  /// - Parameters:
  ///   - data: The member's three link data bytes.
  ///   - device: The member's address.
  ///   - group: The scene's group number.
  /// - Returns: The meaning, or `nil` when the device's identity isn't known or the catalog
  ///   doesn't describe the bytes.
  func meaning(ofMemberData data: [UInt8], of device: InsteonAddress, group: UInt8) async -> LinkDataMeaning?
}

/// The cohesive API consumed by an adapter that needs queries, commands, events and health.
/// A single instance supplies all four roles, preventing mismatched device networks.
public protocol InsteonServiceAPI: DeviceQuerying, DeviceCommanding, DeviceEventSource, HealthReporting, NotificationRuleManaging, ScheduleManaging, NetworkBackupProviding, SceneProviding {}

/// A refused operation, independent of HTTP status codes or display wording.
public enum ServiceControlError: Error, Equatable {
  /// The device isn't known to this network.
  case unknownDevice
  /// The listing the service holds has no scene of that number the modem controls, so nothing was sent.
  case unknownScene
  /// The scene has no members, so nothing was sent.
  case sceneEmpty
  /// A percentage is invalid or unsupported by the action or device.
  case invalidLevel
  /// The main group doesn't support switching.
  case unsupportedControl
  /// The device's identity isn't known, and it didn't report one when asked, so the service
  /// can't tell what it does. No control was sent.
  case notIdentified
  /// The device rejected the modem because it isn't linked to it. No control took effect.
  case notLinked
  /// Another operation owns this service's admission gate. Nothing was queued.
  case busy
  /// The modem isn't connected, so nothing was sent. The service keeps reconnecting, and a
  /// later command can succeed.
  case modemUnavailable(ModemUnavailability)
  /// The network doesn't give out its ALL-Link databases, as a Hub Pro doesn't, so there is
  /// nothing to read. Nothing was sent.
  case databasesUnavailable
  /// The service holds no plan with that identifier for that scene: it never made one, or restarted
  /// since. Nothing was sent.
  case unknownPlan
  /// The plan is older than five minutes. Nothing was sent; plan again.
  case planExpired
  /// The plan was applied, so it can't be used again. Nothing was sent.
  case planAlreadyApplied
  /// The plan has a refusal or no steps, so it can't be applied. Nothing was sent.
  case planNotApplicable
  /// A database differs from what the plan was made from. Nothing was written; plan again.
  case planStale
  /// The consent doesn't agree to the writes. Nothing was sent.
  case consentRequired
  /// The consent names another plan than the one given. Nothing was sent.
  case consentMismatch
  /// A device didn't answer the read of the slot the first step writes, so nothing was written. The plan stays usable.
  case deviceNotAnswering
}

/// A service runtime failure, independent of its host.
public enum ServiceLifecycleError: Error {
  /// A runtime body is already active on this service.
  case alreadyRunning
  /// The modem's event stream ended while the runtime was active and the service doesn't
  /// reconnect.
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
  /// The modem isn't reachable. Events and device changes may be missed until the next
  /// ``modemReconnected``, and commands are refused.
  case modemUnavailable(ModemUnavailability)
  /// The modem is connected and its device information was read again. Anything heard while
  /// it was away is lost, so consumers refresh what they display.
  /// A notification rule fired. Numbered and retained like every other event.
  case notification(ServiceNotification)
  case modemReconnected
  /// A schedule or a timer ran, or a run was missed. Numbered and retained like every other event.
  case schedule(ScheduleRun)
  /// A scene ran. Numbered and retained like every other event. A scene run by a member's button or
  /// by the command line is not reported, because the modem does not report its own group sends.
  case scene(SceneRun)
  /// The ALL-Link records of a scene's members changed, or may have: a membership plan was applied, in
  /// whole or in part. Numbered and retained like every other event.
  case sceneChanged(SceneChanged)

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
