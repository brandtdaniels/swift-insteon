/// A connection to an Insteon modem that can send it serial commands.
///
/// Depend on this protocol rather than a specific connection, such as an Insteon Hub or a
/// PowerLinc Modem on a serial port, so the connection can be swapped or replaced in tests.
public protocol SerialCommandSender: Sendable {

  /// Sends a command to the modem.
  ///
  /// Anything the command asks for, such as an ALL-Link record or the modem's configuration,
  /// arrives afterwards in the modem's replies, which the connection exposes separately.
  ///
  /// - Parameter command: The command to send.
  /// - Throws: An error if the command could not be delivered, or if the connection waits for
  ///   the modem's acknowledgement and the modem rejects the command.
  func send(_ command: SerialCommand) async throws

}
