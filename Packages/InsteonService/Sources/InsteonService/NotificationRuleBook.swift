import Foundation
import InsteonDeviceCatalog
import InsteonNotifications
import InsteonProtocol

/// A moment on the service's wall clock, which is what the rule set measures cooldowns against.
struct ServiceInstant: InstantProtocol, Sendable {
  var date: Date

  func advanced(by duration: Duration) -> ServiceInstant {
    ServiceInstant(date: date.addingTimeInterval(Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18))
  }

  func duration(to other: ServiceInstant) -> Duration {
    .seconds(other.date.timeIntervalSince(date))
  }

  static func < (left: ServiceInstant, right: ServiceInstant) -> Bool { left.date < right.date }
}

/// The service's rules and the state of their cooldowns.
struct NotificationRuleBook: Sendable {
  private(set) var rules: [ServiceNotificationRule]
  private var set: NotificationRuleSet<ServiceInstant>

  init(rules: [ServiceNotificationRule] = []) {
    self.rules = []
    set = NotificationRuleSet()
    for rule in rules { put(rule) }
  }

  func contains(_ id: String) -> Bool { rules.contains { $0.id == id } }

  /// Adds a rule or replaces the rule with its identifier. The rule set keeps a replaced rule's cooldown when
  /// its trigger is the same.
  mutating func put(_ rule: ServiceNotificationRule) {
    if let index = rules.firstIndex(where: { $0.id == rule.id }) { rules[index] = rule } else { rules.append(rule) }
    set.add(Self.rule(rule))
  }

  mutating func remove(_ id: String) {
    rules.removeAll { $0.id == id }
    set.remove(NotificationRuleID(rawValue: id))
  }

  /// The notifications a device event sets off at `date`.
  mutating func notifications(for event: DeviceEvent, at date: Date) -> [ServiceNotification] {
    set.notifications(for: event, at: ServiceInstant(date: date)).compactMap { fired in
      guard let rule = rules.first(where: { $0.id == fired.rule.id.rawValue }) else { return nil }
      var eventName: String?
      if rule.includesDetail, case let .event(name, _) = rule.trigger { eventName = name }
      return ServiceNotification(ruleID: rule.id, ruleName: rule.name, device: fired.device, firedAt: date, eventName: eventName)
    }
  }

  private static func rule(_ rule: ServiceNotificationRule) -> NotificationRule {
    let trigger: NotificationTrigger
    switch rule.trigger {
    case let .event(name, device):
      trigger = .event(DeviceEventName(rawValue: name), from: device)
    case let .groupCommand(command1, group, device):
      trigger = .groupCommand(command1: command1, group: AllLinkGroupNumber(rawValue: UInt8(clamping: group)), from: device)
    }
    return NotificationRule(id: NotificationRuleID(rawValue: rule.id), name: rule.name, trigger: trigger, cooldown: .seconds(rule.cooldownSeconds), isEnabled: rule.isEnabled)
  }
}
