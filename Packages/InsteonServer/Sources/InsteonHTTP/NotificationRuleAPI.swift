import Foundation
import Hummingbird
import HTTPTypes
import InsteonProtocol
import InsteonService

/// Listing, storing and removing notification rules. Reading needs the `read` scope and writing the
/// `admin` scope, which the authentication middleware has already enforced.
struct NotificationRuleAPI<Service: NotificationRuleManaging>: Sendable {
  let service: Service

  func list() async throws -> Response {
    try json(NotificationRuleListDTO(rules: try await service.notificationRules().map(NotificationRuleRecord.init)))
  }

  func put(_ request: Request, id: String?) async throws -> Response {
    guard HTTPBody.mediaType(request) == "application/json" else { throw HTTPInputError.unsupportedMedia }
    try HTTPBody.requireMarker(request)
    guard let id else { throw NotificationRuleRequestError.malformed }
    let body = try NotificationRuleBody(try await HTTPBody.read(request))
    let rule = try body.rule(id: id)
    try await service.putNotificationRule(rule)
    return try json(NotificationRuleStoredDTO(rule: NotificationRuleRecord(rule)))
  }

  func remove(_ request: Request, id: String?) async throws -> Response {
    try HTTPBody.requireMarker(request)
    guard let id else { throw NotificationRuleError.unknownRule }
    try await service.removeNotificationRule(id: id)
    return Response(status: .noContent)
  }

  private func json(_ value: some Encodable) throws -> Response {
    let encoder = JSONEncoder()
    return Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(bytes: try encoder.encode(value))))
  }
}

/// A request body that isn't a rule.
enum NotificationRuleRequestError: Error { case malformed }

/// A notification rule as the API and the rules file write it.
public struct NotificationRuleRecord: Codable, Sendable, Equatable {
  /// What makes the rule fire.
  public struct Trigger: Codable, Sendable, Equatable {
    /// `event` or `groupCommand`.
    public let kind: String
    /// The event's name, for an `event` trigger.
    public let event: String?
    /// The command, for a `groupCommand` trigger.
    public let command1: Int?
    /// The group, for a `groupCommand` trigger.
    public let group: Int?
    /// The device's address.
    public let device: String
  }

  /// The rule's identifier.
  public let id: String
  /// The rule's name.
  public let name: String
  /// What makes the rule fire.
  public let trigger: Trigger
  /// Seconds the rule stays quiet after it fires.
  public let cooldownSeconds: Int
  /// Whether the rule fires at all.
  public let enabled: Bool
  /// Whether a notification names the event.
  public let includeDetail: Bool

  /// Writes a rule.
  public init(_ rule: ServiceNotificationRule) {
    id = rule.id
    name = rule.name
    switch rule.trigger {
    case let .event(name, device):
      trigger = Trigger(kind: NotificationTriggerKind.event.rawValue, event: name, command1: nil, group: nil, device: device.description)
    case let .groupCommand(command1, group, device):
      trigger = Trigger(kind: NotificationTriggerKind.groupCommand.rawValue, event: nil, command1: Int(command1), group: group, device: device.description)
    }
    cooldownSeconds = rule.cooldownSeconds
    enabled = rule.isEnabled
    includeDetail = rule.includesDetail
  }

  /// The rule this record describes.
  /// - Throws: ``NotificationRuleRequestError`` when the record isn't a rule.
  public func rule() throws -> ServiceNotificationRule {
    try Self.rule(id: id, name: name, trigger: trigger, cooldownSeconds: cooldownSeconds, enabled: enabled, includeDetail: includeDetail)
  }

  static func rule(id: String, name: String, trigger: Trigger, cooldownSeconds: Int, enabled: Bool, includeDetail: Bool) throws -> ServiceNotificationRule {
    guard let device = InsteonAddress(trigger.device) else { throw NotificationRuleRequestError.malformed }
    let converted: ServiceNotificationRule.Trigger
    switch NotificationTriggerKind(rawValue: trigger.kind) {
    case .event:
      guard let event = trigger.event, trigger.command1 == nil, trigger.group == nil else { throw NotificationRuleRequestError.malformed }
      converted = .event(event, device: device)
    case .groupCommand:
      guard trigger.event == nil, let command1 = trigger.command1.flatMap({ UInt8(exactly: $0) }), let group = trigger.group else { throw NotificationRuleRequestError.malformed }
      converted = .groupCommand(command1: command1, group: group, device: device)
    case nil:
      throw NotificationRuleRequestError.malformed
    }
    return ServiceNotificationRule(id: id, name: name, trigger: converted, cooldownSeconds: cooldownSeconds, isEnabled: enabled, includesDetail: includeDetail)
  }
}

/// What the rules file holds.
public struct NotificationRuleRegistry: Codable, Sendable, Equatable {
  /// The file's format.
  public var version = 1
  /// The rules, in the order they were added.
  public var rules: [NotificationRuleRecord]

  /// Creates a registry.
  public init(rules: [NotificationRuleRecord]) { self.rules = rules }
}

/// The body of a request to store a rule. Unknown fields, at any level, are refused.
struct NotificationRuleBody {
  private let name: String
  private let trigger: NotificationRuleRecord.Trigger
  private let cooldownSeconds: Int
  private let enabled: Bool
  private let includeDetail: Bool

  init(_ data: Data) throws {
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          Set(object.keys).isSubset(of: ["name", "trigger", "cooldownSeconds", "enabled", "includeDetail"]),
          let name = object["name"] as? String, let triggerObject = object["trigger"] as? [String: Any] else { throw NotificationRuleRequestError.malformed }
    self.name = name
    trigger = try Self.trigger(triggerObject)
    cooldownSeconds = try object["cooldownSeconds"].map { try Self.integer($0) } ?? 0
    enabled = try object["enabled"].map { try Self.boolean($0) } ?? true
    includeDetail = try object["includeDetail"].map { try Self.boolean($0) } ?? false
  }

  func rule(id: String) throws -> ServiceNotificationRule {
    try NotificationRuleRecord.rule(id: id, name: name, trigger: trigger, cooldownSeconds: cooldownSeconds, enabled: enabled, includeDetail: includeDetail)
  }

  private static func trigger(_ object: [String: Any]) throws -> NotificationRuleRecord.Trigger {
    guard let kind = object["kind"] as? String, let device = object["device"] as? String else { throw NotificationRuleRequestError.malformed }
    switch NotificationTriggerKind(rawValue: kind) {
    case .event:
      guard Set(object.keys) == ["kind", "event", "device"], let event = object["event"] as? String else { throw NotificationRuleRequestError.malformed }
      return .init(kind: kind, event: event, command1: nil, group: nil, device: device)
    case .groupCommand:
      guard Set(object.keys) == ["kind", "command1", "group", "device"] else { throw NotificationRuleRequestError.malformed }
      let command1 = try integer(object["command1"] as Any)
      guard (0...255).contains(command1) else { throw NotificationRuleRequestError.malformed }
      return .init(kind: kind, event: nil, command1: command1, group: try integer(object["group"] as Any), device: device)
    case nil:
      throw NotificationRuleRequestError.malformed
    }
  }

  private static func integer(_ value: Any) throws -> Int {
    guard let number = value as? NSNumber, String(cString: number.objCType) != "c", number.doubleValue == Double(number.intValue) else { throw NotificationRuleRequestError.malformed }
    return number.intValue
  }

  private static func boolean(_ value: Any) throws -> Bool {
    guard let number = value as? NSNumber, String(cString: number.objCType) == "c" else { throw NotificationRuleRequestError.malformed }
    return number.boolValue
  }
}

struct NotificationRuleListDTO: Encodable {
  let version = 1
  let rules: [NotificationRuleRecord]
}

struct NotificationRuleStoredDTO: Encodable {
  let version = 1
  let rule: NotificationRuleRecord
}
