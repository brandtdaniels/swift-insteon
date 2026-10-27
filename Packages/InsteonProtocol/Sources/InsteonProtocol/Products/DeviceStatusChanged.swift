/// A device status changed broadcast, which a device sends when its status changes.
///
/// Devices that support it send it only once it's enabled through their operating flags. The
/// broadcast carries the device's identity in its To address; ask the device for its new status
/// with ``StandardDirectCommand/statusRequest(variant:)``.
public struct DeviceStatusChanged: Hashable, Sendable {

  /// The device whose status changed.
  public var sender: InsteonAddress

  /// The device's category.
  public var category: DeviceCategory

  /// The device's subcategory.
  public var subcategory: DeviceSubcategory

  /// The device's firmware version, or `nil` when the device reports `0xFF` in its place.
  public var firmwareVersion: FirmwareVersion?

  /// Creates a device status changed broadcast.
  ///
  /// - Parameters:
  ///   - sender: The device whose status changed.
  ///   - category: The device's category.
  ///   - subcategory: The device's subcategory.
  ///   - firmwareVersion: The device's firmware version, if it reports one.
  public init(
    sender: InsteonAddress,
    category: DeviceCategory,
    subcategory: DeviceSubcategory,
    firmwareVersion: FirmwareVersion?
  ) {

    self.sender = sender
    self.category = category
    self.subcategory = subcategory
    self.firmwareVersion = firmwareVersion

  }

  /// Reads a device status changed broadcast from a received message.
  ///
  /// - Parameter message: A message the modem received.
  /// - Returns: `nil` unless the message is a standard-length broadcast with cmd1 `0x27`.
  public init?(_ message: ReceivedMessage) {

    guard message.isStandardBroadcast(command1: 0x27) else {

      return nil

    }

    let identity = message.reportedIdentity

    self.init(
      sender: message.sender,
      category: identity.category,
      subcategory: identity.subcategory,
      firmwareVersion: identity.firmwareVersion
    )

  }

}
