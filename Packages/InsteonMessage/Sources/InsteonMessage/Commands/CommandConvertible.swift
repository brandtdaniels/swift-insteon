/// A type that can be expressed as INSTEON command bytes.
///
/// Messages accept any conforming type, so device-specific command sets can be added
/// without changing this package.
public protocol CommandConvertible: Sendable {

  /// The command bytes this value represents.
  var command: Command { get }

}
