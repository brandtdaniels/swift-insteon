/// A message a device running IBIOS sends to its host.
///
/// Turn the bytes it sends into replies with ``IBIOSReplyParser``.
public enum IBIOSReply: Hashable, Sendable {

  /// The echo of a command the host sent, with its ACK or NAK.
  case echo(IBIOSEcho)

  /// Bytes read from memory, in reply to ``IBIOSCommand/upload(address:length:)`` (`0x42`).
  ///
  /// - Parameters:
  ///   - address: The address of the first byte.
  ///   - data: The bytes read.
  ///   - isIntact: Whether the checksum IBIOS sent matches the bytes.
  case memory(address: UInt16, data: [UInt8], isIntact: Bool)

  /// The checksum of a region of memory, in reply to
  /// ``IBIOSCommand/getChecksum(address:length:)`` (`0x44`).
  ///
  /// - Parameters:
  ///   - address: The address of the region's first byte.
  ///   - length: The region's length.
  ///   - checksum: The region's checksum, as ``IBIOSCommand/checksum(of:)`` computes it.
  case checksum(address: UInt16, length: UInt16, checksum: UInt16)

  /// The device's identity, in reply to ``IBIOSCommand/getVersion`` (`0x48`).
  case version(ModemInfo)

  /// An event fired (`0x45`).
  case eventReport(IBIOSEvent)

  /// An Insteon message arrived, as the device's SALad program reports it (`0x4F`).
  ///
  /// - Parameters:
  ///   - event: The event the message fired, such as ``IBIOSEvent/messageForMe``.
  ///   - message: The message, or `nil` for ``IBIOSEvent/sendNotAcknowledged``, which reports
  ///     that a sent message wasn't acknowledged rather than a message that arrived.
  case messageReceived(IBIOSEvent, message: ReceivedMessage?)

  /// An X10 byte arrived, as the device's SALad program reports it (`0x4A`).
  case x10Received(X10Code)

  /// The address of the next SALad instruction, while remote debugging (`0x49`).
  case debugReport(address: UInt16)

  /// Data the device's SALad program sent (`0x41`).
  case data([UInt8])

  /// Text the device's SALad program sent (`0x43`).
  case text(String)

  /// A lone NAK (`0x15`): the device rejected the last command without echoing it, usually
  /// because it was busy. Send the command again after a short delay.
  case negativeAcknowledgement

}

/// The echo of an ``IBIOSCommand``.
///
/// For ``IBIOSCommand/download(address:data:)`` the echo repeats only the address and length,
/// not the checksum or data. An ACK means IBIOS received the command, not that it carried it
/// out; confirm a download with ``IBIOSCommand/getChecksum(address:length:)``.
public struct IBIOSEcho: Hashable, Sendable {

  /// The number of the command being echoed.
  public var number: IBIOSCommandNumber

  /// The command's parameters as echoed, without the ACK or NAK byte.
  public var parameters: [UInt8]

  /// Whether the device accepted the command (ACK) rather than rejecting it (NAK).
  public var isAccepted: Bool

  /// Creates an echo.
  ///
  /// - Parameters:
  ///   - number: The number of the command being echoed.
  ///   - parameters: The command's parameters as echoed.
  ///   - isAccepted: Whether the device accepted the command.
  public init(number: IBIOSCommandNumber, parameters: [UInt8], isAccepted: Bool) {

    self.number = number
    self.parameters = parameters
    self.isAccepted = isAccepted

  }

}
