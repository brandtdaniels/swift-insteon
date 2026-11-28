import Foundation
import InsteonCore
import InsteonService

/// Versioning and coding are transport policy, separate from the service's domain values.
struct DeviceListDTO: Encodable {
  let version = 1
  let devices: [DeviceDTO]
  /// Whether the values come from saved information because the modem is away.
  let stale: Bool
  let cause: String?
  init(_ devices: [ServiceDevice], modem: ModemConnectionState = .connected) {
    self.devices = devices.map(DeviceDTO.init)
    stale = modem.cause != nil
    cause = modem.cause?.wireName
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(version, forKey: .version)
    try container.encode(devices, forKey: .devices)
    try container.encode(stale, forKey: .stale)
    try container.encode(cause, forKey: .cause)
  }
  private enum CodingKeys: String, CodingKey { case version, devices, stale, cause }
}

/// A failed API request: a code to branch on, whether a command may have reached a device, and an
/// explanation, with the request id the log record carries.
struct ErrorDTO: Encodable {
  let version = 1
  let code: String
  let message: String
  let sent: Bool
  let requestId: String
  /// Why the modem is away, present only for `modemUnavailable`.
  let cause: String?

  init(_ failure: HTTPFailure, requestID: String) {
    code = failure.code.rawValue
    message = failure.message
    sent = failure.sent
    requestId = requestID
    cause = failure.modemUnavailability?.wireName
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(version, forKey: .version)
    try container.encode(code, forKey: .code)
    try container.encode(message, forKey: .message)
    try container.encode(sent, forKey: .sent)
    try container.encode(requestId, forKey: .requestId)
    try container.encodeIfPresent(cause, forKey: .cause)
  }
  private enum CodingKeys: String, CodingKey { case version, code, message, sent, requestId, cause }
}

/// Readiness without device addresses, names or the Hub's location.
struct HealthDTO: Encodable {
  let version = 1
  let status: String
  let modem: Modem
  let lastExchangeAgeSeconds: Int?
  let lastPollAgeSeconds: Int?
  let snapshotAgeSeconds: Int?
  let persistence: String
  let notes: [Note]
  let tuning: [TuningValue]

  /// One tuning value in use, and where it came from.
  struct TuningValue: Encodable {
    let name: String
    let value: Int
    let unit = "ms"
    let source: String
  }

  /// Something worth knowing that doesn't change what the service can do.
  struct Note: Encodable {
    let code: String
    let message: String
  }

  struct Modem: Encodable {
    let connected: Bool
    let cause: String?
    func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(connected, forKey: .connected)
      try container.encode(cause, forKey: .cause)
    }
    private enum CodingKeys: String, CodingKey { case connected, cause }
  }

  init(_ health: ServiceHealth) {
    switch health.readiness {
    case .starting: status = HealthStatusName.starting.rawValue
    case .ready: status = HealthStatusName.ready.rawValue
    case .degraded: status = HealthStatusName.degraded.rawValue
    }
    modem = Modem(connected: health.modem == .connected, cause: health.modem.cause?.wireName)
    func age(_ date: Date?) -> Int? { date.map { max(0, Int(health.checkedAt.timeIntervalSince($0))) } }
    lastExchangeAgeSeconds = age(health.lastHardwareExchange)
    lastPollAgeSeconds = age(health.lastPoll)
    snapshotAgeSeconds = age(health.deviceInformationUpdated)
    persistence = PersistenceName(health.persistence).rawValue
    tuning = health.tuning.map { TuningValue(name: $0.name, value: $0.milliseconds, source: $0.source.rawValue) }
    notes = health.notes.map { note in
      switch note {
      case .timeZoneUnavailable: Note(code: HealthNoteCode.timeZoneUnavailable.rawValue, message: "The configured time zone isn't in this host's time zone database, so schedules with a time of day are refused.")
      case let .hubClockDrift(seconds): Note(code: HealthNoteCode.hubClockDrift.rawValue, message: "The Hub's clock differs from the service's by \(abs(seconds)) seconds. The service never changes a Hub's clock.")
      }
    }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(version, forKey: .version)
    try container.encode(status, forKey: .status)
    try container.encode(modem, forKey: .modem)
    try container.encode(lastExchangeAgeSeconds, forKey: .lastExchangeAgeSeconds)
    try container.encode(lastPollAgeSeconds, forKey: .lastPollAgeSeconds)
    try container.encode(snapshotAgeSeconds, forKey: .snapshotAgeSeconds)
    try container.encode(persistence, forKey: .persistence)
    try container.encode(notes, forKey: .notes)
    try container.encode(tuning, forKey: .tuning)
  }
  private enum CodingKeys: String, CodingKey { case version, status, modem, lastExchangeAgeSeconds, lastPollAgeSeconds, snapshotAgeSeconds, persistence, notes, tuning }
}

struct DeviceDTO: Encodable {
  let address: String
  let productName: String?
  let canTurnOnAndOff: Bool
  let canDim: Bool
  let value: UInt8?
  let lastAnsweredAt: Date?
  init(_ device: ServiceDevice) {
    address = device.address.description; productName = device.productName
    canTurnOnAndOff = device.canTurnOnAndOff; canDim = device.canDim
    value = device.value; lastAnsweredAt = device.lastAnsweredAt
  }
}

struct StatusDTO: Encodable {
  let group: Int?
  let kind: String
  let value: UInt8
  let isOn: Bool
  let percent: Int?
  let label: String?
  init(_ status: DeviceStatus) {
    group = status.group; value = status.value; isOn = status.isOn
    switch status.reading {
    case let .percent(number): kind = ReadingKind.percent.rawValue; percent = number; label = nil
    case .onOff: kind = ReadingKind.onOff.rawValue; percent = nil; label = nil
    case let .named(name): kind = ReadingKind.named.rawValue; percent = nil; label = name
    case .raw: kind = ReadingKind.raw.rawValue; percent = nil; label = nil
    }
  }
}

/// What a client's request for a scene says to do, and what the `scene` event reports.
enum HTTPSceneAction: String, Decodable, CaseIterable, Sendable { case on, off }

/// A scene's answer to a command. `acknowledged` means the modem acknowledged sending the group
/// command; each member's own cleanup is in `acknowledged` and `unacknowledged`.
struct SceneReceiptDTO: Encodable {
  let version = 1
  let scene: Int
  let action: String
  let outcome = ReceiptOutcome.acknowledged.rawValue
  let acknowledged: [String]
  let unacknowledged: [String]
  let isComplete: Bool
  let responderCount: Int
  let persistence: String
  init(_ receipt: SceneReceipt) {
    scene = Int(receipt.scene)
    action = (receipt.action == .on ? HTTPSceneAction.on : .off).rawValue
    acknowledged = receipt.acknowledged.map(\.description)
    unacknowledged = receipt.unacknowledged.map(\.description)
    isComplete = receipt.isComplete
    responderCount = receipt.responderCount
    persistence = PersistenceName(receipt.persistence).rawValue
  }
}

struct ReceiptDTO: Encodable {
  let version = 1
  let address: String
  let outcome: String
  let status: StatusDTO?
  let persistence: String
  init(_ receipt: CommandReceipt) {
    address = receipt.address.description
    outcome = (receipt.outcome == .acknowledged ? ReceiptOutcome.acknowledged : .read).rawValue
    status = receipt.status.map(StatusDTO.init)
    persistence = PersistenceName(receipt.persistence).rawValue
  }
}

/// Tells a reconnecting client that events it missed can't be replayed, so it refreshes everything.
struct GapDTO: Encodable {
  let version = 1
  let kind = EventKind.gap.rawValue
  let reason: String
  let runId: String
  let sequence: UInt64
  init(reason: EventGapReason, current: EventCursor) {
    self.reason = reason.rawValue
    runId = current.runID
    sequence = current.sequence
  }
}

struct EventDTO: Encodable {
  let version = 1
  let runId: String
  let sequence: UInt64
  let kind: String
  let address: String?
  let group: Int?
  let name: String?
  let productName: String?
  let completion: CommandCompletionDTO?
  let cause: String?
  let ruleId: String?
  let ruleName: String?
  let firedAt: String?
  let message: String?
  let scheduleId: String?
  let source: String?
  let outcome: String?
  let reason: String?
  let nextRun: String?
  let scene: Int?
  let action: String?
  let acknowledged: [String]?
  let unacknowledged: [String]?
  let isComplete: Bool?
  /// On `sceneMembership`: how many steps of the applied plan were made, and how many were not.
  let stepsMade: Int?
  let stepsNotMade: Int?
  init(_ event: ServiceEvent, at position: EventCursor) {
    runId = position.runID
    sequence = position.sequence
    switch event {
    case let .notification(note):
      ruleId = note.ruleID; ruleName = note.ruleName
      firedAt = ISO8601DateFormatter().string(from: note.firedAt)
    case let .schedule(run):
      ruleId = nil; ruleName = nil
      firedAt = ISO8601DateFormatter().string(from: run.firedAt)
    case let .scene(run):
      ruleId = nil; ruleName = nil
      firedAt = ISO8601DateFormatter().string(from: run.firedAt)
    case let .sceneChanged(changed):
      ruleId = nil; ruleName = nil
      firedAt = ISO8601DateFormatter().string(from: changed.firedAt)
    default:
      ruleId = nil; ruleName = nil; firedAt = nil
    }
    switch event {
    case let .modemUnavailable(reason): cause = reason.wireName; message = reason.notice
    case let .schedule(run):
      if case let .unavailable(reason) = run.outcome { cause = reason.wireName; message = reason.notice } else { cause = nil; message = nil }
    default: cause = nil; message = nil
    }
    if case let .schedule(run) = event {
      scheduleId = run.id
      source = (run.source == .timer ? ScheduleSourceName.timer : .schedule).rawValue
      switch run.outcome {
      case .acknowledged: outcome = ScheduleOutcomeName.acknowledged.rawValue; reason = nil
      case .missed: outcome = ScheduleOutcomeName.missed.rawValue; reason = nil
      case .unavailable: outcome = ScheduleOutcomeName.unavailable.rawValue; reason = nil
      case let .refused(error): outcome = ScheduleOutcomeName.refused.rawValue; reason = HTTPFailure(error).code.rawValue
      case .unknown: outcome = ScheduleOutcomeName.unknown.rawValue; reason = nil
      }
      nextRun = run.nextRun.map { ISO8601DateFormatter().string(from: $0) }
    } else if case .scene = event {
      scheduleId = nil; source = SceneSourceName.api.rawValue; outcome = nil; reason = nil; nextRun = nil
    } else if case let .sceneChanged(changed) = event {
      scheduleId = nil; source = SceneSourceName.api.rawValue; reason = nil; nextRun = nil
      switch changed.outcome {
      case .applied: outcome = "applied"
      case .appliedUnverified: outcome = "appliedUnverified"
      case .incomplete: outcome = "incomplete"
      }
    } else {
      scheduleId = nil; source = nil; outcome = nil; reason = nil; nextRun = nil
    }
    if case let .scene(run) = event {
      scene = Int(run.number)
      action = run.action == .on ? HTTPSceneAction.on.rawValue : HTTPSceneAction.off.rawValue
      acknowledged = run.receipt.acknowledged.map(\.description)
      unacknowledged = run.receipt.unacknowledged.map(\.description)
      isComplete = run.receipt.isComplete
      stepsMade = nil; stepsNotMade = nil
    } else if case let .sceneChanged(changed) = event {
      scene = Int(changed.number)
      action = nil; acknowledged = nil; unacknowledged = nil; isComplete = nil
      stepsMade = changed.stepsMade; stepsNotMade = changed.stepsNotMade
    } else {
      scene = nil; action = nil; acknowledged = nil; unacknowledged = nil; isComplete = nil; stepsMade = nil; stepsNotMade = nil
    }
    if case let .commandCompleted(command, receipt) = event {
      completion = CommandCompletionDTO(command: command, receipt: receipt)
    } else {
      completion = nil
    }
    switch event {
    case let .commandCompleted(command, _):
      kind = EventKind.commandCompleted.rawValue; address = command.address.description; group = nil; name = nil; productName = nil
    case let .identified(address, productName):
      kind = EventKind.identified.rawValue; self.address = address.description; group = nil; name = nil; self.productName = productName
    case let .setButtonPressed(address):
      kind = EventKind.setButtonPressed.rawValue; self.address = address.description; group = nil; name = nil; productName = nil
    case let .groupCommand(address, group, name):
      kind = EventKind.groupCommand.rawValue; self.address = address.description; self.group = group; self.name = name; productName = nil
    case let .heartbeat(address, group):
      kind = EventKind.heartbeat.rawValue; self.address = address.description; self.group = group; name = nil; productName = nil
    case let .statusChanged(address):
      kind = EventKind.statusChanged.rawValue; self.address = address.description; group = nil; name = nil; productName = nil
    case .modemUnavailable:
      kind = EventKind.modemUnavailable.rawValue; address = nil; group = nil; name = nil; productName = nil
    case .modemReconnected:
      kind = EventKind.reconnected.rawValue; address = nil; group = nil; name = nil; productName = nil
    case let .notification(note):
      kind = EventKind.notification.rawValue; address = note.device.description; group = nil; name = note.eventName; productName = nil
    case let .schedule(run):
      kind = EventKind.schedule.rawValue; address = run.device.description; group = nil; name = run.name; productName = nil
    case let .scene(run):
      kind = EventKind.scene.rawValue; address = nil; group = nil; name = run.name; productName = nil
    case .sceneChanged:
      kind = EventKind.sceneMembership.rawValue; address = nil; group = nil; name = nil; productName = nil
    }
  }
}

struct CommandCompletionDTO: Encodable {
  let action: String
  let levelPercent: Int?
  let result: ReceiptDTO

  init(command: ServiceCommand, receipt: CommandReceipt) {
    switch command.action {
    case .identify: action = HTTPCommand.Action.identify.rawValue
    case .status: action = HTTPCommand.Action.status.rawValue
    case .on: action = HTTPCommand.Action.on.rawValue
    case .off: action = HTTPCommand.Action.off.rawValue
    }
    levelPercent = command.levelPercent
    result = ReceiptDTO(receipt)
  }
}
