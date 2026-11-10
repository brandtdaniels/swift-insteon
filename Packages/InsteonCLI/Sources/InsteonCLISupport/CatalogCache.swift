import Foundation
import InsteonCore

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
  /// Without a bundled copy, nothing can check a cached copy's guards, so the bundled copy is
  /// still the answer and the cached one isn't used; without a cached copy, the bundled one
  /// is.
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

      return .bundled

    }

    guard cached.isCompatible(with: bundled), cached.patch >= bundled.patch else {

      return .bundled

    }

    return .cached

  }

  /// What to do with the cached copy of the catalog, once it's read and checked against the
  /// bundled copy.
  public enum CachedCatalog {

    /// Use the cached copy.
    case use(ProductCatalog)

    /// Use the bundled copy, after the warning, as the cached copy weakens its guards.
    case useBundled(warning: String)

    /// Use no catalog, after the warning, as the bundled copy, which the cached one is checked
    /// against, is missing or can't be read.
    case useNone(warning: String)

    /// The cached copy can't be read as a catalog.
    case unreadable

  }

  /// Reads the cached copy of the catalog and says which copy to use.
  ///
  /// - Parameters:
  ///   - json: The cached copy's JSON.
  ///   - path: The cached copy's file, for a warning.
  ///   - reading: Reads and checks a catalog, as `ProductCatalog.init(json:)` does.
  /// - Returns: What to do.
  public static func cachedCatalog(_ json: Data, path: String, reading: (Data) throws -> ProductCatalog) -> CachedCatalog {

    do {

      return .use(try reading(json))

    } catch let ProductCatalogError.weakensGuards(weakenings) {

      return .useBundled(warning: CatalogText.cachedWeakensGuards(path: path, weakenings))

    } catch ProductCatalogError.bundledCopyMissing {

      return .useNone(warning: CatalogText.cachedUnchecked(path: path, bundledIsMissing: true))

    } catch ProductCatalogError.bundledCopyUnreadable {

      return .useNone(warning: CatalogText.cachedUnchecked(path: path, bundledIsMissing: false))

    } catch {

      return .unreadable

    }

  }

  /// Reads the cached catalog's version from its file's JSON, a string such as `"0.6.26"`.
  ///
  /// - Parameter json: The file's contents.
  /// - Returns: The version, or `nil` if the contents aren't a version.
  public static func version(json: Data) -> DeviceCatalogVersion? {

    ProductCatalogStore.version(json: json)

  }

  /// The cached catalog's version as its file's JSON, a string such as `"0.6.26"`.
  ///
  /// - Parameter version: The version.
  /// - Returns: The JSON.
  /// - Throws: `EncodingError` if the version can't be encoded.
  public static func versionJSON(_ version: DeviceCatalogVersion) throws -> Data {

    try ProductCatalogStore.versionJSON(version)

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

  /// What `insteon catalog update` says when the published copy is older than the copy in use
  /// or the bundled one, so it isn't downloaded.
  ///
  /// - Parameters:
  ///   - published: The published copy's version.
  ///   - current: The version of the copy in use, which stays.
  /// - Returns: The message.
  public static func publishedIsOlder(published: DeviceCatalogVersion, current: DeviceCatalogVersion) -> String {

    "The published Insteon device catalog, \(published), is older than the current copy, \(current), so it isn't downloaded and the current copy stays."

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

  /// What `insteon catalog update` says when the published copy would let more be sent or
  /// written to a device than the bundled copy does, so it isn't used.
  ///
  /// - Parameters:
  ///   - weakenings: The weakened guards.
  ///   - current: The version of the copy in use, which stays.
  /// - Returns: The message.
  public static func publishedWeakensGuards(_ weakenings: [GuardWeakening], current: DeviceCatalogVersion) -> String {

    "The published Insteon device catalog would let more be sent or written to a device than the bundled copy does, "
      + "weakening the guards that keep it reachable and unlocked (\(list(weakenings))), so it isn't used and the current copy, \(current), stays."

  }

  /// The warning when the cached copy would let more be sent or written to a device than the
  /// bundled copy does, so the bundled copy is used.
  ///
  /// - Parameters:
  ///   - path: The cached copy's file.
  ///   - weakenings: The weakened guards.
  /// - Returns: The warning.
  public static func cachedWeakensGuards(path: String, _ weakenings: [GuardWeakening]) -> String {

    "insteon: warning: the cached Insteon device catalog at \(path) would let more be sent or written to a device than the bundled copy does, "
      + "weakening the guards that keep it reachable and unlocked (\(list(weakenings))), so the bundled copy is used. "
      + "'insteon catalog update' replaces it."

  }

  /// The warning when the cached copy can't be checked, since the bundled copy is missing or
  /// can't be read, so it isn't used.
  ///
  /// - Parameters:
  ///   - path: The cached copy's file.
  ///   - bundledIsMissing: Whether the bundled copy is missing, rather than unreadable.
  /// - Returns: The warning.
  public static func cachedUnchecked(path: String, bundledIsMissing: Bool) -> String {

    let problem: String = bundledIsMissing ? "isn't next to it" : "couldn't be read"

    return "insteon: warning: the cached Insteon device catalog at \(path) isn't used: the catalog the command ships with \(problem), "
      + "so nothing can check the cached copy's guards. Scripts/install-insteon.sh installs the command with it."

  }

  /// Weakened guards as a list, such as `0x01/0x7A flagBits Get Operating Flags 0x00 kept bits 0x40`.
  static func list(_ weakenings: [GuardWeakening]) -> String {

    weakenings.map(\.description).joined(separator: ", ")

  }

}
