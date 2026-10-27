/// A message an INSTEON modem sends to its host.
///
/// Modems send two kinds of replies: echoes of the commands the host sent, ending in an ACK or
/// NAK, and reports of things that happened, such as a message received from a device. Turn
/// the bytes a modem sends into replies with ``ModemReplyParser``.
public enum ModemReply: Hashable, Sendable {

  /// A device sent a message (`0x50` for standard length, `0x51` for extended).
  case messageReceived(ReceivedMessage)

  /// An X10 transmission was heard on the power line (`0x52`).
  case x10Received(X10Code)

  /// ALL-Linking finished with another device (`0x53`).
  case allLinkingCompleted(AllLinkingCompleted)

  /// One of the modem's buttons was used (`0x54`).
  case buttonEvent(ModemButtonEvent)

  /// The modem was reset to factory defaults with its SET button (`0x55`).
  case userReset

  /// A device didn't acknowledge an ALL-Link cleanup message (`0x56`).
  ///
  /// - Parameters:
  ///   - group: The ALL-Link group the cleanup was for.
  ///   - address: The device that didn't respond.
  case allLinkCleanupFailed(group: UInt8, address: InsteonAddress)

  /// A record from the modem's ALL-Link database (`0x57`), in reply to
  /// ``SerialCommand/getFirstAllLinkRecord`` and similar commands.
  case allLinkRecord(AllLinkRecord)

  /// The modem finished sending ALL-Link cleanup messages (`0x58`).
  ///
  /// - Parameter isComplete: `true` if every cleanup was sent, or `false` if the sequence was
  ///   interrupted.
  case allLinkCleanupStatus(isComplete: Bool)

  /// A record read from the modem's database (`0x59`), in reply to
  /// ``SerialCommand/readDatabase(address:)``.
  ///
  /// - Parameters:
  ///   - address: The record's address in the database.
  ///   - record: The record.
  case databaseRecord(address: UInt16, record: AllLinkRecord)

  /// The modem's identity (`0x60`), in reply to ``SerialCommand/getModemInfo``.
  case modemInfo(ModemInfo)

  /// The modem's settings (`0x73`), in reply to ``SerialCommand/getModemConfiguration``.
  case modemConfiguration(ModemConfigurationReport)

  /// The modem's echo of a command the host sent, with its ACK or NAK.
  case echo(CommandEcho)

  /// A lone NAK (`0x15`): the modem rejected the last command without echoing it, usually
  /// because it was busy. Send the command again after a short delay.
  case negativeAcknowledgement

}
