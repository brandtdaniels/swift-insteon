/// What an open/close sensor, such as a door or window sensor, reports to its groups, as
/// Insteon's heartbeat status sheet gives them.
public enum OpenCloseSensorEvent: Hashable, Sendable {

  /// It opened: on to group 1.
  case opened

  /// It closed: off to group 1.
  case closed

  /// The sensor's periodic heartbeat, to group 4.
  case heartbeat

  /// Reads an open/close sensor's event from a group command.
  ///
  /// - Parameter command: A command the sensor sent.
  /// - Returns: `nil` if the command isn't one of the events above.
  public init?(_ command: GroupCommand) {

    switch (command.group.rawValue, command.command1) {
    case (0x01, 0x11): self = .opened
    case (0x01, 0x13): self = .closed
    case (0x04, _): self = .heartbeat
    default: return nil
    }

  }

}
