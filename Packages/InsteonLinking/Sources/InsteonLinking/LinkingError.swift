import InsteonProtocol

/// Errors reported by ``Linker`` and ``Unlinker``.
public enum LinkingError: Error, Hashable, Sendable {

  /// A device's ALL-Link database has no room for another record.
  case databaseFull(InsteonAddress)

  /// A record written to a device's ALL-Link database read back differently.
  case recordNotWritten(InsteonAddress, address: UInt16)

  /// A device with an i1 engine can't be put into linking or unlinking mode remotely; link it
  /// with its SET button instead.
  case remoteLinkingUnsupported(InsteonAddress)

  /// The modem didn't report a link in time.
  case linkingTimedOut

  /// The modem reported a link other than the one asked for: with another device, which a
  /// person linked with its SET button while the modem was waiting, in another group, or of
  /// another kind, such as a new link where an unlink was asked for.
  case unexpectedLink(AllLinkingCompleted)

  /// Removing a record from the modem's ALL-Link database also removed these records, which
  /// link the same device in the same group in the other role, and they couldn't be added
  /// back. The modem deletes the first record that matches a group and address whatever its
  /// role, so a record of the other role is deleted and then added back.
  case modemRecordsLost([AllLinkRecord])

}
