import InsteonProtocol

/// Errors reported by ``Linker`` and ``Unlinker``.
public enum LinkingError: Error, Hashable, Sendable {

  /// A device's ALL-Link database has no room for another record.
  case databaseFull(InsteonAddress)

  /// A record written to a device's ALL-Link database read back differently.
  case recordNotWritten(InsteonAddress, address: UInt16)

  /// The modem closed before it reported its own address.
  case modemAddressUnavailable

  /// A device with an i1 engine can't be put into linking or unlinking mode remotely; link it
  /// with its SET button instead.
  case remoteLinkingUnsupported(InsteonAddress)

  /// The modem didn't report a link in time.
  case linkingTimedOut

  /// The modem reported a link other than the one asked for: with another device, which a
  /// person linked with its SET button while the modem was waiting, in another group, or of
  /// another kind, such as a new link where an unlink was asked for.
  case unexpectedLink(AllLinkingCompleted)

}
