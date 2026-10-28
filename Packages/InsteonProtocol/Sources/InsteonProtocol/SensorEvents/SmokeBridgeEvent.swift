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

  /// The bridge's periodic heartbeat, to group `0x0A`, with its command: on, fast on, off or
  /// fast off (`0x11` to `0x14`).
  case heartbeat(command1: UInt8)

  /// Reads a Smoke Bridge's event from a group command.
  ///
  /// - Parameter command: A command the bridge sent.
  /// - Returns: `nil` if the command isn't one of the events above.
  public init?(_ command: GroupCommand) {

    switch (command.group.rawValue, command.command1) {
    case (0x01, 0x11): self = .smoke
    case (0x02, 0x11): self = .carbonMonoxide
    case (0x03, 0x11): self = .test
    case (0x04, 0x11): self = .unknownAlarm
    case (0x05, 0x11): self = .clear
    case (0x06, 0x11): self = .lowBattery
    case (0x07, 0x11): self = .malfunction
    case let (0x0A, command1) where (0x11...0x14).contains(command1): self = .heartbeat(command1: command1)
    default: return nil
    }

  }

}
