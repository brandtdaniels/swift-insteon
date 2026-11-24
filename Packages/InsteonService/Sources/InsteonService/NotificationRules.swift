import Foundation
import InsteonProtocol

/// A rule the service evaluates against what devices report, such as "tell me when the basement
/// sensor reports wet".
///
/// The service keeps its rules, applies an edit to the next device report, and publishes a
/// ``ServiceEvent/notification(_:)`` each time a rule fires. How a notification reaches a person is
/// not the service's business: a separate process follows the event stream and delivers it.
public struct ServiceNotificationRule: Hashable, Sendable {
  /// The most rules the service keeps.
  public static let maximumCount = 64
  /// The longest cooldown a rule has: one week.
  public static let longestCooldownSeconds = 604_800
  /// The longest a rule's identifier or name is, in characters.
  public static let longestTextLength = 64

  /// What makes a rule fire.
  public enum Trigger: Hashable, Sendable {
    /// A device reports an event its product's profile names, such as `wet`.
    case event(String, device: InsteonAddress)
    /// A device sends a command to one of its groups, for a product whose profile names no event for it.
    /// A group is 1 through 255. A heartbeat is not a group command here.
    case groupCommand(command1: UInt8, group: Int, device: InsteonAddress)

    /// The device the trigger is about.
    public var device: InsteonAddress {
      switch self {
      case let .event(_, device), let .groupCommand(_, _, device): device
      }
    }
  }

  /// The rule's identifier: letters, digits, `-`, `_` and `.`, at most 64 characters. A client chooses it.
  public var id: String
  /// What people call the rule, such as `Basement leak`. 1 through 64 characters, without control characters.
  public var name: String
  /// What makes the rule fire.
  public var trigger: Trigger
  /// Seconds after firing during which the rule stays quiet, so a busy sensor doesn't notify on every pass.
  /// 0 lets it fire every time.
  public var cooldownSeconds: Int
  /// Whether the rule fires at all.
  public var isEnabled: Bool
  /// Whether a notification names the event that fired it. Off, a notification carries only the rule, the
  /// device and the time.
  public var includesDetail: Bool

  /// Creates a rule. The service validates it when it is stored.
  public init(id: String, name: String, trigger: Trigger, cooldownSeconds: Int = 0, isEnabled: Bool = true, includesDetail: Bool = false) {
    self.id = id
    self.name = name
    self.trigger = trigger
    self.cooldownSeconds = cooldownSeconds
    self.isEnabled = isEnabled
    self.includesDetail = includesDetail
  }
}

/// A rule that fired: what a notifier needs to deliver it, and nothing more.
///
/// A notification carries the rule, the device and the time. The event that fired the rule is named only
/// when the rule asks for it with ``ServiceNotificationRule/includesDetail``.
public struct ServiceNotification: Equatable, Sendable {
  /// The rule's identifier.
  public let ruleID: String
  /// The rule's name.
  public let ruleName: String
  /// The device that set the rule off.
  public let device: InsteonAddress
  /// When the rule fired.
  public let firedAt: Date
  /// The event's name, such as `wet`, when the rule includes detail and its trigger names an event.
  public let eventName: String?

  /// Creates a notification.
  public init(ruleID: String, ruleName: String, device: InsteonAddress, firedAt: Date, eventName: String?) {
    self.ruleID = ruleID
    self.ruleName = ruleName
    self.device = device
    self.firedAt = firedAt
    self.eventName = eventName
  }
}

/// Why a change to the rules was refused.
public enum NotificationRuleError: Error, Equatable, Sendable {
  /// The rule breaks a limit: its identifier, name, cooldown or trigger isn't one the service accepts.
  case invalidRule
  /// The rule's device isn't one the service knows.
  case unknownDevice
  /// No rule has that identifier.
  case unknownRule
  /// The service already keeps ``ServiceNotificationRule/maximumCount`` rules.
  case limitReached
  /// The rules couldn't be read or saved, so nothing changed.
  case notSaved
}

/// Where the rules live between runs.
public protocol NotificationRulePersisting: Sendable {
  /// The stored rules, or `nil` when none have been stored.
  func load() async throws -> [ServiceNotificationRule]?
  /// Replaces the stored rules.
  func save(_ rules: [ServiceNotificationRule]) async throws
}

/// The role of a service that keeps notification rules.
public protocol NotificationRuleManaging: Sendable {
  /// The rules, in the order they were added.
  func notificationRules() async throws -> [ServiceNotificationRule]
  /// Adds a rule, or replaces the rule with its identifier. A replacement with the same trigger keeps the
  /// rule's cooldown running. The change applies to the next device report.
  func putNotificationRule(_ rule: ServiceNotificationRule) async throws
  /// Removes a rule. It stops firing at once.
  func removeNotificationRule(id: String) async throws
}
