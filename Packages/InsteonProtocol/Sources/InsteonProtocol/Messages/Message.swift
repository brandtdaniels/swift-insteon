/// An INSTEON message ready to hand to a modem for transmission.
///
/// The bytes are the destination address, flags and command, followed by user data for
/// extended messages. This is the form INSTEON modems accept for sending; the modem adds
/// its own address as the sender.
public protocol Message: ByteEncodable, Hashable, Sendable {

  /// The device the message is addressed to.
  ///
  /// For ALL-Link broadcasts, the low byte is the ALL-Link group instead.
  var destination: InsteonAddress { get }

  /// The message's flags byte.
  var flags: MessageFlags { get }

  /// The message's command bytes.
  var command: Command { get }

}
