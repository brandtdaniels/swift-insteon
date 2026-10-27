/// A connection to an INSTEON modem that can send it serial commands.
///
/// Depend on this protocol rather than a specific connection, such as an INSTEON Hub or a
/// PowerLinc Modem on a serial port, so the connection can be swapped or replaced in tests.
public protocol SerialCommandSender: Sendable {

  /// Sends a command to the modem.
  ///
  /// - Parameter command: The command to send.
  /// - Throws: An error if the command could not be delivered to the modem.
  func send(_ command: SerialCommand) async throws

}
