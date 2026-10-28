import InsteonDeviceCatalog
import InsteonProtocol

/// A rule that someone wants to hear about something a device does, such as a leak sensor
/// turning wet, a door opening or a sensor going quiet.
///
/// A ``NotificationRuleSet`` checks a home's devices against its rules. How a notification
/// reaches people, such as a push notification or an email, is up to the app.
///
/// ```swift
/// let leak = NotificationRule(id: "basement-leak", name: "Basement leak", trigger: .event("wet", from: basementSensor))
/// let door = NotificationRule(id: "front-door", name: "Front door opened", trigger: .event("opened", from: frontDoor), cooldown: .seconds(300))
/// ```
public struct NotificationRule: Hashable, Sendable, Identifiable {

  /// The rule's identifier, which the app chooses and keeps.
  public var id: NotificationRuleID

  /// What people call the rule, such as "Basement leak".
  public var name: String

  /// What makes the rule fire.
  public var trigger: NotificationTrigger

  /// How long after firing the rule stays quiet, so a busy motion sensor doesn't notify on
  /// every pass. Zero, or less, lets it fire every time.
  public var cooldown: Duration

  /// Whether the rule fires at all.
  public var isEnabled: Bool

  /// Creates a rule.
  ///
  /// - Parameters:
  ///   - id: The rule's identifier.
  ///   - name: What people call the rule.
  ///   - trigger: What makes the rule fire.
  ///   - cooldown: How long after firing the rule stays quiet. Defaults to zero.
  ///   - isEnabled: Whether the rule fires at all. Defaults to `true`.
  public init(id: NotificationRuleID, name: String, trigger: NotificationTrigger, cooldown: Duration = .zero, isEnabled: Bool = true) {

    self.id = id
    self.name = name
    self.trigger = trigger
    self.cooldown = cooldown
    self.isEnabled = isEnabled

  }

}

/// A notification rule's identifier, such as `"basement-leak"`.
public struct NotificationRuleID: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {

  /// The identifier.
  public let rawValue: String

  /// Creates an identifier.
  ///
  /// - Parameter rawValue: The identifier.
  public init(rawValue: String) {

    self.rawValue = rawValue

  }

  /// Creates an identifier from a string literal.
  ///
  /// - Parameter value: The identifier.
  public init(stringLiteral value: String) {

    self.init(rawValue: value)

  }

  /// The identifier.
  public var description: String { rawValue }

}

/// What makes a ``NotificationRule`` fire.
public enum NotificationTrigger: Hashable, Sendable {

  /// A device sends a group command its device profile names, such as a leak sensor's `wet`
  /// or a door sensor's `opened`.
  case event(DeviceEventName, from: InsteonAddress)

  /// A device sends a command to one of its groups, for a product whose profile names none,
  /// such as a switch turning on (cmd1 `0x11`) or off (cmd1 `0x13`) from its paddle. It
  /// matches whatever the profile calls the command, and a command to the profile's
  /// heartbeat group too.
  case groupCommand(command1: UInt8, group: AllLinkGroupNumber, from: InsteonAddress)

  /// A device goes silent: a `HeartbeatMonitor` watching it hasn't heard from it for longer
  /// than its allowance. The rule fires once each time the device goes silent; if that's
  /// during the rule's cooldown, it fires at the first check after the cooldown, should the
  /// device still be silent.
  case silence(of: InsteonAddress)

  /// The device the trigger is about.
  public var device: InsteonAddress {

    switch self {
    case let .event(_, device), let .groupCommand(_, _, device), let .silence(device):
      device
    }

  }

  /// Whether a device event sets the trigger off.
  ///
  /// - Parameter event: An event a `DeviceEventInterpreter` read.
  /// - Returns: Whether the event is a group command the trigger names. A silence trigger
  ///   never matches an event.
  public func matches(_ event: DeviceEvent) -> Bool {

    switch (self, event) {
    case let (.event(eventName, device), .groupCommand(command, name)):
      return command.controller == device && name == eventName
    case let (.groupCommand(command1, group, device), .groupCommand(command, _)),
         let (.groupCommand(command1, group, device), .heartbeat(command)):
      return command.controller == device && command.group == group && command.command1 == command1
    default:
      return false
    }

  }

}
