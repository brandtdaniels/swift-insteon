import Foundation
import InsteonDeviceCatalog

/// Which copy of the Insteon device catalog the `insteon` command uses.
public enum CatalogSource: Hashable, Sendable {

  /// The copy that ships with the package, in the bundle next to the command.
  case bundled

  /// The copy `insteon catalog update` downloaded into the cache directory.
  case cached

}

/// The `insteon` command's own copy of the Insteon device catalog, which
/// `insteon catalog update` downloads so new catalog data reaches the command without a new
/// release of the package.
///
/// The copy is `$XDG_CACHE_HOME/insteon/catalog.json`, or `~/.cache/insteon/catalog.json`,
/// with its version, such as `"0.6.26"`, in `catalog-version.json` beside it. Both hold only
/// the public catalog.
public enum CatalogCache {

  /// The catalog's path inside the cache directory: `insteon/catalog.json`.
  public static let relativePath: String = "insteon/catalog.json"

  /// The path of the catalog's version inside the cache directory:
  /// `insteon/catalog-version.json`.
  public static let versionRelativePath: String = "insteon/catalog-version.json"

  /// The cached catalog's file, as `CachePaths.path(_:environment:)` finds it.
  ///
  /// - Parameter environment: The process's environment.
  /// - Returns: The path, or `nil` if neither `XDG_CACHE_HOME` nor `HOME` is set.
  public static func path(environment: [String: String]) -> String? {

    CachePaths.path(relativePath, environment: environment)

  }

  /// The file of the cached catalog's version, as `CachePaths.path(_:environment:)` finds it.
  ///
  /// - Parameter environment: The process's environment.
  /// - Returns: The path, or `nil` if neither `XDG_CACHE_HOME` nor `HOME` is set.
  public static func versionPath(environment: [String: String]) -> String? {

    CachePaths.path(versionRelativePath, environment: environment)

  }

  /// Which copy of the catalog to use.
  ///
  /// The cached copy is used when it has the same MAJOR.MINOR as the bundled copy, so the
  /// package reads its format, and a PATCH at least as high, so it's at least as new.
  /// Without a bundled copy, a cached one is used whatever its version; without a cached
  /// copy, the bundled one is.
  ///
  /// ```swift
  /// let bundled = DeviceCatalogVersion(major: 0, minor: 6, patch: 25)
  ///
  /// CatalogCache.source(bundled: bundled, cached: DeviceCatalogVersion("0.6.26"))   // .cached
  /// CatalogCache.source(bundled: bundled, cached: DeviceCatalogVersion("0.6.24"))   // .bundled
  /// CatalogCache.source(bundled: bundled, cached: DeviceCatalogVersion("0.7.0"))    // .bundled
  /// ```
  ///
  /// - Parameters:
  ///   - bundled: The bundled copy's version, or `nil` if the bundle isn't there.
  ///   - cached: The cached copy's version, or `nil` if there's no cached copy.
  /// - Returns: The copy to use.
  public static func source(bundled: DeviceCatalogVersion?, cached: DeviceCatalogVersion?) -> CatalogSource {

    guard let cached else {

      return .bundled

    }

    guard let bundled else {

      return .cached

    }

    guard cached.isCompatible(with: bundled), cached.patch >= bundled.patch else {

      return .bundled

    }

    return .cached

  }

  /// Reads the cached catalog's version from its file's JSON, a string such as `"0.6.26"`.
  ///
  /// - Parameter json: The file's contents.
  /// - Returns: The version, or `nil` if the contents aren't a version.
  public static func version(json: Data) -> DeviceCatalogVersion? {

    try? JSONDecoder().decode(DeviceCatalogVersion.self, from: json)

  }

  /// The cached catalog's version as its file's JSON, a string such as `"0.6.26"`.
  ///
  /// - Parameter version: The version.
  /// - Returns: The JSON.
  /// - Throws: `EncodingError` if the version can't be encoded.
  public static func versionJSON(_ version: DeviceCatalogVersion) throws -> Data {

    try JSONEncoder().encode(version)

  }

}

/// What `insteon catalog` and `insteon catalog update` print.
public enum CatalogText {

  /// The lines `insteon catalog` prints: the bundled copy's version, the cached copy's, and
  /// which copy is in use.
  ///
  /// - Parameters:
  ///   - bundled: The bundled copy's version, or `nil` if the bundle isn't there.
  ///   - cached: The cached copy's version, or `nil` if there's none or it can't be read.
  ///   - hasCachedFile: Whether there's a cached copy, so a `nil` version means it can't be
  ///     read.
  ///   - inUse: The copy in use, or `nil` if neither can be read.
  /// - Returns: The lines.
  public static func status(
    bundled: DeviceCatalogVersion?,
    cached: DeviceCatalogVersion?,
    hasCachedFile: Bool,
    inUse: CatalogSource?
  ) -> [String] {

    let bundledText: String = bundled.map { "\($0)" } ?? "missing"
    let cachedText: String

    if let cached {

      cachedText = "\(cached)"

    } else {

      cachedText = hasCachedFile ? "unreadable" : "none"

    }

    let inUseText: String

    switch inUse {
    case .bundled:
      inUseText = "bundled"
    case .cached:
      inUseText = "cached"
    case nil:
      inUseText = "none"
    }

    return [
      "Bundled:  \(bundledText)",
      "Cached:   \(cachedText)",
      "In use:   \(inUseText)"
    ]

  }

  /// What `insteon catalog update` says after saving a newer copy, such as
  /// "Updated the Insteon device catalog to 0.6.26."
  ///
  /// - Parameter version: The saved copy's version.
  /// - Returns: The message.
  public static func updated(to version: DeviceCatalogVersion) -> String {

    "Updated the Insteon device catalog to \(version)."

  }

  /// What `insteon catalog update` says when the copy in use is the published one, such as
  /// "The Insteon device catalog is up to date (0.6.26)."
  ///
  /// - Parameter version: The version of the copy in use.
  /// - Returns: The message.
  public static func upToDate(_ version: DeviceCatalogVersion) -> String {

    "The Insteon device catalog is up to date (\(version))."

  }

  /// What `insteon catalog update` says when the published copy is older than the bundled
  /// one, so it isn't saved.
  ///
  /// - Parameters:
  ///   - published: The published copy's version.
  ///   - bundled: The bundled copy's version.
  /// - Returns: The message.
  public static func bundledIsNewer(published: DeviceCatalogVersion, bundled: DeviceCatalogVersion) -> String {

    "The bundled Insteon device catalog, \(bundled), is newer than the published one, \(published), so the published one isn't saved."

  }

  /// What `insteon catalog update` says when the published copy is in a format this package
  /// doesn't read: a different MAJOR.MINOR than the bundled copy's.
  ///
  /// - Parameters:
  ///   - published: The published copy's version.
  ///   - bundled: The bundled copy's version, whose MAJOR.MINOR is the format the package reads.
  ///   - current: The version of the copy in use, which stays.
  /// - Returns: The message.
  public static func incompatible(
    published: DeviceCatalogVersion,
    bundled: DeviceCatalogVersion,
    current: DeviceCatalogVersion
  ) -> String {

    let format: String = "\(bundled.major).\(bundled.minor)"
    let isNewerFormat: Bool = published.major > bundled.major
      || (published.major == bundled.major && published.minor > bundled.minor)

    if isNewerFormat {

      return "The published Insteon device catalog, \(published), needs a newer swift-insteon than this command, "
        + "which reads catalog \(format), so the current copy, \(current), stays. "
        + "Update swift-insteon and reinstall the command to get it."

    }

    return "The published Insteon device catalog, \(published), is in an older format than this command reads, "
      + "catalog \(format), so the current copy, \(current), stays."

  }

}
