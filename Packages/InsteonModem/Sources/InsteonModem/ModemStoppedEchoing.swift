import InsteonProtocol

/// The modem didn't echo a message to a device after it had sent something.
///
/// The modem was connected and powered, since it had sent something, so it's most likely still
/// busy with a device that doesn't answer, as when it retries a message on a marginal powerline
/// signal. ``Modem``'s requests to a device throw this in place of
/// ``ModemError/timedOut(_:)`` for a message the modem doesn't echo in time.
///
/// A request fails with ``ModemError/timedOut(_:)`` instead when the modem hasn't sent anything
/// since the ``Modem`` started reading, or since the last command it didn't answer, since the
/// modem may be disconnected, off or stuck.
///
/// The modem may still send the message once it's free, so a command that changes a device's
/// state can still take effect.
public struct ModemStoppedEchoing: Error, Hashable, Sendable {

  /// The device the message was addressed to.
  public let device: InsteonAddress

  /// The command that carried the message, such as `SerialCommandNumber.sendMessage`.
  public let command: SerialCommandNumber

  /// Creates the error.
  ///
  /// - Parameters:
  ///   - device: The device the message was addressed to.
  ///   - command: The command that carried the message.
  public init(device: InsteonAddress, command: SerialCommandNumber) {

    self.device = device
    self.command = command

  }

}
