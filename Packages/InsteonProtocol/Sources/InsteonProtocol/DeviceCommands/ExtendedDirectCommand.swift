/// Common commands sent to a single device in an extended-length direct message.
///
/// The user data that accompanies these commands is device-specific; build it with
/// ``UserData``.
public enum ExtendedDirectCommand: Hashable, Sendable {

  /// Reads or writes device configuration selected by the user data (cmd1 `0x2E`).
  ///
  /// Most devices expect `variant` `0x00`. Some define others for their own data, such as
  /// `0x02`, which reads a thermostat's operation information and is sent with
  /// ``CRCIntegrity``.
  case getSet(variant: UInt8 = 0x00)

  /// Reads or writes records in the device's ALL-Link database (cmd1 `0x2F`, cmd2 `0x00`).
  case readWriteAllLinkDatabase

  /// Makes a device act as if one of its ALL-Link groups were triggered (cmd1 `0x30`, cmd2 `0x00`).
  ///
  /// D1 is the group. When D2 is `0x01`, D3 is the on-level to use locally instead of the
  /// device's own; D4 and D5 are the cmd1 and cmd2 to send to the group; and D6 selects the
  /// local ramp rate, `0x00` for the device's own or `0x01` for instant. The two devices must
  /// be linked.
  case triggerAllLinkGroup

  /// Sets the direct command a responder carries out in place of an ALL-Link alias command
  /// (cmd1 `0x03`, cmd2 `0x04`).
  ///
  /// Build its user data with ``AllLinkCommandAlias``. When D4 is `0x01`, the substitute is an
  /// extended command, and a ``ExtendedDirectCommand/setAllLinkCommandAliasExtendedData``
  /// message follows.
  case setAllLinkCommandAlias

  /// Carries the user data of an extended substitute set with
  /// ``ExtendedDirectCommand/setAllLinkCommandAlias`` (cmd1 `0x03`, cmd2 `0x05`).
  ///
  /// D1 through D14 are the substitute's user data. The default ``ChecksumIntegrity``
  /// overwrites D14 with this message's checksum; to send the substitute's D14 as given, use
  /// ``UnprotectedIntegrity``.
  case setAllLinkCommandAliasExtendedData

}

// MARK: - CommandConvertible

extension ExtendedDirectCommand: CommandConvertible {

  /// The command's cmd1 and cmd2 bytes.
  public var command: Command {

    switch self {
    case let .getSet(variant):
      Command(command1: 0x2E, command2: variant)
    case .readWriteAllLinkDatabase:
      Command(command1: 0x2F)
    case .triggerAllLinkGroup:
      Command(command1: 0x30)
    case .setAllLinkCommandAlias:
      Command(command1: 0x03, command2: 0x04)
    case .setAllLinkCommandAliasExtendedData:
      Command(command1: 0x03, command2: 0x05)
    }

  }

}

// MARK: - Engine support

extension ExtendedDirectCommand {

  /// The earliest engine on which every device accepts the command, or `nil` when that
  /// depends on the product.
  ///
  /// The i2 engine adds the get/set, ALL-Link database and trigger commands, which some i1
  /// devices also accept. What a device reads or writes with them is specific to the product,
  /// and only some products accept a ``ExtendedDirectCommand/getSet(variant:)`` variant other
  /// than `0x00`. The Developer's Guide defines the ALL-Link command alias commands for every
  /// device category, but whether a device accepts them depends on the product.
  public var minimumEngine: InsteonEngine? {

    switch self {
    case let .getSet(variant):
      variant == 0x00 ? .i2 : nil
    case .readWriteAllLinkDatabase, .triggerAllLinkGroup:
      .i2
    case .setAllLinkCommandAlias, .setAllLinkCommandAliasExtendedData:
      nil
    }

  }

}
