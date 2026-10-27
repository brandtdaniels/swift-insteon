/// Common commands sent to a single device in an extended-length direct message.
///
/// The user data that accompanies these commands is device-specific; build it with
/// ``UserData``.
public enum ExtendedDirectCommand: Hashable, Sendable {

  /// Reads or writes device configuration selected by the user data (cmd1 `0x2E`, cmd2 `0x00`).
  case extendedGetSet

  /// Reads or writes records in the device's ALL-Link database (cmd1 `0x2F`, cmd2 `0x00`).
  case readWriteAllLinkDatabase

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
    }

  }

}
