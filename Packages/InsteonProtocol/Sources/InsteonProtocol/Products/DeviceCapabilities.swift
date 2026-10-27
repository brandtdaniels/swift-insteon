/// What a device can do, as a ``ProductDatabase`` records it for the device's firmware version.
///
/// Devices of the same kind can support different commands depending on their firmware, so
/// capabilities belong to a particular firmware version. A ``ProductDatabase`` supplies them;
/// this package defines only the questions they answer.
///
/// A command is identified by its bytes and its ``MessageLength``, since standard and extended
/// commands with the same cmd1 can be different commands.
public protocol DeviceCapabilities: Sendable {

  /// Returns whether the device, as a responder, acts on a command it receives.
  ///
  /// - Parameters:
  ///   - command: A command sent to the device.
  ///   - length: The length of the message that carries the command.
  /// - Returns: `true` if the device acts on the command.
  func responds(to command: Command, length: MessageLength) -> Bool

  /// Returns whether the device, as a controller, sends a command to the devices linked to it.
  ///
  /// - Parameters:
  ///   - command: A command the device might send.
  ///   - length: The length of the message that carries the command.
  /// - Returns: `true` if the device sends the command.
  func sends(_ command: Command, length: MessageLength) -> Bool

}

extension DeviceCapabilities {

  /// Returns whether the device, as a responder, acts on a standard command it receives.
  ///
  /// - Parameter command: A standard command sent to the device, such as a
  ///   ``StandardDirectCommand``.
  /// - Returns: `true` if the device acts on the command.
  public func responds(to command: some StandardCommandConvertible) -> Bool {

    responds(to: command.command, length: .standard)

  }

  /// Returns whether the device, as a responder, acts on an extended command it receives.
  ///
  /// - Parameter command: An extended command sent to the device.
  /// - Returns: `true` if the device acts on the command.
  public func responds(to command: ExtendedDirectCommand) -> Bool {

    responds(to: command.command, length: .extended)

  }

  /// Returns whether the device, as a controller, sends a standard command to the devices
  /// linked to it.
  ///
  /// - Parameter command: A standard command the device might send, such as a
  ///   ``StandardDirectCommand``.
  /// - Returns: `true` if the device sends the command.
  public func sends(_ command: some StandardCommandConvertible) -> Bool {

    sends(command.command, length: .standard)

  }

  /// Returns whether the device, as a controller, sends an extended command to the devices
  /// linked to it.
  ///
  /// - Parameter command: An extended command the device might send.
  /// - Returns: `true` if the device sends the command.
  public func sends(_ command: ExtendedDirectCommand) -> Bool {

    sends(command.command, length: .extended)

  }

}
