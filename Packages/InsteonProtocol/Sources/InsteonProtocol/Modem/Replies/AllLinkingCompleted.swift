/// The result of ALL-Linking the modem with another device.
public struct AllLinkingCompleted: Hashable, Sendable {

  /// The link code the modem reports: `0x00` when it became a responder, `0x01` when it became
  /// a controller, and `0xFF` when the link was deleted.
  public var linkCode: UInt8

  /// The ALL-Link group that was linked.
  public var group: UInt8

  /// The address of the other device.
  public var address: InsteonAddress

  /// The other device's category, reported only when the modem became its controller.
  public var category: DeviceCategory?

  /// The other device's subcategory, reported only when the modem became its controller.
  public var subcategory: DeviceSubcategory?

  /// The other device's firmware version, reported when the modem became its controller by a
  /// device that doesn't answer ``StandardDirectCommand/productDataRequest``. Other devices
  /// send `0xFF`, which reads as `nil`.
  public var firmwareVersion: FirmwareVersion?

  /// Creates a linking result.
  ///
  /// - Parameters:
  ///   - linkCode: The link code the modem reported.
  ///   - group: The ALL-Link group.
  ///   - address: The other device's address.
  ///   - category: The other device's category, if reported.
  ///   - subcategory: The other device's subcategory, if reported.
  ///   - firmwareVersion: The other device's firmware version, if reported.
  public init(
    linkCode: UInt8,
    group: UInt8,
    address: InsteonAddress,
    category: DeviceCategory?,
    subcategory: DeviceSubcategory?,
    firmwareVersion: FirmwareVersion?
  ) {

    self.linkCode = linkCode
    self.group = group
    self.address = address
    self.category = category
    self.subcategory = subcategory
    self.firmwareVersion = firmwareVersion

  }

  /// The modem's role in the link, or `nil` for a link code this package doesn't recognize.
  public var mode: AllLinkMode? {

    AllLinkMode(rawValue: linkCode)

  }

}
