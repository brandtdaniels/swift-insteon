import InsteonProtocol

/// The firmware versions that have a capability.
public enum FirmwareSelection: Hashable, Sendable {

  /// Only these versions.
  case only(Set<FirmwareVersion>)

  /// Every version except these.
  case except(Set<FirmwareVersion>)

  /// Whether a firmware version a device reported is selected.
  ///
  /// A device that reports no firmware version, or `0xFF`, which devices report when they
  /// don't give one, isn't selected: its version could be any of them.
  ///
  /// - Parameter version: The firmware version the device reported, if any.
  /// - Returns: `true` if the selection includes the version.
  public func contains(_ version: FirmwareVersion?) -> Bool {

    guard let version, version.rawValue != 0xFF else {

      return false

    }

    switch self {
    case let .only(versions): return versions.contains(version)
    case let .except(versions): return !versions.contains(version)
    }

  }

}

/// One of a product's identities that a capability applies to, and the firmware versions
/// under it that have the capability.
public struct ScopedIdentity: Hashable, Sendable {

  /// The category the product reports.
  public var category: DeviceCategory

  /// The subcategory the product reports.
  public var subcategory: DeviceSubcategory

  /// The firmware versions that have the capability, or `nil` for every version.
  public var firmware: FirmwareSelection?

  /// Creates a scoped identity.
  ///
  /// - Parameters:
  ///   - category: The category the product reports.
  ///   - subcategory: The subcategory the product reports.
  ///   - firmware: The firmware versions that have the capability, or `nil` for every
  ///     version.
  public init(category: DeviceCategory, subcategory: DeviceSubcategory, firmware: FirmwareSelection? = nil) {

    self.category = category
    self.subcategory = subcategory
    self.firmware = firmware

  }

  /// Whether a device reporting these values has the capability.
  ///
  /// - Parameters:
  ///   - category: The category the device reported.
  ///   - subcategory: The subcategory the device reported.
  ///   - firmwareVersion: The firmware version the device reported, if any.
  /// - Returns: `true` if the identity matches and, when it selects firmware, the version is
  ///   selected.
  public func covers(category: DeviceCategory, subcategory: DeviceSubcategory, firmwareVersion: FirmwareVersion?) -> Bool {

    guard category == self.category, subcategory == self.subcategory else {

      return false

    }

    return firmware?.contains(firmwareVersion) ?? true

  }

}

/// Which of a product's identities and firmware versions have a capability.
public enum CapabilityCoverage: Hashable, Sendable {

  /// Every identity and firmware version of the product.
  case everyVersion

  /// Only these identities, each with the firmware versions that have the capability.
  case identities([ScopedIdentity])

  /// Whether a device reporting these values has the capability.
  ///
  /// - Parameters:
  ///   - category: The category the device reported.
  ///   - subcategory: The subcategory the device reported.
  ///   - firmwareVersion: The firmware version the device reported, if any.
  /// - Returns: `true` if the coverage includes the device.
  public func covers(category: DeviceCategory, subcategory: DeviceSubcategory, firmwareVersion: FirmwareVersion?) -> Bool {

    switch self {
    case .everyVersion:
      true
    case let .identities(identities):
      identities.contains { $0.covers(category: category, subcategory: subcategory, firmwareVersion: firmwareVersion) }
    }

  }

}

extension ScopedIdentity: Decodable {

  private enum CodingKeys: String, CodingKey {

    case category
    case subcategory
    case firmware

  }

  private struct Selection: Decodable {

    let only: [ProfileByte]?

    let except: [ProfileByte]?

  }

  /// Decodes a scoped identity from a capability's `identities`.
  ///
  /// - Parameter decoder: The decoder to read from.
  /// - Throws: `DecodingError` if a byte isn't written as `0x` and two hexadecimal digits, or
  ///   a firmware selection doesn't have exactly one of `only` and `except`.
  public init(from decoder: any Decoder) throws {

    let container = try decoder.container(keyedBy: CodingKeys.self)
    var firmware: FirmwareSelection?

    if let selection = try container.decodeIfPresent(Selection.self, forKey: .firmware) {

      switch (selection.only, selection.except) {
      case let (only?, nil):
        firmware = .only(Set(only.map { FirmwareVersion(rawValue: $0.value) }))
      case let (nil, except?):
        firmware = .except(Set(except.map { FirmwareVersion(rawValue: $0.value) }))
      default:
        throw DecodingError.dataCorruptedError(forKey: .firmware, in: container, debugDescription: "A firmware selection has exactly one of only and except.")
      }

    }

    self.init(
      category: DeviceCategory(rawValue: try container.decode(ProfileByte.self, forKey: .category).value),
      subcategory: DeviceSubcategory(rawValue: try container.decode(ProfileByte.self, forKey: .subcategory).value),
      firmware: firmware
    )

  }

}
