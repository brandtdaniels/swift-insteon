/// A substitute direct command for an ALL-Link alias command, encoded as the user data of an
/// ``ExtendedDirectCommand/setAllLinkCommandAlias`` message.
///
/// When a responder hears an ``AllLinkCommand`` it has a substitute for, it carries out the
/// substitute as if it had been sent to it directly. A substitute of `0x0000` makes it ignore
/// the alias command.
///
/// ```swift
/// // Make ALL-Link Alias 2 High turn the device on at full brightness, instantly.
/// let alias = AllLinkCommandAlias(.alias2High, substitute: StandardDirectCommand.fastOn(level: 0xFF))
/// let message = alias.message(to: lamp)
/// ```
///
/// This sets standard-length substitutes. For an extended substitute, set D4 to `0x01` and
/// follow with a ``ExtendedDirectCommand/setAllLinkCommandAliasExtendedData`` message.
public struct AllLinkCommandAlias: Hashable, Sendable {

  /// The alias command to replace.
  public var command: AllLinkCommand

  /// The standard direct command to carry out in its place.
  public var substitute: Command

  /// Creates an alias.
  ///
  /// - Parameters:
  ///   - command: The alias command to replace.
  ///   - substitute: The standard direct command to carry out in its place.
  public init(_ command: AllLinkCommand, substitute: some StandardCommandConvertible) {

    self.command = command
    self.substitute = substitute.command

  }

  /// An alias that makes a responder ignore an alias command.
  ///
  /// - Parameter command: The alias command to ignore.
  /// - Returns: An alias whose substitute is `0x0000`.
  public static func ignoring(_ command: AllLinkCommand) -> AllLinkCommandAlias {

    AllLinkCommandAlias(command, substitute: Command(command1: 0x00))

  }

  /// The alias's user data: D1 is the alias command, D2 and D3 are the substitute's cmd1 and
  /// cmd2, and D4 is `0x00` for a standard-length substitute.
  public var userData: UserData {

    var userData = UserData()
    userData[1] = command.rawValue
    userData[2] = substitute.command1
    userData[3] = substitute.command2

    return userData

  }

  /// The extended message that sets the alias, sealed with a checksum, which i2cs devices
  /// require.
  ///
  /// - Parameter device: The responder to set it on.
  /// - Returns: The message.
  public func message(to device: InsteonAddress) -> ExtendedMessage {

    ExtendedMessage(to: device, command: ExtendedDirectCommand.setAllLinkCommandAlias, userData: userData)

  }

}
