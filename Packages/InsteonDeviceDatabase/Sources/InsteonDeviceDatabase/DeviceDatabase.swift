import Foundation
import InsteonProtocol

/// A database of device profiles, for finding what a device is and can do from the identity it
/// reports.
///
/// The package ships a copy of the INSTEON device database, which ``DeviceDatabase/bundled()``
/// loads. An app can instead load a copy it downloaded, such as with `DeviceDatabaseUpdater`,
/// with ``DeviceDatabase/init(json:)``.
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

    self.init(profiles: try JSONDecoder().decode(Contents.self, from: json).devices)

  }

  /// Loads the copy of the database the package ships with.
  ///
  /// The copy is read once, the first time it's asked for.
  ///
  /// - Returns: The database.
  /// - Throws: ``DeviceDatabaseError/missingBundledDatabase`` if the copy isn't in the
  ///   package's resources, or the error reading it.
  public static func bundled() throws -> DeviceDatabase {

    try bundledCopy.get()

  }

  /// The copy the package ships with, or the error reading it.
  private static let bundledCopy = Result<DeviceDatabase, any Error> {

    try DeviceDatabase(json: bundledJSON())

  }

  /// The JSON of the copy the package ships with.
  static func bundledJSON() throws -> Data {

    guard let url = Bundle.module.url(forResource: "database", withExtension: "json") else {

      throw DeviceDatabaseError.missingBundledDatabase

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
  /// - Returns: The matching profile, or `nil` if there's none. The published database never
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

  /// The profile of a model.
  ///
  /// - Parameter model: The model number.
  /// - Returns: The first profile for the model, or `nil` if there's none.
  public func profile(model: ProductModel) -> DeviceProfile? {

    profiles.first { $0.model == model }

  }

  /// The database's contents, with its format version checked before its profiles are read.
  private struct Contents: Decodable {

    private enum CodingKeys: String, CodingKey {

      case schemaVersion
      case devices

    }

    let devices: [DeviceProfile]

    init(from decoder: any Decoder) throws {

      let container = try decoder.container(keyedBy: CodingKeys.self)
      let version = try container.decode(Int.self, forKey: .schemaVersion)

      guard version == DeviceDatabase.schemaVersion else {

        throw DeviceDatabaseError.unsupportedSchemaVersion(version)

      }

      devices = try container.decode([DeviceProfile].self, forKey: .devices)

    }

  }

}

/// Errors reading a ``DeviceDatabase``.
public enum DeviceDatabaseError: Error, Hashable, Sendable {

  /// The database is in a format version this package doesn't read, with that version.
  case unsupportedSchemaVersion(Int)

  /// The copy of the database the package ships with isn't in its resources.
  case missingBundledDatabase

  /// The server answered a request for the manifest or the database with a status other than
  /// 2xx, with that status.
  case unexpectedStatus(Int)

  /// The manifest isn't the JSON the INSTEON device database publishes, or names its
  /// database by anything but a plain file name.
  case malformedManifest

  /// The downloaded database's SHA-256 doesn't match the manifest's, such as when one was
  /// fetched before a new version was published and the other after.
  case checksumMismatch

}
