import InsteonProtocol

/// Firmware versions: only some, or every version except some.
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

/// The Insteon engine a product runs under one of its identities, and the firmware versions
/// that run it.
///
/// A product's identities and firmware versions can run different engines, so the catalog
/// gives the engine per identity and firmware rather than per product. A device also reports
/// its engine in reply to InsteonProtocol's `StandardDirectCommand.getEngineVersion`, which is
/// the surer source; the catalog's entries are for deciding before asking, or for a device
/// that doesn't answer.
public struct DeviceEngine: Hashable, Sendable {

  /// The engine.
  public var engine: InsteonEngine

  /// The category the product reports.
  public var category: DeviceCategory

  /// The subcategory the product reports.
  public var subcategory: DeviceSubcategory

  /// The firmware versions that run the engine, or `nil` for every version.
  public var firmware: FirmwareSelection?

  /// Creates an engine entry.
  ///
  /// - Parameters:
  ///   - engine: The engine.
  ///   - category: The category the product reports.
  ///   - subcategory: The subcategory the product reports.
  ///   - firmware: The firmware versions that run the engine, or `nil` for every version.
  public init(engine: InsteonEngine, category: DeviceCategory, subcategory: DeviceSubcategory, firmware: FirmwareSelection? = nil) {

    self.engine = engine
    self.category = category
    self.subcategory = subcategory
    self.firmware = firmware

  }

  /// Whether a device reporting these values runs the engine.
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

extension DeviceEngine {

  private enum CodingKeys: String, CodingKey {

    case engine
    case category
    case subcategory
    case firmware

  }

  private struct Selection: Decodable {

    let only: [ProfileByte]?

    let except: [ProfileByte]?

  }

  /// The catalog's names for the engines.
  private static let engines: [String: InsteonEngine] = ["i1": .i1, "i2": .i2, "i2cs": .i2cs]

  /// Decodes an engine entry, or returns `nil` for an engine from a later version of the
  /// catalog.
  ///
  /// - Parameter decoder: The decoder to read from.
  /// - Throws: `DecodingError` if a byte isn't written as `0x` and two hexadecimal digits, or
  ///   a firmware selection doesn't have exactly one of `only` and `except`.
  init?(from decoder: any Decoder) throws {

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

    let category = DeviceCategory(rawValue: try container.decode(ProfileByte.self, forKey: .category).value)
    let subcategory = DeviceSubcategory(rawValue: try container.decode(ProfileByte.self, forKey: .subcategory).value)

    guard let engine = Self.engines[try container.decode(String.self, forKey: .engine)] else {

      return nil

    }

    self.init(engine: engine, category: category, subcategory: subcategory, firmware: firmware)

  }

}
