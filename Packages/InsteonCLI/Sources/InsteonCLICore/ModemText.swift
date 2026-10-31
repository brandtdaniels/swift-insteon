import InsteonProtocol

/// What the command says when the modem doesn't echo a command.
public enum ModemText {

  /// For a modem that didn't echo a command, when nothing suggests it's busy, as when it's
  /// disconnected or off.
  ///
  /// - Parameter command: The command's name, such as "Get IM Info".
  /// - Returns: A message that says to check the modem's connection and power.
  public static func unanswered(command: String) -> String {

    "The modem didn't answer \(command). Check that it's connected and powered."

  }

  /// For a modem that answered earlier commands and then didn't echo a message to a device, as
  /// when it's still sending an earlier message to a device that doesn't answer.
  ///
  /// - Parameter device: The device the message was addressed to.
  /// - Returns: A message that names the device and says to try again.
  public static func didntConfirmSending(to device: InsteonAddress) -> String {

    "The modem didn't confirm sending to \(device); it may still be busy with a device that isn't answering. Check that \(device) is powered and in range, then try again."

  }

}
