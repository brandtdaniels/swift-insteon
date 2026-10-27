import InsteonProtocol

/// Errors reported by ``PowerLincController``.
public enum PowerLincControllerError: Error, Hashable, Sendable {

  /// The controller can't carry this command. It sends standard INSTEON messages and X10, and
  /// answers ``SerialCommand/getModemInfo``.
  case unsupported(SerialCommand)

  /// The controller kept rejecting an IBIOS command with a NAK, usually because it was busy.
  case rejected(IBIOSCommand)

  /// The controller didn't answer an IBIOS command within the configured timeout.
  case timedOut(IBIOSCommand)

  /// The connection closed while a command was waiting for its answer.
  case connectionClosed

}
