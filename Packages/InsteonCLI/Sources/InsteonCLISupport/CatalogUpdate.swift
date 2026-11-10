import Foundation
import InsteonCore

/// The `insteon` command's two copies of the Insteon device catalog, as they are on disk: the
/// one bundled next to the command, and the one `insteon catalog update` keeps in the cache
/// directory.
public protocol CatalogCopies {

  /// The bundled copy's version, or `nil` if the bundle or its manifest isn't there.
  func bundledVersion() -> DeviceCatalogVersion?

  /// The cached copy's file, or `nil` if there's no cache directory, as when neither
  /// `XDG_CACHE_HOME` nor `HOME` is set.
  var catalogPath: String? { get }

  /// The file of the cached copy's version, or `nil` if there's no cache directory.
  var versionPath: String? { get }

  /// Whether there's a cached copy, readable or not.
  var hasCachedCopy: Bool { get }

  /// The cached copy's version, or `nil` if there's no cached copy or its version can't be
  /// read.
  func cachedVersion() -> DeviceCatalogVersion?

  /// The cached copy's JSON, or `nil` if there's none or it can't be read.
  func cachedJSON() -> Data?

}

extension CatalogCopies {

  /// Whether there's a cache directory to keep a copy in: both files have a path.
  public var hasCacheDirectory: Bool { catalogPath != nil && versionPath != nil }

}

/// What `insteon catalog update` does once it has asked the catalog's site.
public enum CatalogUpdateOutcome: Hashable, Sendable {

  /// Save the published copy, its JSON and version, in the cache directory, then say so
  /// with ``CatalogText/updated(to:)``.
  case save(json: Data, version: DeviceCatalogVersion)

  /// Keep the copy in use, and print the line, which says why.
  case keep(String)

}

/// What `insteon catalog update` decides: which copy is current, whether the site may be
/// asked, and what to do with the published copy.
public enum CatalogUpdate {

  /// Compares the published catalog with the copy in use.
  ///
  /// The copy in use is the cached one when ``CatalogCache/source(bundled:cached:)`` chooses
  /// it and it reads as a catalog; a cached copy that fails, such as one that weakens the
  /// bundled copy's guards, isn't in use, so the published copy replaces it. Otherwise it's
  /// the bundled copy. Only an HTTPS address is asked. A published copy in another format,
  /// or older than the copy in use, is kept out, and that isn't a failure.
  ///
  /// - Parameters:
  ///   - copies: The copies on disk.
  ///   - isReadable: Whether a cached copy's JSON reads as a catalog, as
  ///     `ProductCatalog.init(json:)` checks it.
  ///   - location: Where the catalog is published.
  ///   - willAsk: Called with a note just before the site is asked.
  ///   - download: Asks the site, with the JSON and version of the copy in use, or `nil` for
  ///     both when it's the bundled copy, as `ProductCatalog.update(replacing:currentVersion:from:requestTimeout:resourceTimeout:)`
  ///     does.
  ///   - message: Describes an error the download threw, on one line or several.
  /// - Returns: What to do.
  /// - Throws: `CommandFailure` when there's no bundled copy, no cache directory or no HTTPS
  ///   address, or the published copy can't be downloaded or used; `CancellationError` if the
  ///   download was canceled.
  public static func check(
    _ copies: some CatalogCopies,
    isReadable: (Data) -> Bool,
    location: URL,
    willAsk: (String) -> Void,
    download: (_ current: Data?, _ currentVersion: DeviceCatalogVersion?) async throws -> ProductCatalogUpdate,
    message: (any Error) -> String
  ) async throws -> CatalogUpdateOutcome {

    guard let bundled = copies.bundledVersion() else {

      throw CommandFailure(
        description: "The Insteon device catalog (\(ProductCatalog.bundleName)) isn't next to the command, "
          + "so there's no version to update from. Scripts/install-insteon.sh installs the command with it."
      )

    }

    guard copies.hasCacheDirectory else {

      throw CommandFailure(description: CatalogText.noCacheDirectory)

    }

    // The cached copy is compared with the published one only when it's the copy in use.
    var current: Data? = nil
    var cachedVersion: DeviceCatalogVersion? = nil
    var currentVersion: DeviceCatalogVersion = bundled

    if let cached = copies.cachedVersion(),
      CatalogCache.source(bundled: bundled, cached: cached) == .cached,
      let json = copies.cachedJSON(),
      isReadable(json)
    {

      current = json
      cachedVersion = cached
      currentVersion = cached

    }

    guard location.scheme?.lowercased() == "https" else {

      throw CommandFailure(description: "The Insteon device catalog's address, \(location.absoluteString), isn't HTTPS, so it isn't asked.")

    }

    willAsk("Checking \(location.absoluteString) for a newer Insteon device catalog...")

    let result: ProductCatalogUpdate

    do {

      result = try await download(current, cachedVersion)

    } catch let error as CancellationError {

      throw error

    } catch let error as ProductCatalogUpdateError {

      return try outcome(of: error, bundled: bundled, current: currentVersion)

    } catch {

      throw CommandFailure(
        description: "The Insteon device catalog couldn't be downloaded from \(location.absoluteString): \(oneLine(message(error)))"
      )

    }

    switch result {
    case .unchanged:
      return .keep(CatalogText.upToDate(currentVersion))
    case let .updated(json, version):
      return .save(json: json, version: version)
    }

  }

  /// Why the published catalog wasn't used: a line to print, for a catalog in another format
  /// or an older one, which isn't a failure, or a `CommandFailure`.
  private static func outcome(of error: ProductCatalogUpdateError, bundled: DeviceCatalogVersion, current: DeviceCatalogVersion) throws -> CatalogUpdateOutcome {

    switch error {
    case let .incompatibleVersion(published):
      return .keep(CatalogText.incompatible(published: published, bundled: bundled, current: current))
    case let .olderThanCurrent(published):
      return .keep(CatalogText.publishedIsOlder(published: published, current: current))
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
    case .insecureLocation:
      throw CommandFailure(description: "The Insteon device catalog's address isn't HTTPS, so it isn't asked, and the current copy, \(current), stays.")
    case .insecureRedirect:
      throw CommandFailure(description: "The Insteon device catalog's site redirected to an address that isn't HTTPS, so nothing was used and the current copy, \(current), stays.")
    case .redirectRefused:
      throw CommandFailure(
        description: "The Insteon device catalog's site redirected to another host or port, so the redirect wasn't followed, nothing was used, and the current copy, \(current), stays."
      )
    case .unreadableCatalog:
      throw CommandFailure(description: "The published Insteon device catalog couldn't be read, so the current copy, \(current), stays.")
    case let .weakensGuards(weakenings):
      throw CommandFailure(description: CatalogText.publishedWeakensGuards(weakenings, current: current))
    }

  }

  /// A message on one line, for an error whose description may span several.
  private static func oneLine(_ text: String) -> String {

    text.split(whereSeparator: { (character: Character) -> Bool in character.isNewline }).joined(separator: " ")

  }

}
