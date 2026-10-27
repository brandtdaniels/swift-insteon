import InsteonProtocol

/// Errors reported by ``PowerLincController``.
public enum PowerLincControllerError: Error, Hashable, Sendable {

  /// The controller can't carry this command. It sends standard INSTEON messages and X10, and
  /// answers `SerialCommand.getModemInfo`.
  case unsupported(SerialCommand)

  /// The controller kept rejecting an IBIOS command, with a NAK because it was busy or with
  /// memory that arrived damaged.
  case rejected(IBIOSCommand)

  /// Data downloaded to an address didn't read back with the checksum it was written with,
  /// so the controller was never asked to send it.
  case unconfirmedDownload(address: UInt16)

  /// The controller didn't answer an IBIOS command within the configured timeout.
  case timedOut(IBIOSCommand)

  /// The connection closed while a command was waiting for its answer.
  case connectionClosed

}
