/// The identity a modem reports in reply to ``SerialCommand/getModemInfo``.
public struct ModemInfo: Hashable, Sendable {

  /// The modem's INSTEON address.
  public var address: InsteonAddress

  /// The modem's device category.
  public var category: DeviceCategory

  /// The modem's device subcategory.
  public var subcategory: UInt8

  /// The modem's firmware version.
  public var firmwareVersion: UInt8

  /// Creates modem information.
  ///
  /// - Parameters:
  ///   - address: The modem's address.
  ///   - category: The device category.
  ///   - subcategory: The device subcategory.
  ///   - firmwareVersion: The firmware version.
  public init(address: InsteonAddress, category: DeviceCategory, subcategory: UInt8, firmwareVersion: UInt8) {

    self.address = address
    self.category = category
    self.subcategory = subcategory
    self.firmwareVersion = firmwareVersion

  }

}
