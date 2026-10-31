import InsteonProtocol

/// A category and subcategory a product reports, and the firmware versions it reports them
/// with.
///
/// A device reports its category, subcategory and firmware version when it's asked to
/// identify itself, when its SET button is pressed, and in some heartbeats. An identity
/// without a firmware range covers every version; one with a range covers a product that
/// reports the same category and subcategory with different behavior across versions.
public struct DeviceIdentity: Hashable, Sendable {

  /// The Insteon Product Key a product reports, as the catalog gives it.
  ///
  /// A product reports its key in D2 through D4 of the Product Data Response that answers
  /// Product Data Request (cmd1 `0x03`, cmd2 `0x00`).
  public enum ProductKeyEntry: Hashable, Sendable {

    /// The key the product reports.
    case key(ProductKey)

    /// The product reports no key: Insteon's documents mark it Legacy, made before product
    /// keys, and it doesn't answer Product Data Request, so an app shouldn't wait for one.
    case notReported

    /// The key, or `nil` for a product that reports none.
    public var productKey: ProductKey? {

      switch self {
      case let .key(key):
        key
      case .notReported:
        nil
      }

    }

  }

  /// The category the product reports.
  public var category: DeviceCategory

  /// The subcategory the product reports.
  public var subcategory: DeviceSubcategory

  /// The firmware versions the identity covers, or `nil` for every version.
  public var firmware: ClosedRange<FirmwareVersion>?

  /// Where the variant was sold, when the subcategory tells regions apart, such as `"Europe"`.
  public var region: String?

  /// How sure the catalog is of the identity.
  public var verification: Verification

  /// The Insteon Product Key the product reports under the identity, or `nil` if no source
  /// gives it.
  public var productKey: ProductKeyEntry?

  /// How sure the catalog is of ``DeviceIdentity/productKey``, where that differs from
  /// ``DeviceIdentity/verification``, or `nil` when the identity's verification covers the key
  /// too.
  public var productKeyVerification: Verification?

  /// Creates an identity.
  ///
  /// - Parameters:
  ///   - category: The category the product reports.
  ///   - subcategory: The subcategory the product reports.
  ///   - firmware: The firmware versions the identity covers, or `nil` for every version.
  ///   - region: Where the variant was sold.
  ///   - verification: How sure the catalog is of the identity. Defaults to ``Verification/documented``.
  ///   - productKey: The Insteon Product Key the product reports. Defaults to `nil`.
  ///   - productKeyVerification: How sure the catalog is of the key, where that differs from
  ///     the identity's verification. Defaults to `nil`.
  public init(
    category: DeviceCategory,
    subcategory: DeviceSubcategory,
    firmware: ClosedRange<FirmwareVersion>? = nil,
    region: String? = nil,
    verification: Verification = .documented,
    productKey: ProductKeyEntry? = nil,
    productKeyVerification: Verification? = nil
  ) {

    self.category = category
    self.subcategory = subcategory
    self.firmware = firmware
    self.region = region
    self.verification = verification
    self.productKey = productKey
    self.productKeyVerification = productKeyVerification

  }

  /// Whether a device reporting these values has this identity.
  ///
  /// A device that reports no firmware version, or `0xFF`, which devices report when they
  /// don't give one, matches only an identity that covers every version.
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

    guard let firmwareVersion, firmwareVersion.rawValue != 0xFF else {

      return false

    }

    return firmware.contains(firmwareVersion)

  }

}

extension DeviceIdentity: Decodable {

  private enum CodingKeys: String, CodingKey {

    case category
    case subcategory
    case firmware
    case region
    case verification
    case productKey
    case productKeyVerification

  }

  private struct FirmwareRange: Decodable {

    let from: ProfileByte

    let through: ProfileByte

  }

  /// The product key as the catalog writes it: `0x` and six uppercase hexadecimal digits, D2
  /// first, or `none`.
  ///
  /// - Parameter text: The key as the catalog writes it.
  /// - Returns: The key, or `nil` for text written another way, such as by a later version of
  ///   the catalog.
  static func parseProductKey(_ text: String) -> ProductKeyEntry? {

    if text == "none" {

      return .notReported

    }

    let digits = text.dropFirst(2)

    guard text.hasPrefix("0x"), digits.count == 6, digits.allSatisfy({ $0.isHexDigit && !$0.isLowercase }), let number = UInt32(digits, radix: 16) else {

      return nil

    }

    return .key(ProductKey(UInt8(truncatingIfNeeded: number >> 16), UInt8(truncatingIfNeeded: number >> 8), UInt8(truncatingIfNeeded: number)))

  }

  /// Decodes an identity from a profile's JSON.
  ///
  /// A product key written in a way this package doesn't read reads as `nil`.
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
      region: try container.decodeIfPresent(String.self, forKey: .region),
      verification: try container.decodeIfPresent(Verification.self, forKey: .verification) ?? .documented,
      productKey: try container.decodeIfPresent(String.self, forKey: .productKey).flatMap(Self.parseProductKey),
      productKeyVerification: try container.decodeIfPresent(Verification.self, forKey: .productKeyVerification)
    )

  }

}
