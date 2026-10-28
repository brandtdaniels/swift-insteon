import Foundation
import InsteonProtocol

/// A catalog of device profiles, for finding what a device is and can do from the identity it
/// reports.
///
/// The package ships a copy of the Insteon device catalog, which ``DeviceCatalog/bundled()``
/// loads. An app can keep a newer copy with ``DeviceCatalogUpdater``, or load one it
/// downloaded itself with ``DeviceCatalog/init(json:)``.
///
/// ```swift
/// let catalog = try DeviceCatalog.bundled()
///
/// if let pressed = SetButtonPressed(message),
///    let profile = catalog.profile(category: pressed.category, subcategory: pressed.subcategory, firmwareVersion: pressed.firmwareVersion) {
///   print(profile.model, profile.name)
/// }
/// ```
///
/// A device with no profile can still be handled by what its category implies, such as
/// dimming for `DeviceCategory.dimmableLightingControl`.
public struct DeviceCatalog: Hashable, Sendable {

  /// The version of the catalog's format this package reads: `1`.
  public static let schemaVersion = 1

  /// Every profile, in the order they were given.
  public let profiles: [DeviceProfile]

  /// Every command set, in the order they were given.
  public let commandSets: [CommandSet]

  /// The indexes in ``profiles`` of the profiles with an identity for each category and
  /// subcategory.
  private let index: [Key: [Int]]

  private struct Key: Hashable, Sendable {

    let category: DeviceCategory

    let subcategory: DeviceSubcategory

  }

  /// Creates a catalog of profiles.
  ///
  /// - Parameters:
  ///   - profiles: The profiles.
  ///   - commandSets: The command sets the profiles name. Defaults to none.
  public init(profiles: [DeviceProfile], commandSets: [CommandSet] = []) {

    var index: [Key: [Int]] = [:]

    for (offset, profile) in profiles.enumerated() {

      for key in Set(profile.identities.map { Key(category: $0.category, subcategory: $0.subcategory) }) {

        index[key, default: []].append(offset)

      }

    }

    self.profiles = profiles
    self.commandSets = commandSets
    self.index = index

  }

  /// Reads a catalog from the JSON the Insteon device catalog publishes as `catalog.json`.
  ///
  /// - Parameter json: The catalog's JSON.
  /// - Throws: ``DeviceCatalogError/unsupportedSchemaVersion(_:)`` if the catalog is in a
  ///   format other than ``DeviceCatalog/schemaVersion``, or `DecodingError` if the JSON
  ///   isn't a catalog.
  public init(json: Data) throws {

    let contents = try JSONDecoder().decode(Contents.self, from: json)

    self.init(profiles: contents.devices, commandSets: contents.commandSets)

  }

  /// Loads the copy of the catalog the package ships with.
  ///
  /// The copy is read once, the first time it's asked for.
  ///
  /// - Returns: The catalog.
  /// - Throws: ``DeviceCatalogError/missingBundledCatalog`` if the copy isn't in the
  ///   package's resources, or the error reading it.
  public static func bundled() throws -> DeviceCatalog {

    try bundledCopy.get()

  }

  /// The copy the package ships with, or the error reading it.
  private static let bundledCopy = Result<DeviceCatalog, any Error> {

    try DeviceCatalog(json: bundledJSON())

  }

  /// The JSON of the copy the package ships with, such as to save as an app's own copy.
  ///
  /// - Returns: The JSON.
  /// - Throws: ``DeviceCatalogError/missingBundledCatalog`` if the copy isn't in the
  ///   package's resources, or the error reading it.
  public static func bundledJSON() throws -> Data {

    guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json") else {

      throw DeviceCatalogError.missingBundledCatalog

    }

    return try Data(contentsOf: url)

  }

  /// The profile of a device that reported a category, subcategory and firmware version.
  ///
  /// An identity for a range of firmware versions is preferred over one for every version, so
  /// a profile for particular versions isn't hidden by a broader one. A device that reports no
  /// firmware version, or `0xFF`, matches only an identity that covers every version.
  ///
  /// - Parameters:
  ///   - category: The category the device reported.
  ///   - subcategory: The subcategory the device reported.
  ///   - firmwareVersion: The firmware version the device reported, if any.
  /// - Returns: The matching profile, or `nil` if there's none. The published catalog never
  ///   has two profiles claim the same identity.
  public func profile(category: DeviceCategory, subcategory: DeviceSubcategory, firmwareVersion: FirmwareVersion?) -> DeviceProfile? {

    var broadest: DeviceProfile?

    for offset in index[Key(category: category, subcategory: subcategory), default: []] {

      let profile = profiles[offset]

      for identity in profile.identities where identity.matches(category: category, subcategory: subcategory, firmwareVersion: firmwareVersion) {

        guard identity.firmware == nil else {

          return profile

        }

        broadest = broadest ?? profile

      }

    }

    return broadest

  }

  /// The command set a device uses, given the identity and firmware version it reported.
  ///
  /// - Parameters:
  ///   - category: The category the device reported.
  ///   - subcategory: The subcategory the device reported.
  ///   - firmwareVersion: The firmware version the device reported, if any.
  /// - Returns: The command set the device's profile names for the identity and version, or
  ///   `nil` if there's no profile, it names none, or the catalog doesn't have the one it names.
  public func commandSet(category: DeviceCategory, subcategory: DeviceSubcategory, firmwareVersion: FirmwareVersion?) -> CommandSet? {

    guard
      let profile = profile(category: category, subcategory: subcategory, firmwareVersion: firmwareVersion),
      let entry = profile.commandSets.first(where: { $0.covers(category: category, subcategory: subcategory, firmwareVersion: firmwareVersion) })
    else {

      return nil

    }

    return commandSet(id: entry.commandSet)

  }

  /// The command set with an identifier.
  ///
  /// - Parameter id: The identifier, such as `"keypadLinc"`.
  /// - Returns: The command set, or `nil` if the catalog has none with that identifier.
  public func commandSet(id: CommandSetID) -> CommandSet? {

    commandSets.first { $0.id == id }

  }

  /// The profiles a search finds, in catalog order.
  ///
  /// Every word of the search must appear in a profile's model, name, aliases or identities,
  /// ignoring case, so `"switchlinc dimmer"` finds the products once called SwitchLinc Dimmer
  /// and `"0x01/0x20"` finds the one with that identity.
  ///
  /// - Parameter query: The words to look for, separated by spaces.
  /// - Returns: The matching profiles, or every profile for an empty search.
  public func profiles(matching query: String) -> [DeviceProfile] {

    profiles.filter { $0.matches(query) }

  }

  /// The profile of a model.
  ///
  /// - Parameter model: The model number.
  /// - Returns: The first profile for the model, or `nil` if there's none.
  public func profile(model: ProductModel) -> DeviceProfile? {

    profiles.first { $0.model == model }

  }

  /// The catalog's contents, with its format version checked before its profiles are read.
  private struct Contents: Decodable {

    private enum CodingKeys: String, CodingKey {

      case schemaVersion
      case devices
      case commandSets

    }

    let devices: [DeviceProfile]

    let commandSets: [CommandSet]

    init(from decoder: any Decoder) throws {

      let container = try decoder.container(keyedBy: CodingKeys.self)
      let version = try container.decode(Int.self, forKey: .schemaVersion)

      guard version == DeviceCatalog.schemaVersion else {

        throw DeviceCatalogError.unsupportedSchemaVersion(version)

      }

      devices = try container.decode([DeviceProfile].self, forKey: .devices)
      commandSets = try container.decodeIfPresent([CommandSet].self, forKey: .commandSets) ?? []

    }

  }

}

/// Errors reading a ``DeviceCatalog``.
public enum DeviceCatalogError: Error, Hashable, Sendable {

  /// The catalog is in a format version this package doesn't read, with that version.
  case unsupportedSchemaVersion(Int)

  /// The copy of the catalog the package ships with isn't in its resources.
  case missingBundledCatalog

}
