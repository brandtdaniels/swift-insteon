/// Common commands sent to a single device in an extended-length direct message.
///
/// The user data that accompanies these commands is device-specific; build it with
/// ``UserData``.
public enum ExtendedDirectCommand: Hashable, Sendable {

  /// Reads or writes device configuration selected by the user data (cmd1 `0x2E`, cmd2 `0x00`).
  case extendedGetSet

  /// Reads or writes records in the device's ALL-Link database (cmd1 `0x2F`, cmd2 `0x00`).
  case readWriteAllLinkDatabase

  /// Makes a device act as if one of its ALL-Link groups were triggered (cmd1 `0x30`, cmd2 `0x00`).
  ///
  /// D1 is the group. When D2 is `0x01`, D3 is the on-level to use locally instead of the
  /// device's own; D4 and D5 are the cmd1 and cmd2 to send to the group; and D6 selects the
  /// local ramp rate, `0x00` for the device's own or `0x01` for instant. The two devices must
  /// be linked.
  case triggerAllLinkGroup

}

// MARK: - CommandConvertible

extension ExtendedDirectCommand: CommandConvertible {

  /// The command's cmd1 and cmd2 bytes.
  public var command: Command {

    switch self {
    case .extendedGetSet:
      Command(command1: 0x2E)
    case .readWriteAllLinkDatabase:
      Command(command1: 0x2F)
    case .triggerAllLinkGroup:
      Command(command1: 0x30)
    }

  }

}
