/// A database of INSTEON products that records what each product can do.
///
/// A shared product database is the one place that records each product's capabilities, so
/// apps don't each keep their own list of devices. Conform a type to this protocol to read it
/// from wherever your app gets it, such as a web service or a copy bundled with the app.
///
/// A device is looked up by the category and subcategory it reports in its
/// ``SetButtonPressed`` broadcast, along with its firmware version when that's known, since
/// capabilities can differ between firmware versions. How a database answers for an unknown
/// firmware version, for example with the closest earlier one, is up to the database.
public protocol ProductDatabase: Sendable {

  /// Looks up the capabilities of a kind of device.
  ///
  /// - Parameters:
  ///   - category: The device's category.
  ///   - subcategory: The device's subcategory.
  ///   - firmwareVersion: The device's firmware version, if known.
  /// - Returns: The device's capabilities, or `nil` if the database has no record of it.
  /// - Throws: An error if the database couldn't be read.
  func capabilities(
    category: DeviceCategory,
    subcategory: DeviceSubcategory,
    firmwareVersion: FirmwareVersion?
  ) async throws -> (any DeviceCapabilities)?

}
