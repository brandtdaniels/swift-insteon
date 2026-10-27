/// An extended-length INSTEON message: destination, flags, two command bytes and 14 bytes
/// of user data.
///
/// The message seals its user data with an integrity scheme when created, so the integrity
/// bytes always match the command and data:
///
/// ```swift
/// var userData = UserData()
/// userData[1] = 0x01
///
/// let message = ExtendedMessage(
///   to: InsteonAddress(0xAA, 0xBB, 0xCC),
///   command: ExtendedDirectCommand.getSet,
///   userData: userData
/// )
/// message.userData[14]  // 0xD1, the checksum
/// ```
public struct ExtendedMessage: Message {

  /// The device the message is addressed to.
  public let destination: InsteonAddress

  /// The kind of message.
  public let messageType: MessageFlags.MessageType

  /// The number of retransmissions to allow.
  public let maxHops: MessageFlags.HopCount

  /// The message's command bytes.
  public let command: Command

  /// The user data, with its integrity bytes set.
  public let userData: UserData

  /// Creates an extended-length message.
  ///
  /// - Parameters:
  ///   - destination: The device the message is addressed to.
  ///   - command: The command to send.
  ///   - userData: The user data to send. Its integrity bytes are overwritten by `integrity`.
  ///   - integrity: How to protect the user data. Defaults to ``ChecksumIntegrity``,
  ///     which i2cs devices require and i1 and i2 devices ignore.
  ///   - messageType: The kind of message. Defaults to ``MessageFlags/MessageType/direct``.
  ///   - maxHops: The number of retransmissions to allow. Defaults to three.
  public init(
    to destination: InsteonAddress,
    command: some CommandConvertible,
    userData: UserData = UserData(),
    integrity: some UserDataIntegrity = ChecksumIntegrity(),
    messageType: MessageFlags.MessageType = .direct,
    maxHops: MessageFlags.HopCount = .three
  ) {

    self.destination = destination
    self.command = command.command
    self.userData = integrity.seal(userData, for: command.command)
    self.messageType = messageType
    self.maxHops = maxHops

  }

  /// The message's flags: extended length, with all hops remaining.
  public var flags: MessageFlags {

    MessageFlags(messageType: messageType, isExtended: true, maxHops: maxHops)

  }

  /// The message's 20 bytes: destination, flags, cmd1, cmd2 and D1 through D14.
  public var bytes: [UInt8] {

    destination.bytes + [flags.rawValue] + command.bytes + userData.bytes

  }

}
