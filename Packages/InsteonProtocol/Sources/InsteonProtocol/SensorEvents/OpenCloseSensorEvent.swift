/// What an open/close sensor, such as a door or window sensor, reports to its groups, as
/// Insteon's heartbeat status sheet gives them.
public enum OpenCloseSensorEvent: Hashable, Sendable {

  /// It opened: on to group 1.
  case opened

  /// It closed: off to group 1.
  case closed

  /// The sensor's periodic heartbeat, to group 4, with its command: on, fast on, off or fast
  /// off (`0x11` to `0x14`). Insteon's heartbeat sheet says some sensors report their current
  /// state in it, which depends on the model.
  case heartbeat(command1: UInt8)

  /// Reads an open/close sensor's event from a group command.
  ///
  /// - Parameter command: A command the sensor sent.
  /// - Returns: `nil` if the command isn't one of the events above.
  public init?(_ command: GroupCommand) {

    switch (command.group.rawValue, command.command1) {
    case (0x01, 0x11): self = .opened
    case (0x01, 0x13): self = .closed
    case let (0x04, command1) where (0x11...0x14).contains(command1): self = .heartbeat(command1: command1)
    default: return nil
    }

  }

}
