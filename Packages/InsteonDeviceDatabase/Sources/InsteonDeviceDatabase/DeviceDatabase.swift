import Foundation
import InsteonProtocol

/// A database of device profiles, for finding what a device is and can do from the identity it
/// reports.
///
/// The package ships a copy of the INSTEON device database, which ``DeviceDatabase/bundled()``
/// loads. An app can instead load a copy it downloaded with ``DeviceDatabase/init(json:)``.
///
/// ```swift
/// let database = try DeviceDatabase.bundled()
///
/// if let pressed = SetButtonPressed(message),
///    let profile = database.profile(category: pressed.category, subcategory: pressed.subcategory, firmwareVersion: pressed.firmwareVersion) {
///   print(profile.model, profile.name)
/// }
/// ```
///
/// A device with no profile can still be handled by what its category implies, such as
/// dimming for `DeviceCategory.dimmableLightingControl`.
public struct DeviceDatabase: Hashable, Sendable {

  /// The version of the database's format this package reads: `1`.
  public static let schemaVersion = 1

  /// Every profile, in the order they were given.
  public let profiles: [DeviceProfile]

  /// The indexes in ``profiles`` of the profiles with an identity for each category and
  /// subcategory.
  private let index: [Key: [Int]]

  private struct Key: Hashable, Sendable {

    let category: DeviceCategory

    let subcategory: DeviceSubcategory

  }

  /// Creates a database of profiles.
  ///
  /// - Parameter profiles: The profiles.
  public init(profiles: [DeviceProfile]) {

    var index: [Key: [Int]] = [:]

    for (offset, profile) in profiles.enumerated() {

      for key in Set(profile.identities.map { Key(category: $0.category, subcategory: $0.subcategory) }) {

        index[key, default: []].append(offset)

      }

    }

    self.profiles = profiles
    self.index = index

  }

  /// Reads a database from the JSON the INSTEON device database publishes as `database.json`.
  ///
  /// - Parameter json: The database's JSON.
  /// - Throws: ``DeviceDatabaseError/unsupportedSchemaVersion(_:)`` if the database is in a
  ///   format other than ``DeviceDatabase/schemaVersion``, or `DecodingError` if the JSON
  ///   isn't a database.
  public init(json: Data) throws {

    let decoder = JSONDecoder()
    let version = try decoder.decode(Version.self, from: json).schemaVersion

    guard version == Self.schemaVersion else {

      throw DeviceDatabaseError.unsupportedSchemaVersion(version)

    }

    self.init(profiles: try decoder.decode(Contents.self, from: json).devices)

  }

  /// Loads the copy of the database the package ships with.
  ///
  /// The copy is read from the package's resources each time, so keep the database rather than
  /// loading it for each lookup.
  ///
  /// - Returns: The database.
  /// - Throws: ``DeviceDatabaseError/missingBundledDatabase`` if the copy isn't in the
  ///   package's resources, or the error reading it.
  public static func bundled() throws -> DeviceDatabase {

    guard let url = Bundle.module.url(forResource: "database", withExtension: "json") else {

      throw DeviceDatabaseError.missingBundledDatabase

    }

    return try DeviceDatabase(json: Data(contentsOf: url))

  }

  /// The profile of a device that reported a category, subcategory and firmware version.
  ///
  /// A device that reports no firmware version matches only an identity that covers every
  /// version.
  ///
  /// - Parameters:
  ///   - category: The category the device reported.
  ///   - subcategory: The subcategory the device reported.
  ///   - firmwareVersion: The firmware version the device reported, if any.
  /// - Returns: The first profile with a matching identity, or `nil` if there's none. The
  ///   published database has at most one.
  public func profile(category: DeviceCategory, subcategory: DeviceSubcategory, firmwareVersion: FirmwareVersion?) -> DeviceProfile? {

    index[Key(category: category, subcategory: subcategory), default: []]
      .lazy
      .map { profiles[$0] }
      .first { profile in

        profile.identities.contains { $0.matches(category: category, subcategory: subcategory, firmwareVersion: firmwareVersion) }

      }

  }

  /// The profile of a model.
  ///
  /// - Parameter model: The model number.
  /// - Returns: The first profile for the model, or `nil` if there's none.
  public func profile(model: ProductModel) -> DeviceProfile? {

    profiles.first { $0.model == model }

  }

  /// The database's format version, read before the rest.
  private struct Version: Decodable {

    let schemaVersion: Int

  }

  private struct Contents: Decodable {

    let devices: [DeviceProfile]

  }

}

/// Errors reading a ``DeviceDatabase``.
public enum DeviceDatabaseError: Error, Hashable, Sendable {

  /// The database is in a format version this package doesn't read, with that version.
  case unsupportedSchemaVersion(Int)

  /// The copy of the database the package ships with isn't in its resources.
  case missingBundledDatabase

}
