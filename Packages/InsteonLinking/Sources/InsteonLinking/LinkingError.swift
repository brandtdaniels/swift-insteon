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

}
