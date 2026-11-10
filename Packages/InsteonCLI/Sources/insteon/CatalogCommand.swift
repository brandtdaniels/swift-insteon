import Foundation
import InsteonCLISupport
import InsteonCore

/// The command's two copies of the Insteon device catalog: the one bundled next to the
/// command, and the one `insteon catalog update` keeps in the cache directory, described by
/// `CatalogCache`.
///
/// The cached copy holds only the public catalog. It's written readable only by the current
/// user, like the identity cache, and a cached copy that can't be read only means the bundled
/// copy is used.
enum CatalogStore {

  /// A copy of the catalog, and which copy it is.
  struct Loaded {

    /// The catalog.
    let catalog: ProductCatalog

    /// Which copy it was read from.
    let source: CatalogSource

  }

  /// The cached catalog's file, or `nil` if neither `XDG_CACHE_HOME` nor `HOME` is set.
  static func catalogPath() -> String? {

    CatalogCache.path(environment: ProcessInfo.processInfo.environment)

  }

  /// The file of the cached catalog's version, or `nil` if neither `XDG_CACHE_HOME` nor `HOME`
  /// is set.
  static func versionPath() -> String? {

    CatalogCache.versionPath(environment: ProcessInfo.processInfo.environment)

  }

  /// The bundled copy's version, or `nil` if the bundle or its manifest isn't there.
  static func bundledVersion() -> DeviceCatalogVersion? {

    try? ProductCatalog.bundledVersion()

  }

  /// The cached copy's files, or `nil` if neither `XDG_CACHE_HOME` nor `HOME` is set.
  static func store() -> ProductCatalogStore? {

    guard let catalogPath = catalogPath(), let versionPath = versionPath() else {

      return nil

    }

    return ProductCatalogStore(catalogPath: catalogPath, versionPath: versionPath)

  }

  /// Whether there's a cached copy of the catalog, readable or not.
  static func hasCachedCopy() -> Bool {

    store()?.hasCachedCopy ?? false

  }

  /// The cached copy's version, or `nil` if there's no cached copy or its version can't be
  /// read.
  static func cachedVersion() -> DeviceCatalogVersion? {

    store()?.cachedVersion()

  }

  /// The cached copy's JSON, or `nil` if there's none or it can't be read.
  static func cachedJSON() -> Data? {

    store()?.cachedJSON()

  }

  /// The copy of the catalog to use, as `CatalogCache.source(bundled:cached:)` chooses, or
  /// `nil` if neither copy can be read. A copy that can't be read gets a one-line warning on
  /// standard error.
  static func load() -> Loaded? {

    let bundled: DeviceCatalogVersion? = bundledVersion()
    let cached: DeviceCatalogVersion? = cachedVersion()

    if cached == nil, hasCachedCopy(), let path = versionPath() {

      Output.note(
        "insteon: warning: the cached Insteon device catalog's version, \(path), couldn't be read, so the cached copy isn't used. "
          + "'insteon catalog update' downloads it again."
      )

    }

    if CatalogCache.source(bundled: bundled, cached: cached) == .cached {

      if let json = cachedJSON() {

        switch CatalogCache.cachedCatalog(json, path: catalogPath() ?? CatalogCache.relativePath, reading: ProductCatalog.init(json:)) {
        case let .use(catalog):
          return Loaded(catalog: catalog, source: .cached)
        case let .useBundled(warning):
          Output.note(warning)
          return bundledCatalog().map { (catalog: ProductCatalog) -> Loaded in Loaded(catalog: catalog, source: .bundled) }
        case let .useNone(warning):
          Output.note(warning)
          return nil
        case .unreadable:
          break
        }

      }

      Output.note(
        "insteon: warning: the cached Insteon device catalog at \(catalogPath() ?? CatalogCache.relativePath) couldn't be read, "
          + "so it isn't used. 'insteon catalog update' downloads it again."
      )

    }

    guard let catalog = bundledCatalog() else {

      return nil

    }

    return Loaded(catalog: catalog, source: .bundled)

  }

  /// The catalog the package ships with, or `nil` after a one-line warning if it isn't beside
  /// the command, as when only the executable was copied, or can't be read.
  private static func bundledCatalog() -> ProductCatalog? {

    let url: URL

    do {

      url = try ProductCatalog.bundledCatalogURL()

    } catch {

      Output.note(
        "insteon: warning: the Insteon device catalog (\(ProductCatalog.bundleName)) isn't next to the command, "
          + "so products aren't named. Scripts/install-insteon.sh installs the command with it."
      )

      return nil

    }

    do {

      return try ProductCatalog.load(contentsOf: url)

    } catch {

      Output.note("insteon: warning: the Insteon device catalog at \(url.path) couldn't be read, so products aren't named.")

      return nil

    }

  }

  /// Saves a downloaded catalog and its version in the cache directory, each readable only by
  /// the current user and replaced whole.
  ///
  /// The catalog is written before its version. A version that's left older than its catalog
  /// is still one with the same format, since only a catalog compatible with the bundled copy
  /// is saved.
  ///
  /// - Throws: `CommandFailure` if either file can't be written.
  static func save(json: Data, version: DeviceCatalogVersion) throws {

    guard let store = store() else {

      throw noCacheDirectory

    }

    do {

      try store.save(json: json, version: version)

    } catch is ProductCatalogStoreError {

      throw CommandFailure(description: "The Insteon device catalog couldn't be saved in \(store.directory).")

    }

  }

  /// The error when there's no cache directory to keep the catalog in.
  static let noCacheDirectory = CommandFailure(description: CatalogText.noCacheDirectory)

}

/// The copies `CatalogStore` reads, for the decisions InsteonCLISupport makes about them.
struct CatalogFiles: CatalogCopies {

  func bundledVersion() -> DeviceCatalogVersion? { CatalogStore.bundledVersion() }

  var hasCacheDirectory: Bool { CatalogStore.catalogPath() != nil && CatalogStore.versionPath() != nil }

  var hasCachedCopy: Bool { CatalogStore.hasCachedCopy() }

  func cachedVersion() -> DeviceCatalogVersion? { CatalogStore.cachedVersion() }

  func cachedJSON() -> Data? { CatalogStore.cachedJSON() }

}

/// `insteon catalog` and `insteon catalog update`: show the catalog's versions, and download
/// the latest compatible one. Neither needs a Hub or modem, or reads the Hub's settings.
enum CatalogCommand {

  /// How long a request for the manifest or the catalog may take.
  private static let requestTimeout: TimeInterval = 30

  /// Prints the bundled and cached copies' versions, and which copy is in use.
  static func status() {

    let bundled: DeviceCatalogVersion? = CatalogStore.bundledVersion()
    let cached: DeviceCatalogVersion? = CatalogStore.cachedVersion()
    let hasCachedFile: Bool = CatalogStore.hasCachedCopy()
    let inUse: CatalogSource? = CatalogStore.load()?.source

    for line in CatalogText.status(bundled: bundled, cached: cached, hasCachedFile: hasCachedFile, inUse: inUse) {

      Output.line(line)

    }

  }

  /// Downloads the published catalog when it's compatible with the bundled copy, differs
  /// from the copy in use, and is at least as new as that copy and the bundled copy, and
  /// saves it. `CatalogUpdate.check` decides; this asks the site and saves.
  ///
  /// Only the catalog's site is asked, over HTTPS, with a session that keeps no cookies or
  /// credentials, so nothing about the Hub is ever sent. A redirect is followed only to HTTPS
  /// on the same host and port.
  ///
  /// - Throws: `CommandFailure` if the catalog can't be downloaded, checked or saved.
  static func update() async throws {

    let location: URL = ProductCatalog.updateLocation
    let outcome: CatalogUpdateOutcome = try await CatalogUpdate.check(
      CatalogFiles(),
      isReadable: { (json: Data) -> Bool in (try? ProductCatalog(json: json)) != nil },
      location: location,
      willAsk: Output.note,
      download: { (current: Data?, currentVersion: DeviceCatalogVersion?) async throws -> ProductCatalogUpdate in

        try await ProductCatalog.update(replacing: current, currentVersion: currentVersion, from: location, requestTimeout: requestTimeout)

      },
      message: Names.message(for:)
    )

    switch outcome {
    case let .keep(line):
      Output.line(line)
    case let .save(json, version):
      try CatalogStore.save(json: json, version: version)
      Output.line(CatalogText.updated(to: version))
    }

  }

}
