/// What a device can do, as a ``ProductDatabase`` records it for the device's firmware version.
///
/// Devices of the same kind can support different commands depending on their firmware, so
/// capabilities belong to a particular firmware version. A ``ProductDatabase`` supplies them;
/// this package defines only the questions they answer.
public protocol DeviceCapabilities: Sendable {

  /// Returns whether the device, as a responder, acts on a command it receives.
  ///
  /// - Parameter command: A command sent to the device.
  /// - Returns: `true` if the device acts on the command.
  func responds(to command: Command) -> Bool

  /// Returns whether the device, as a controller, sends a command to the devices linked to it.
  ///
  /// - Parameter command: A command the device might send.
  /// - Returns: `true` if the device sends the command.
  func sends(_ command: Command) -> Bool

}

extension DeviceCapabilities {

  /// Returns whether the device, as a responder, acts on a command it receives.
  ///
  /// - Parameter command: A command sent to the device, such as a ``StandardDirectCommand``.
  /// - Returns: `true` if the device acts on the command.
  public func responds(to command: some CommandConvertible) -> Bool {

    responds(to: command.command)

  }

  /// Returns whether the device, as a controller, sends a command to the devices linked to it.
  ///
  /// - Parameter command: A command the device might send, such as a ``StandardDirectCommand``.
  /// - Returns: `true` if the device sends the command.
  public func sends(_ command: some CommandConvertible) -> Bool {

    sends(command.command)

  }

}
