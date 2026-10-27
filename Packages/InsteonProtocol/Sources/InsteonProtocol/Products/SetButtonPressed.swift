/// A SET Button Pressed broadcast, in which a device identifies its kind.
///
/// A device sends this broadcast when someone holds its SET button to link it, and in reply to
/// ``StandardDirectCommand/idRequest``. The broadcast's To address carries the device's
/// category, subcategory and, on some devices, firmware version.
///
/// ```swift
/// for await reply in await modem.replies() {
///   if case let .messageReceived(message) = reply, let identity = SetButtonPressed(message) {
///     print(identity.sender, identity.category, identity.subcategory)
///   }
/// }
/// ```
public struct SetButtonPressed: Hashable, Sendable {

  /// The role the device takes when linked from its SET button.
  public enum Role: UInt8, Hashable, Sendable {

    /// The device links as a responder (cmd1 `0x01`).
    case responder = 0x01

    /// The device links as a controller (cmd1 `0x02`).
    case controller = 0x02

  }

  /// The device that sent the broadcast.
  public var sender: InsteonAddress

  /// The role the device takes when linked.
  public var role: Role

  /// The device's category.
  public var category: DeviceCategory

  /// The device's subcategory.
  public var subcategory: UInt8

  /// The device's firmware version, or `nil` when the device reports `0xFF` in its place.
  public var firmwareVersion: UInt8?

  /// Creates a SET Button Pressed broadcast.
  ///
  /// - Parameters:
  ///   - sender: The device that sent the broadcast.
  ///   - role: The role the device takes when linked.
  ///   - category: The device's category.
  ///   - subcategory: The device's subcategory.
  ///   - firmwareVersion: The device's firmware version, if it reports one.
  public init(
    sender: InsteonAddress,
    role: Role,
    category: DeviceCategory,
    subcategory: UInt8,
    firmwareVersion: UInt8?
  ) {

    self.sender = sender
    self.role = role
    self.category = category
    self.subcategory = subcategory
    self.firmwareVersion = firmwareVersion

  }

  /// Reads a SET Button Pressed broadcast from a received message.
  ///
  /// - Parameter message: A message the modem received.
  /// - Returns: `nil` unless the message is a standard-length broadcast with cmd1 `0x01` or
  ///   `0x02`.
  public init?(_ message: ReceivedMessage) {

    guard
      message.flags.messageType == .broadcast,
      !message.flags.isExtended,
      let role = Role(rawValue: message.command.command1)
    else {

      return nil

    }

    let firmware = message.destination.low

    self.init(
      sender: message.sender,
      role: role,
      category: DeviceCategory(rawValue: message.destination.high),
      subcategory: message.destination.middle,
      firmwareVersion: firmware == 0xFF ? nil : firmware
    )

  }

}
