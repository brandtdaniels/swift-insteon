/// An INSTEON message a modem received from a device.
public struct ReceivedMessage: Hashable, Sendable {

  /// The device that sent the message.
  public var sender: InsteonAddress

  /// The device the message was addressed to. For broadcasts this field carries other data,
  /// such as the sender's device category in a ``SetButtonPressed`` broadcast.
  public var destination: InsteonAddress

  /// The message's flags.
  public var flags: MessageFlags

  /// The message's command bytes.
  public var command: Command

  /// The user data of an extended message, or `nil` for a standard message.
  public var userData: UserData?

  /// Creates a received message.
  ///
  /// - Parameters:
  ///   - sender: The device that sent the message.
  ///   - destination: The device the message was addressed to.
  ///   - flags: The message's flags.
  ///   - command: The message's command bytes.
  ///   - userData: The user data of an extended message. Defaults to `nil`.
  public init(
    sender: InsteonAddress,
    destination: InsteonAddress,
    flags: MessageFlags,
    command: Command,
    userData: UserData? = nil
  ) {

    self.sender = sender
    self.destination = destination
    self.flags = flags
    self.command = command
    self.userData = userData

  }

}

extension ReceivedMessage {

  /// Why the device rejected a message, when this message is a direct or ALL-Link cleanup NAK;
  /// otherwise `nil`.
  public var nakReason: NAKReason? {

    switch flags.messageType {
    case .directNegativeAcknowledgement, .allLinkCleanupNegativeAcknowledgement:
      NAKReason(rawValue: command.command2)
    default:
      nil
    }

  }

}
