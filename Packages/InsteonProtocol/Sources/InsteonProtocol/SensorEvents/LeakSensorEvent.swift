/// What a leak sensor reports to its groups, as Insteon's heartbeat status sheet gives them.
public enum LeakSensorEvent: Hashable, Sendable {

  /// No water: on to group 1.
  case dry

  /// Water was detected: on to group 2.
  case wet

  /// The sensor's periodic heartbeat, to group 4.
  case heartbeat

  /// Reads a leak sensor's event from a group command.
  ///
  /// - Parameter command: A command the sensor sent.
  /// - Returns: `nil` if the command isn't one of the events above.
  public init?(_ command: GroupCommand) {

    switch (command.group.rawValue, command.command1) {
    case (0x01, 0x11): self = .dry
    case (0x02, 0x11): self = .wet
    case (0x04, _): self = .heartbeat
    default: return nil
    }

  }

}
