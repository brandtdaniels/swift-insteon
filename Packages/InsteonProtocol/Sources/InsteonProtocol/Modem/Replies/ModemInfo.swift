/// The identity a modem reports in reply to ``SerialCommand/getModemInfo``.
public struct ModemInfo: Hashable, Sendable {

  /// The modem's INSTEON address.
  public var address: InsteonAddress

  /// The modem's device category.
  public var category: DeviceCategory

  /// The modem's device subcategory.
  public var subcategory: DeviceSubcategory

  /// The modem's firmware version.
  public var firmwareVersion: FirmwareVersion

  /// Creates modem information.
  ///
  /// - Parameters:
  ///   - address: The modem's address.
  ///   - category: The device category.
  ///   - subcategory: The device subcategory.
  ///   - firmwareVersion: The firmware version.
  public init(address: InsteonAddress, category: DeviceCategory, subcategory: DeviceSubcategory, firmwareVersion: FirmwareVersion) {

    self.address = address
    self.category = category
    self.subcategory = subcategory
    self.firmwareVersion = firmwareVersion

  }

}

extension ModemInfo {

  /// Decodes an identity as a modem's Get IM Info and IBIOS's Get Version report it: the
  /// address, the category, the subcategory and the firmware version.
  ///
  /// - Parameter bytes: The 6 bytes of the identity.
  init(reportedBytes bytes: [UInt8]) {

    self.init(
      address: InsteonAddress(bytes[0], bytes[1], bytes[2]),
      category: DeviceCategory(rawValue: bytes[3]),
      subcategory: DeviceSubcategory(rawValue: bytes[4]),
      firmwareVersion: FirmwareVersion(rawValue: bytes[5])
    )

  }

}
