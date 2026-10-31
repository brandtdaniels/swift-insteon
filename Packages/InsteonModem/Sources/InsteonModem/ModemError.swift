import InsteonProtocol

/// Errors reported by ``Modem``.
public enum ModemError: Error, Hashable, Sendable {

  /// The modem kept rejecting a command with a NAK, because it stayed busy or because its
  /// firmware doesn't implement the command.
  case rejected(SerialCommandNumber)

  /// The modem didn't echo a command within the configured timeout.
  ///
  /// A request to a device throws ``ModemStoppedEchoing`` in its place once the modem has sent
  /// anything, since a modem that has answered is more likely busy than disconnected.
  case timedOut(SerialCommandNumber)

  /// The modem is closed: its connection ended, or ``Modem/run()`` returned.
  case connectionClosed

  /// A device rejected a message with a NAK, for the reason it gave.
  case deviceRejected(InsteonAddress, NAKReason)

  /// A device didn't acknowledge a message within the request's timeout.
  case deviceTimedOut(InsteonAddress)

}
