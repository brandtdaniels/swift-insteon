/// What a Smoke Bridge reports to its groups when the smoke and CO alarms it listens to
/// change, as Insteon's Smoke command sheet gives them. Each event is an on to its group.
public enum SmokeBridgeEvent: Hashable, Sendable {

  /// Smoke was detected: group 1.
  case smoke

  /// Carbon monoxide was detected: group 2.
  case carbonMonoxide

  /// An alarm is being tested: group 3.
  case test

  /// An alarm the bridge doesn't recognize sounded: group 4.
  case unknownAlarm

  /// The alarms are clear: group 5.
  case clear

  /// An alarm's battery is low: group 6.
  case lowBattery

  /// An alarm reports a malfunction: group 7.
  case malfunction

  /// The bridge's periodic heartbeat: group `0x0A`.
  case heartbeat

  /// Reads a Smoke Bridge's event from a group command.
  ///
  /// - Parameter command: A command the bridge sent.
  /// - Returns: `nil` if the command isn't an on, or a heartbeat, to one of the groups above.
  public init?(_ command: GroupCommand) {

    if command.group == 0x0A {

      self = .heartbeat

      return

    }

    guard command.command1 == 0x11 else {

      return nil

    }

    switch command.group.rawValue {
    case 0x01: self = .smoke
    case 0x02: self = .carbonMonoxide
    case 0x03: self = .test
    case 0x04: self = .unknownAlarm
    case 0x05: self = .clear
    case 0x06: self = .lowBattery
    case 0x07: self = .malfunction
    default: return nil
    }

  }

}
