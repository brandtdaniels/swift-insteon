import InsteonProtocol

/// The command set a product uses under one of its identities, and the firmware versions that
/// use it.
public struct CommandSetEntry: Hashable, Sendable {

  /// The command set's identifier.
  public var commandSet: CommandSetID

  /// The category the product reports.
  public var category: DeviceCategory

  /// The subcategory the product reports.
  public var subcategory: DeviceSubcategory

  /// The firmware versions that use the command set, or `nil` for every version.
  public var firmware: FirmwareSelection?

  /// Creates a command set entry.
  ///
  /// - Parameters:
  ///   - commandSet: The command set's identifier.
  ///   - category: The category the product reports.
  ///   - subcategory: The subcategory the product reports.
  ///   - firmware: The firmware versions that use the command set, or `nil` for every version.
  public init(commandSet: CommandSetID, category: DeviceCategory, subcategory: DeviceSubcategory, firmware: FirmwareSelection? = nil) {

    self.commandSet = commandSet
    self.category = category
    self.subcategory = subcategory
    self.firmware = firmware

  }

  /// Whether a device reporting these values uses the command set.
  ///
  /// - Parameters:
  ///   - category: The category the device reported.
  ///   - subcategory: The subcategory the device reported.
  ///   - firmwareVersion: The firmware version the device reported, if any.
  /// - Returns: `true` if the identity matches and, when the entry selects firmware, the
  ///   version is selected.
  public func covers(category: DeviceCategory, subcategory: DeviceSubcategory, firmwareVersion: FirmwareVersion?) -> Bool {

    guard category == self.category, subcategory == self.subcategory else {

      return false

    }

    return firmware?.contains(firmwareVersion) ?? true

  }

}

extension CommandSetEntry: Decodable {

  private enum CodingKeys: String, CodingKey {

    case commandSet
    case category
    case subcategory
    case firmware

  }

  /// Decodes an entry from a profile's `commandSets`.
  ///
  /// - Parameter decoder: The decoder to read from.
  /// - Throws: `DecodingError` if a byte isn't written as `0x` and two hexadecimal digits, or
  ///   a firmware selection doesn't have exactly one of `only` and `except`.
  public init(from decoder: any Decoder) throws {

    let container = try decoder.container(keyedBy: CodingKeys.self)

    self.init(
      commandSet: CommandSetID(rawValue: try container.decode(String.self, forKey: .commandSet)),
      category: DeviceCategory(rawValue: try container.decode(ProfileByte.self, forKey: .category).value),
      subcategory: DeviceSubcategory(rawValue: try container.decode(ProfileByte.self, forKey: .subcategory).value),
      firmware: try container.decodeIfPresent(FirmwareSelection.self, forKey: .firmware)
    )

  }

}
