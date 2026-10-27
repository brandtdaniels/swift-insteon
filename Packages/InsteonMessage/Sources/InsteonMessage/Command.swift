/// The two command bytes of an INSTEON message.
///
/// `command1` selects the operation and `command2` carries its argument, such as a light
/// level or an ALL-Link group. Use the typed catalogues, ``StandardDirectCommand`` and
/// ``ExtendedDirectCommand``, where they cover what you need, and this type directly for
/// device-specific commands they don't.
public struct Command: Hashable, Sendable {

  /// The first command byte, which selects the operation.
  public var command1: UInt8

  /// The second command byte, which carries the operation's argument.
  public var command2: UInt8

  /// Creates a command from its two bytes.
  ///
  /// - Parameters:
  ///   - command1: The first command byte.
  ///   - command2: The second command byte. Defaults to `0x00`.
  public init(command1: UInt8, command2: UInt8 = 0x00) {

    self.command1 = command1
    self.command2 = command2

  }

}

// MARK: - ByteEncodable

extension Command: ByteEncodable {

  /// The command's two bytes: `command1` then `command2`.
  public var bytes: [UInt8] {

    [command1, command2]

  }

}

// MARK: - CommandConvertible

extension Command: CommandConvertible {

  /// The command itself.
  public var command: Command {

    self

  }

}
