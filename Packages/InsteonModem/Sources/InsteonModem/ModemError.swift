import InsteonProtocol

/// Errors reported by ``Modem``.
public enum ModemError: Error, Hashable, Sendable {

  /// The modem kept rejecting a command with a NAK, usually because it was busy.
  case rejected(SerialCommandNumber)

  /// The modem didn't echo a command within the configured timeout.
  case timedOut(SerialCommandNumber)

  /// The connection closed while a command was waiting for its echo.
  case connectionClosed

}
