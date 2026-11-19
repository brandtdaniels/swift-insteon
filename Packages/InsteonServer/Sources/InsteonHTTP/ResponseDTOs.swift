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
  }
  private enum CodingKeys: String, CodingKey { case version, status, modem, lastExchangeAgeSeconds, lastPollAgeSeconds, snapshotAgeSeconds, persistence }
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
  let message: String?
  init(_ event: ServiceEvent, at position: EventCursor) {
    runId = position.runID
    sequence = position.sequence
    switch event {
    case let .modemUnavailable(reason): cause = reason.wireName; message = reason.notice
    default: cause = nil; message = nil
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
