/// A heartbeat broadcast, which a battery-powered device sends periodically to show it's
/// still working.
///
/// The broadcast carries a battery level in cmd2, whose scale depends on the device, and the
/// device's identity in its To address.
///
/// ```swift
/// var parser = ModemReplyParser()
///
/// for reply in parser.parse(bytesFromModem) {
///   if case let .messageReceived(message) = reply, let heartbeat = Heartbeat(message) {
///     print(heartbeat.sender, heartbeat.batteryLevel)
///   }
/// }
/// ```
public struct Heartbeat: Hashable, Sendable {

  /// The device that sent the heartbeat.
  public var sender: InsteonAddress

  /// The device's battery level, on a scale that depends on the device.
  public var batteryLevel: UInt8

  /// The device's category.
  public var category: DeviceCategory

  /// The device's subcategory.
  public var subcategory: DeviceSubcategory

  /// The device's firmware version, or `nil` when the device reports `0xFF` in its place.
  public var firmwareVersion: FirmwareVersion?

  /// Creates a heartbeat.
  ///
  /// - Parameters:
  ///   - sender: The device that sent the heartbeat.
  ///   - batteryLevel: The device's battery level.
  ///   - category: The device's category.
  ///   - subcategory: The device's subcategory.
  ///   - firmwareVersion: The device's firmware version, if it reports one.
  public init(
    sender: InsteonAddress,
    batteryLevel: UInt8,
    category: DeviceCategory,
    subcategory: DeviceSubcategory,
    firmwareVersion: FirmwareVersion?
  ) {

    self.sender = sender
    self.batteryLevel = batteryLevel
    self.category = category
    self.subcategory = subcategory
    self.firmwareVersion = firmwareVersion

  }

  /// Reads a heartbeat from a received message.
  ///
  /// - Parameter message: A message the modem received.
  /// - Returns: `nil` unless the message is a standard-length broadcast with cmd1 `0x04`.
  public init?(_ message: ReceivedMessage) {

    guard message.isStandardBroadcast(command1: 0x04) else {

      return nil

    }

    let identity = message.reportedIdentity

    self.init(
      sender: message.sender,
      batteryLevel: message.command.command2,
      category: identity.category,
      subcategory: identity.subcategory,
      firmwareVersion: identity.firmwareVersion
    )

  }

}
