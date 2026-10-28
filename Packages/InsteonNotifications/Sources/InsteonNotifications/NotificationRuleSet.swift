import InsteonDeviceCatalog
import InsteonProtocol

/// A home's notification rules, and the notifications its devices set off.
///
/// Give the rule set each event a `DeviceEventInterpreter` reads, and now and then the
/// devices a `HeartbeatMonitor` finds silent. It returns the notifications to deliver, in the
/// order of its rules, leaving out disabled rules and rules still in their cooldown.
///
/// ```swift
/// var rules = NotificationRuleSet<ContinuousClock.Instant>(rules: [leak, door])
///
/// for event in interpreter.events(from: message, at: .now) {
///   for notification in rules.notifications(for: event, at: .now) {
///     await deliver(notification.rule.name)
///   }
/// }
///
/// // Now and then:
/// for notification in rules.notifications(forSilent: monitor.silentDevices(at: .now), at: .now) {
///   await deliver(notification.rule.name)
/// }
/// ```
///
/// The rule set keeps no clock of its own: give it the time each event arrived, from any
/// clock, so tests can use one they control.
public struct NotificationRuleSet<Instant: InstantProtocol>: Sendable where Instant.Duration == Duration, Instant: Sendable {

  /// The rules, in the order they were added.
  public private(set) var rules: [NotificationRule]

  /// When each rule last fired.
  private var lastFired: [NotificationRuleID: Instant] = [:]

  /// The silence rules whose device is still silent since they fired.
  private var silent: Set<NotificationRuleID> = []

  /// Creates a rule set.
  ///
  /// - Parameter rules: The rules. A rule with the same identifier as an earlier one replaces
  ///   it.
  public init(rules: [NotificationRule] = []) {

    self.rules = []

    for rule in rules {

      add(rule)

    }

  }

  /// The rule with an identifier.
  ///
  /// - Parameter id: The rule's identifier.
  /// - Returns: The rule, or `nil` if there's none with that identifier.
  public func rule(id: NotificationRuleID) -> NotificationRule? {

    rules.first { $0.id == id }

  }

  /// Adds a rule, or replaces the rule with its identifier and forgets when that one fired.
  ///
  /// - Parameter rule: The rule.
  public mutating func add(_ rule: NotificationRule) {

    if let index = rules.firstIndex(where: { $0.id == rule.id }) {

      rules[index] = rule
      forget(rule.id)

    } else {

      rules.append(rule)

    }

  }

  /// Removes a rule.
  ///
  /// - Parameter id: The rule's identifier.
  public mutating func remove(_ id: NotificationRuleID) {

    rules.removeAll { $0.id == id }
    forget(id)

  }

  /// The notifications an event sets off.
  ///
  /// - Parameters:
  ///   - event: An event a `DeviceEventInterpreter` read.
  ///   - instant: When the event arrived.
  /// - Returns: A notification for each enabled rule the event matches that isn't in its
  ///   cooldown, in the order of the rules.
  public mutating func notifications(for event: DeviceEvent, at instant: Instant) -> [DeviceNotification<Instant>] {

    fire(rules.filter { $0.trigger.matches(event) }, at: instant)

  }

  /// The notifications silent devices set off.
  ///
  /// A silence rule fires once when its device goes silent, and again only after the device
  /// has been heard from and gone silent again.
  ///
  /// - Parameters:
  ///   - devices: The devices a `HeartbeatMonitor` finds silent.
  ///   - instant: When the devices were checked.
  /// - Returns: A notification for each enabled silence rule whose device has gone silent
  ///   since it last fired and that isn't in its cooldown, in the order of the rules.
  public mutating func notifications(forSilent devices: [InsteonAddress], at instant: Instant) -> [DeviceNotification<Instant>] {

    let silentDevices = Set(devices)
    var newlySilent: [NotificationRule] = []

    for rule in rules {

      guard case let .silence(device) = rule.trigger else {

        continue

      }

      if !silentDevices.contains(device) {

        silent.remove(rule.id)

      } else if !silent.contains(rule.id) {

        newlySilent.append(rule)

      }

    }

    let notifications = fire(newlySilent, at: instant)
    silent.formUnion(notifications.map(\.rule.id))

    return notifications

  }

  /// Fires the rules that are enabled and out of their cooldown.
  private mutating func fire(_ candidates: [NotificationRule], at instant: Instant) -> [DeviceNotification<Instant>] {

    var notifications: [DeviceNotification<Instant>] = []

    for rule in candidates where rule.isEnabled {

      if let last = lastFired[rule.id], last.duration(to: instant) < rule.cooldown {

        continue

      }

      lastFired[rule.id] = instant
      notifications.append(DeviceNotification(rule: rule, instant: instant))

    }

    return notifications

  }

  /// Forgets when a rule fired.
  private mutating func forget(_ id: NotificationRuleID) {

    lastFired[id] = nil
    silent.remove(id)

  }

}

/// A notification a rule set off, for the app to deliver.
public struct DeviceNotification<Instant: InstantProtocol>: Hashable, Sendable {

  /// The rule that fired.
  public var rule: NotificationRule

  /// When it fired.
  public var instant: Instant

  /// Creates a notification.
  ///
  /// - Parameters:
  ///   - rule: The rule that fired.
  ///   - instant: When it fired.
  public init(rule: NotificationRule, instant: Instant) {

    self.rule = rule
    self.instant = instant

  }

  /// The device the notification is about.
  public var device: InsteonAddress { rule.trigger.device }

}
