/// A type that can be expressed as INSTEON command bytes.
///
/// Messages accept any conforming type, so device-specific command sets can be added
/// without changing this package.
public protocol CommandConvertible: Sendable {

  /// The command bytes this value represents.
  var command: Command { get }

  /// The earliest ``InsteonEngine`` on which every device accepts the command, or `nil` when
  /// that depends on the product. Defaults to `nil`.
  var minimumEngine: InsteonEngine? { get }

}

extension CommandConvertible {

  /// Returns `nil`: without more knowledge of a command, whether a device accepts it depends on
  /// the product.
  public var minimumEngine: InsteonEngine? {

    nil

  }

}

/// A command that can be sent in a standard-length message.
///
/// The protocol defines standard-length and extended-length direct commands in separate tables,
/// and the same cmd1 can mean different things in each: `0x2E` is Light ON at Ramp Rate in a
/// standard message but Extended Set/Get in an extended one. Commands from the extended table,
/// such as ``ExtendedDirectCommand``, don't conform, so they can't end up in a
/// ``StandardMessage`` by mistake. Any command can still be sent in an ``ExtendedMessage``.
public protocol StandardCommandConvertible: CommandConvertible {}
