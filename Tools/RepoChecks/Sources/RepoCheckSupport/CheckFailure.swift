/// A check that can't go on, with the message to give. The command writes it to standard
/// error and exits with status 1, as `sys.exit(message)` did.
public struct CheckFailure: Error, Equatable, CustomStringConvertible {
  public let message: String

  public init(_ message: String) {
    self.message = message
  }

  public var description: String {
    message
  }
}
