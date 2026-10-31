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

  /// Whether there's a cached copy of the catalog, readable or not.
  static func hasCachedCopy() -> Bool {

    guard let path = catalogPath() else {

      return false

    }

    return PrivateFiles.exists(path)

  }

  /// The cached copy's version, or `nil` if there's no cached copy or its version can't be
  /// read.
  static func cachedVersion() -> DeviceCatalogVersion? {

    guard hasCachedCopy(), let path = versionPath(), let data = PrivateFiles.read(path) else {

      return nil

    }

    return CatalogCache.version(json: data)

  }

  /// The cached copy's JSON, or `nil` if there's none or it can't be read.
  static func cachedJSON() -> Data? {

    guard let path = catalogPath() else {

      return nil

    }

    return PrivateFiles.read(path)

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

      if let json = cachedJSON(), let catalog = try? ProductCatalog(json: json) {

        return Loaded(catalog: catalog, source: .cached)

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

    guard let path = catalogPath(), let versionPath = versionPath() else {

      throw noCacheDirectory

    }

    let versionJSON: Data = try CatalogCache.versionJSON(version)

    guard PrivateFiles.replace(path, with: json), PrivateFiles.replace(versionPath, with: versionJSON) else {

      throw CommandFailure(description: "The Insteon device catalog couldn't be saved in \(Paths.directory(of: path)).")

    }

  }

  /// The error when there's no cache directory to keep the catalog in.
  static let noCacheDirectory = CommandFailure(
    description: "Neither XDG_CACHE_HOME nor HOME is set to an absolute path, so there's nowhere to keep the Insteon device catalog."
  )

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

  /// Downloads the published catalog when it's compatible with the bundled copy and differs
  /// from the copy in use, and saves it when it's at least as new as the bundled copy.
  ///
  /// Only the catalog's site is asked, over HTTPS, with a session that keeps no cookies or
  /// credentials, so nothing about the Hub is ever sent. A redirect is followed only to HTTPS
  /// on the same host and port.
  ///
  /// - Throws: `CommandFailure` if the catalog can't be downloaded, checked or saved.
  static func update() async throws {

    let bundled: DeviceCatalogVersion

    do {

      bundled = try ProductCatalog.bundledVersion()

    } catch {

      throw CommandFailure(
        description: "The Insteon device catalog (\(ProductCatalog.bundleName)) isn't next to the command, "
          + "so there's no version to update from. Scripts/install-insteon.sh installs the command with it."
      )

    }

    guard CatalogStore.catalogPath() != nil, CatalogStore.versionPath() != nil else {

      throw CatalogStore.noCacheDirectory

    }

    // The cached copy is compared with the published one only when it's the copy in use.
    var current: Data? = nil
    var currentVersion: DeviceCatalogVersion = bundled

    if let cached = CatalogStore.cachedVersion(),
      CatalogCache.source(bundled: bundled, cached: cached) == .cached,
      let json = CatalogStore.cachedJSON()
    {

      current = json
      currentVersion = cached

    }

    let location: URL = ProductCatalog.updateLocation

    guard location.scheme == "https" else {

      throw CommandFailure(description: "The Insteon device catalog's address, \(location.absoluteString), isn't HTTPS, so it isn't asked.")

    }

    Output.note("Checking \(location.absoluteString) for a newer Insteon device catalog...")

    let result: ProductCatalogUpdate

    do {

      // Only the catalog's site is asked, with a session that keeps no cookies or
      // credentials, and redirects only to HTTPS on its own host.
      result = try await ProductCatalog.update(replacing: current, from: location, requestTimeout: requestTimeout)

    } catch let error as CancellationError {

      throw error

    } catch let error as ProductCatalogUpdateError {

      try report(error, bundled: bundled, current: currentVersion)

      return

    } catch {

      throw CommandFailure(
        description: "The Insteon device catalog couldn't be downloaded from \(location.absoluteString): \(oneLine(Names.message(for: error)))"
      )

    }

    switch result {
    case .unchanged:
      Output.line(CatalogText.upToDate(currentVersion))
    case let .updated(json, version):
      guard CatalogCache.source(bundled: bundled, cached: version) == .cached else {

        Output.line(CatalogText.bundledIsNewer(published: version, bundled: bundled))

        return

      }

      try CatalogStore.save(json: json, version: version)
      Output.line(CatalogText.updated(to: version))
    }

  }

  /// Says why the published catalog wasn't used: in a line, for a catalog in another format,
  /// which isn't a failure, or by throwing.
  ///
  /// - Throws: `CommandFailure` for an error other than an incompatible version.
  private static func report(_ error: ProductCatalogUpdateError, bundled: DeviceCatalogVersion, current: DeviceCatalogVersion) throws {

    switch error {
    case let .incompatibleVersion(published):
      Output.line(CatalogText.incompatible(published: published, bundled: bundled, current: current))
    case let .unexpectedStatus(status):
      throw CommandFailure(
        description: "The Insteon device catalog's site answered with HTTP status \(status), so the current copy, \(current), stays."
      )
    case .malformedManifest:
      throw CommandFailure(description: "The Insteon device catalog's manifest couldn't be read, so the current copy, \(current), stays.")
    case .checksumMismatch:
      throw CommandFailure(
        description: "The downloaded Insteon device catalog didn't match its manifest's SHA-256, so the current copy, \(current), stays. Try again later."
      )
    case .insecureRedirect:
      throw CommandFailure(description: "The Insteon device catalog's site redirected to an address that isn't HTTPS, so nothing was used and the current copy, \(current), stays.")
    case .redirectRefused:
      throw CommandFailure(
        description: "The Insteon device catalog's site redirected to another host or port, so the redirect wasn't followed, nothing was used, and the current copy, \(current), stays."
      )
    case .unreadableCatalog:
      throw CommandFailure(description: "The published Insteon device catalog couldn't be read, so the current copy, \(current), stays.")
    }

  }

  /// A message on one line, for an error whose description may span several.
  private static func oneLine(_ text: String) -> String {

    text.split(whereSeparator: { (character: Character) -> Bool in character.isNewline }).joined(separator: " ")

  }

}
