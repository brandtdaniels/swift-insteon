/// A modem's echo of a command its host sent.
///
/// Modems repeat each command back, then add `0x06` (ACK) if they accepted it or `0x15` (NAK)
/// if they couldn't, for example because they were busy. A NAK usually means the command should
/// be sent again after a short delay.
public struct CommandEcho: Hashable, Sendable {

  /// The number of the command being echoed.
  public var number: SerialCommandNumber

  /// The command's parameters as echoed, without the ACK or NAK byte.
  public var parameters: [UInt8]

  /// Whether the modem accepted the command (ACK) rather than rejecting it (NAK).
  public var isAccepted: Bool

  /// Creates an echo.
  ///
  /// - Parameters:
  ///   - number: The number of the command being echoed.
  ///   - parameters: The command's parameters as echoed.
  ///   - isAccepted: Whether the modem accepted the command.
  public init(number: SerialCommandNumber, parameters: [UInt8], isAccepted: Bool) {

    self.number = number
    self.parameters = parameters
    self.isAccepted = isAccepted

  }

}
