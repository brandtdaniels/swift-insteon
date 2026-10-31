/// A version of the Insteon device catalog, `MAJOR.MINOR.PATCH`, as its manifest gives it.
///
/// The catalog follows semantic versioning. PATCH counts changes to its data, MINOR changes to
/// its format, and MAJOR changes that break a client built for the earlier format. Below 1.0
/// the format can change in any MINOR, so this package reads only a catalog with the same
/// MAJOR.MINOR as the copy it ships with:
///
/// ```swift
/// let bundled = try DeviceCatalog.bundledVersion()
///
/// if DeviceCatalogVersion("0.6.12")?.isCompatible(with: bundled) == true {
///   print("This package reads it")
/// }
/// ```
///
/// It encodes and decodes as its string, such as `"0.6.12"`, so an app can save it beside a
/// catalog it downloaded.
public struct DeviceCatalogVersion: Hashable, Sendable, LosslessStringConvertible, Codable {

  /// The MAJOR version, which the catalog's published path names, such as `v0`.
  public var major: Int

  /// The MINOR version, raised when the catalog's format changes.
  public var minor: Int

  /// The PATCH version, raised when the catalog's data changes but not its format.
  public var patch: Int

  /// Creates a version.
  ///
  /// - Parameters:
  ///   - major: The MAJOR version.
  ///   - minor: The MINOR version.
  ///   - patch: The PATCH version.
  public init(major: Int, minor: Int, patch: Int) {

    self.major = major
    self.minor = minor
    self.patch = patch

  }

  /// Reads a version written `MAJOR.MINOR.PATCH`, such as `"0.6.12"`.
  ///
  /// - Parameter description: The version, three numbers of ASCII digits separated by dots.
  /// - Returns: The version, or `nil` if it isn't written that way.
  public init?(_ description: String) {

    let parts = description.split(separator: ".", omittingEmptySubsequences: false)

    // A leading zero would read back written another way, so it isn't allowed.
    guard
      parts.count == 3,
      parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } && !($0.count > 1 && $0.first == "0") })
    else {

      return nil

    }

    let numbers = parts.compactMap { Int($0) }

    guard numbers.count == 3 else {

      return nil

    }

    self.init(major: numbers[0], minor: numbers[1], patch: numbers[2])

  }

  /// The version written `MAJOR.MINOR.PATCH`.
  public var description: String {

    "\(major).\(minor).\(patch)"

  }

  /// Whether a catalog of this version is in the same format as one of another version: the
  /// same MAJOR and MINOR, whatever their PATCH.
  ///
  /// - Parameter other: The other version, such as ``DeviceCatalog/bundledVersion()``.
  /// - Returns: `true` if the MAJOR and MINOR versions are the same.
  public func isCompatible(with other: DeviceCatalogVersion) -> Bool {

    major == other.major && minor == other.minor

  }

  /// Decodes a version from its string, such as `"0.6.12"`.
  ///
  /// - Parameter decoder: The decoder to read from.
  /// - Throws: `DecodingError` if the value isn't a string written `MAJOR.MINOR.PATCH`.
  public init(from decoder: any Decoder) throws {

    let container = try decoder.singleValueContainer()
    let text = try container.decode(String.self)

    guard let version = DeviceCatalogVersion(text) else {

      throw DecodingError.dataCorruptedError(in: container, debugDescription: "\(text) isn't a version written MAJOR.MINOR.PATCH.")

    }

    self = version

  }

  /// Encodes the version as its string, such as `"0.6.12"`.
  ///
  /// - Parameter encoder: The encoder to write to.
  /// - Throws: The encoder's error.
  public func encode(to encoder: any Encoder) throws {

    var container = encoder.singleValueContainer()
    try container.encode(description)

  }

}

extension DeviceCatalogVersion: Comparable {

  /// Whether a version is older than another: its MAJOR, then its MINOR, then its PATCH is
  /// lower.
  ///
  /// - Parameters:
  ///   - lhs: A version.
  ///   - rhs: Another version.
  /// - Returns: `true` if `lhs` comes before `rhs`.
  public static func < (lhs: DeviceCatalogVersion, rhs: DeviceCatalogVersion) -> Bool {

    (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)

  }

}

/// The fields of the catalog's `manifest.json` this package reads.
struct CatalogManifest: Decodable, Sendable {

  /// The catalog's version.
  let version: DeviceCatalogVersion

  /// The catalog's file name, beside the manifest.
  let catalog: String

  /// The catalog's SHA-256, as lowercase hexadecimal.
  let sha256: String

}
