/// A standard-length INSTEON message: destination, flags and two command bytes.
///
/// ```swift
/// let message = StandardMessage(
///   to: InsteonAddress(0xAA, 0xBB, 0xCC),
///   command: StandardDirectCommand.on(level: 0x80)
/// )
/// message.hexString  // "AABBCC0F1180"
/// ```
public struct StandardMessage: Message {

  /// The device the message is addressed to.
  public let destination: InsteonAddress

  /// The kind of message.
  public let messageType: MessageFlags.MessageType

  /// The number of retransmissions to allow.
  public let maxHops: MessageFlags.HopCount

  /// The message's command bytes.
  public let command: Command

  /// Creates a standard-length message.
  ///
  /// - Parameters:
  ///   - destination: The device the message is addressed to.
  ///   - command: The command to send.
  ///   - messageType: The kind of message. Defaults to ``MessageFlags/MessageType/direct``.
  ///   - maxHops: The number of retransmissions to allow. Defaults to three.
  public init(
    to destination: InsteonAddress,
    command: some CommandConvertible,
    messageType: MessageFlags.MessageType = .direct,
    maxHops: MessageFlags.HopCount = .three
  ) {

    self.destination = destination
    self.command = command.command
    self.messageType = messageType
    self.maxHops = maxHops

  }

  /// The message's flags: standard length, with all hops remaining.
  public var flags: MessageFlags {

    MessageFlags(messageType: messageType, isExtended: false, maxHops: maxHops)

  }

  /// The message's six bytes: destination, flags, cmd1 and cmd2.
  public var bytes: [UInt8] {

    destination.bytes + [flags.rawValue] + command.bytes

  }

}
