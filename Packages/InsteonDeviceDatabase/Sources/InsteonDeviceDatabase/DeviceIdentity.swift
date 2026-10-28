import InsteonProtocol

/// A category and subcategory a product reports, and the firmware versions it reports them
/// with.
///
/// A device reports its category, subcategory and firmware version when it's asked to
/// identify itself, when its SET button is pressed, and in some heartbeats. An identity
/// without a firmware range covers every version; one with a range covers a product that
/// reports the same category and subcategory with different behavior across versions.
public struct DeviceIdentity: Hashable, Sendable {

  /// The category the product reports.
  public var category: DeviceCategory

  /// The subcategory the product reports.
  public var subcategory: DeviceSubcategory

  /// The firmware versions the identity covers, or `nil` for every version.
  public var firmware: ClosedRange<FirmwareVersion>?

  /// Where the variant was sold, when the subcategory tells regions apart, such as `"Europe"`.
  public var region: String?

  /// Creates an identity.
  ///
  /// - Parameters:
  ///   - category: The category the product reports.
  ///   - subcategory: The subcategory the product reports.
  ///   - firmware: The firmware versions the identity covers, or `nil` for every version.
  ///   - region: Where the variant was sold.
  public init(category: DeviceCategory, subcategory: DeviceSubcategory, firmware: ClosedRange<FirmwareVersion>? = nil, region: String? = nil) {

    self.category = category
    self.subcategory = subcategory
    self.firmware = firmware
    self.region = region

  }

  /// Whether a device reporting these values has this identity.
  ///
  /// A device that reports no firmware version, such as one that reports `0xFF`, matches only
  /// an identity that covers every version.
  ///
  /// - Parameters:
  ///   - category: The category the device reported.
  ///   - subcategory: The subcategory the device reported.
  ///   - firmwareVersion: The firmware version the device reported, if any.
  /// - Returns: `true` if the identity covers the values.
  public func matches(category: DeviceCategory, subcategory: DeviceSubcategory, firmwareVersion: FirmwareVersion?) -> Bool {

    guard category == self.category, subcategory == self.subcategory else {

      return false

    }

    guard let firmware else {

      return true

    }

    return firmwareVersion.map(firmware.contains) ?? false

  }

}

extension DeviceIdentity: Decodable {

  private enum CodingKeys: String, CodingKey {

    case category
    case subcategory
    case firmware
    case region

  }

  private struct FirmwareRange: Decodable {

    let from: ProfileByte

    let through: ProfileByte

  }

  /// Decodes an identity from a profile's JSON.
  ///
  /// - Parameter decoder: The decoder to read from.
  /// - Throws: `DecodingError` if a byte isn't written as `0x` and two hexadecimal digits, or
  ///   a firmware range ends before it starts.
  public init(from decoder: any Decoder) throws {

    let container = try decoder.container(keyedBy: CodingKeys.self)
    var firmware: ClosedRange<FirmwareVersion>?

    if let range = try container.decodeIfPresent(FirmwareRange.self, forKey: .firmware) {

      guard range.from.value <= range.through.value else {

        throw DecodingError.dataCorruptedError(forKey: .firmware, in: container, debugDescription: "The firmware range ends before it starts.")

      }

      firmware = FirmwareVersion(rawValue: range.from.value)...FirmwareVersion(rawValue: range.through.value)

    }

    self.init(
      category: DeviceCategory(rawValue: try container.decode(ProfileByte.self, forKey: .category).value),
      subcategory: DeviceSubcategory(rawValue: try container.decode(ProfileByte.self, forKey: .subcategory).value),
      firmware: firmware,
      region: try container.decodeIfPresent(String.self, forKey: .region)
    )

  }

}
