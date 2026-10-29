import Foundation
import InsteonProtocol

/// A catalog of device profiles, for finding what a device is and can do from the identity it
/// reports.
///
/// The package ships a copy of the Insteon device catalog, which ``DeviceCatalog/bundled()``
/// loads, throwing ``DeviceCatalogError/missingBundledCatalog`` if the copy's bundle is
/// missing. An app can keep a newer copy with ``DeviceCatalogUpdater``, or load one it
/// downloaded itself with ``DeviceCatalog/init(json:)`` or ``DeviceCatalog/load(contentsOf:)``.
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
  /// The catalog doesn't carry its version; its manifest does. Read only a catalog whose
  /// version has the same MAJOR.MINOR as ``DeviceCatalog/bundledVersion()``, as
  /// ``DeviceCatalogUpdater`` makes sure of, since a catalog in another format may not read, or
  /// may read differently.
  ///
  /// - Parameter json: The catalog's JSON.
  /// - Throws: `DecodingError` if the JSON isn't a catalog.
  public init(json: Data) throws {

    let contents = try JSONDecoder().decode(Contents.self, from: json)

    self.init(profiles: contents.devices, commandSets: contents.commandSets)

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

  /// The catalog's contents.
  private struct Contents: Decodable {

    private enum CodingKeys: String, CodingKey {

      case devices
      case commandSets

    }

    let devices: [DeviceProfile]

    let commandSets: [CommandSet]

    init(from decoder: any Decoder) throws {

      let container = try decoder.container(keyedBy: CodingKeys.self)

      devices = try container.decode([DeviceProfile].self, forKey: .devices)
      commandSets = try container.decodeIfPresent([CommandSet].self, forKey: .commandSets) ?? []

    }

  }

}

/// Errors reading a ``DeviceCatalog``.
public enum DeviceCatalogError: Error, Hashable, Sendable {

  /// The copy of the catalog the package ships with, or its manifest, isn't found: its bundle,
  /// one of ``DeviceCatalog/bundleNames``, isn't in any of the places it's looked for, such as
  /// when a command was copied without the bundle beside it.
  case missingBundledCatalog

}

extension DeviceCatalogError: LocalizedError {

  /// A description of the error to show.
  public var errorDescription: String? {

    switch self {

    case .missingBundledCatalog:
      let names: String = DeviceCatalog.bundleNames.joined(separator: " or ")
      return "The Insteon device catalog isn't found. Its bundle, \(names), must be beside the program or in its resources."

    }

  }

}
