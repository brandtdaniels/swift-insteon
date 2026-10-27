/// A source of device capabilities: the INSTEON Product Database (IPDB), or a copy of it.
///
/// The product database is the one place that records what each product can do, so apps don't
/// each keep their own list of devices. Conform a type to this protocol to read it from wherever
/// your app gets it, such as a web service or a copy bundled with the app.
///
/// A device is looked up by its ``InsteonProductKey`` when it reports one in its
/// ``ProductData``, or else by the category and subcategory in its ``SetButtonPressed``
/// broadcast. Either way, pass its firmware version when it's known, since capabilities can
/// differ between firmware versions. How a database answers for an unknown firmware version,
/// for example with the closest earlier one, is up to the database.
public protocol ProductDatabase: Sendable {

  /// Looks up the capabilities of a product by its product key.
  ///
  /// - Parameters:
  ///   - productKey: The product's key.
  ///   - firmwareVersion: The device's firmware version, if known.
  /// - Returns: The product's capabilities, or `nil` if the database has no record of it.
  /// - Throws: An error if the database couldn't be read.
  func capabilities(
    productKey: InsteonProductKey,
    firmwareVersion: UInt8?
  ) async throws -> (any DeviceCapabilities)?

  /// Looks up the capabilities of a kind of device by its category and subcategory.
  ///
  /// - Parameters:
  ///   - category: The device's category.
  ///   - subcategory: The device's subcategory.
  ///   - firmwareVersion: The device's firmware version, if known.
  /// - Returns: The device's capabilities, or `nil` if the database has no record of it.
  /// - Throws: An error if the database couldn't be read.
  func capabilities(
    category: DeviceCategory,
    subcategory: UInt8,
    firmwareVersion: UInt8?
  ) async throws -> (any DeviceCapabilities)?

}
