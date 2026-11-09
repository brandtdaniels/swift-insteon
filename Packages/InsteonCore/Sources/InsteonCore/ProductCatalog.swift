import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonDeviceCatalog
import InsteonNetworking

/// A copy of the Insteon device catalog, which names products and describes what they do.
///
/// A front end loads the copy the package ships with, or a newer one it downloaded with
/// ``update(replacing:currentVersion:from:requestTimeout:resourceTimeout:)`` and saved, and hands it to
/// ``ModemSession/network(catalog:snapshot:hub:)``:
///
/// ```swift
/// let catalog = try ProductCatalog.load(contentsOf: ProductCatalog.bundledCatalogURL())
///
/// print(catalog.productName(category: 0x01, subcategory: 0x20, firmwareVersion: nil) ?? "unknown")
/// ```
public struct ProductCatalog: Sendable {

  /// The catalog.
  let catalog: DeviceCatalog

  init(_ catalog: DeviceCatalog) {

    self.catalog = catalog

  }

  /// Reads a catalog from its JSON, such as a copy a front end saved.
  ///
  /// A catalog that would let an app send or write more to a device the copy the package ships
  /// with knows, as `DeviceCatalog.guardWeakenings(comparedTo:)` finds it, is refused, so the
  /// front end keeps the bundled copy. Without a readable bundled copy there's nothing to
  /// compare with, so the catalog is refused too.
  ///
  /// - Parameter json: The catalog's JSON.
  /// - Throws: `DecodingError` if it isn't a catalog,
  ///   ``ProductCatalogError/weakensGuards(_:)`` if it weakens a guard, or
  ///   ``ProductCatalogError/bundledCopyMissing`` or
  ///   ``ProductCatalogError/bundledCopyUnreadable`` if there's no bundled copy to compare with.
  public init(json: Data) throws {

    self.catalog = try Self.checked(DeviceCatalog(json: json))

  }

  /// Loads a catalog from a file, such as the one ``bundledCatalogURL()`` finds.
  ///
  /// The bundled copy's own file is the bundled copy, read once and not compared with itself.
  /// Any other file is refused as ``init(json:)`` refuses it.
  ///
  /// - Parameter url: The file's URL.
  /// - Returns: The catalog.
  /// - Throws: The error reading the file, `DecodingError` if it isn't a catalog, or an error
  ///   ``init(json:)`` throws.
  public static func load(contentsOf url: URL) throws -> ProductCatalog {

    if let bundledURL = try? DeviceCatalog.bundledCatalogURL(), bundledURL.standardizedFileURL == url.standardizedFileURL {

      return ProductCatalog(try baseline())

    }

    return try ProductCatalog(checked(DeviceCatalog.load(contentsOf: url)))

  }

  /// The bundled copy, to compare another catalog's guards with.
  ///
  /// - Throws: ``ProductCatalogError/bundledCopyMissing`` or
  ///   ``ProductCatalogError/bundledCopyUnreadable``.
  static func baseline() throws -> DeviceCatalog {

    do {

      return try DeviceCatalog.bundled()

    } catch DeviceCatalogError.missingBundledCatalog {

      throw ProductCatalogError.bundledCopyMissing

    } catch {

      throw ProductCatalogError.bundledCopyUnreadable

    }

  }

  /// A catalog, once it's shown to give every device the bundled copy knows guards at least
  /// as strict as the bundled copy's.
  ///
  /// - Parameters:
  ///   - catalog: The catalog.
  ///   - baseline: The catalog to compare with, or `nil` for the bundled copy.
  /// - Returns: The catalog.
  /// - Throws: ``ProductCatalogError/weakensGuards(_:)`` if it weakens a guard, or an error
  ///   ``baseline()`` throws.
  static func checked(_ catalog: DeviceCatalog, against baseline: DeviceCatalog? = nil) throws -> DeviceCatalog {

    let baseline: DeviceCatalog = try baseline ?? Self.baseline()
    let weakenings: [GuardWeakening] = catalog.guardWeakenings(comparedTo: baseline)

    guard weakenings.isEmpty else {

      throw ProductCatalogError.weakensGuards(weakenings)

    }

    return catalog

  }

  /// The file of the copy of the catalog the package ships with.
  ///
  /// - Returns: The file's URL.
  /// - Throws: An error if the copy isn't found, as when only an executable was copied.
  public static func bundledCatalogURL() throws -> URL {

    try DeviceCatalog.bundledCatalogURL()

  }

  /// The version of the copy the package ships with. The package reads catalogs with the same
  /// MAJOR.MINOR.
  ///
  /// - Returns: The version.
  /// - Throws: An error if the copy's manifest isn't found or can't be read.
  public static func bundledVersion() throws -> DeviceCatalogVersion {

    try DeviceCatalog.bundledVersion()

  }

  /// The name of the bundle the shipped copy is in, such as to say what's missing.
  public static var bundleName: String {

    DeviceCatalog.bundleNames[0]

  }

  /// The product a device's identity names, such as "Example Dimmer 9101 (DemoLinc Dimmer)".
  ///
  /// - Parameters:
  ///   - category: The device's category.
  ///   - subcategory: The device's subcategory.
  ///   - firmwareVersion: The device's firmware version, if it reported one.
  /// - Returns: The product's name and model, or `nil` if the catalog doesn't have it.
  public func productName(category: DeviceCategory, subcategory: DeviceSubcategory, firmwareVersion: FirmwareVersion?) -> String? {

    catalog.profile(category: category, subcategory: subcategory, firmwareVersion: firmwareVersion)?.displayName

  }

  // MARK: - Updating

  /// Where the Insteon device catalog publishes the versions this package reads, over HTTPS.
  public static let updateLocation: URL = DeviceCatalogUpdater.defaultLocation

  /// Downloads the published catalog when it's in the format the package reads, differs from
  /// a copy, and is at least as new as that copy and the copy the package ships with.
  ///
  /// Only an HTTPS address is asked, and only the catalog's site, with a session that keeps no cookies, credentials or
  /// cache, so nothing about a Hub is ever sent. A redirect is followed only to HTTPS on the
  /// same host and port. The published catalog is checked against its manifest's SHA-256, and
  /// a file larger than 16 MiB isn't read. A published version older than the copy in use, or
  /// than the bundled copy, is refused before it's downloaded, so a stale cache or a
  /// rolled-back site never takes back newer data.
  ///
  /// - Parameters:
  ///   - current: The JSON of the copy in use, or `nil` for the copy the package ships with.
  ///   - currentVersion: The version of the copy in use, as saved beside it, or `nil` for the
  ///     copy the package ships with.
  ///   - location: Where the catalog is published. Defaults to ``updateLocation``.
  ///   - requestTimeout: How long each request may take, in seconds. Defaults to 30.
  ///   - resourceTimeout: How long the whole download may take, in seconds. Defaults to 120.
  /// - Returns: Whether the published catalog differs, and if it does, its JSON and version.
  /// - Throws: ``ProductCatalogUpdateError`` if the published catalog isn't used,
  ///   `CancellationError`, or the network's error, which ``InsteonErrorDescription``
  ///   describes.
  public static func update(
    replacing current: Data?,
    currentVersion: DeviceCatalogVersion?,
    from location: URL = ProductCatalog.updateLocation,
    requestTimeout: TimeInterval = 30,
    resourceTimeout: TimeInterval = 120
  ) async throws -> ProductCatalogUpdate {

    // Only HTTPS is asked, so the catalog can't be read or changed on its way.
    guard location.scheme?.lowercased() == "https" else {

      throw ProductCatalogUpdateError.insecureLocation

    }

    // An ephemeral session keeps no cookies, credentials or cache between requests.
    let configuration: URLSessionConfiguration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = requestTimeout
    // A limit on the whole download too, so a slow server can't hold the caller for long.
    configuration.timeoutIntervalForResource = resourceTimeout
    let session: URLSession = URLSession(configuration: configuration)

    defer {

      session.finishTasksAndInvalidate()

    }

    // Redirects are followed only to HTTPS on the catalog's own host, decided before each one.
    let client: URLSessionHTTPClient = URLSessionHTTPClient(
      session: session,
      redirectPolicy: DeviceCatalogUpdater.redirectPolicy,
      maximumResponseSize: DeviceCatalogUpdater.maximumResponseSize
    )
    let updater: DeviceCatalogUpdater = DeviceCatalogUpdater(client: client, location: location)
    let result: DeviceCatalogUpdate

    do {

      result = try await updater.update(replacing: current, currentVersion: currentVersion)

    } catch {

      throw updateError(for: error)

    }

    switch result {
    case .unchanged:
      return .unchanged
    case let .updated(json, _, version):
      return .updated(json: json, version: version)
    }

  }

  /// The error ``update(replacing:currentVersion:from:requestTimeout:resourceTimeout:)``
  /// throws for one from the updater: the ``ProductCatalogUpdateError`` that means the same,
  /// or else the error itself, such as `CancellationError` or the network's error.
  static func updateError(for error: any Error) -> any Error {

    if let error = error as? DeviceCatalogUpdateError {

      switch error {
      case let .incompatibleVersion(published):
        return ProductCatalogUpdateError.incompatibleVersion(published)
      case let .olderThanCurrent(published):
        return ProductCatalogUpdateError.olderThanCurrent(published)
      case let .unexpectedStatus(status):
        return ProductCatalogUpdateError.unexpectedStatus(status)
      case .malformedManifest:
        return ProductCatalogUpdateError.malformedManifest
      case .checksumMismatch:
        return ProductCatalogUpdateError.checksumMismatch
      case let .weakensGuards(weakenings):
        return ProductCatalogUpdateError.weakensGuards(weakenings)
      }

    }

    if let error = error as? DeviceCatalogError {

      switch error {
      case .missingBundledCatalog:
        return ProductCatalogError.bundledCopyMissing
      case .unreadableBundledCatalog:
        return ProductCatalogError.bundledCopyUnreadable
      case let .weakensGuards(weakenings):
        return ProductCatalogUpdateError.weakensGuards(weakenings)
      }

    }

    if let error = error as? HTTPClientError {

      switch error {
      case .insecureRedirect:
        return ProductCatalogUpdateError.insecureRedirect
      case .redirectRefused:
        return ProductCatalogUpdateError.redirectRefused
      case .nonHTTPResponse, .responseTooLarge, .proxyConfigured, .credentialsRefused:
        return error
      }

    }

    if error is DecodingError {

      return ProductCatalogUpdateError.unreadableCatalog

    }

    return error

  }

}

/// Why a catalog a front end saved or supplied isn't used.
public enum ProductCatalogError: Error, Hashable, Sendable {

  /// The catalog would let an app send or write more to a device the copy the package ships
  /// with knows, so the bundled copy stays in use. The associated value is each weakened
  /// guard.
  case weakensGuards([GuardWeakening])

  /// The copy of the catalog the package ships with isn't found, so no other catalog's guards
  /// can be compared with it, and none is used.
  case bundledCopyMissing

  /// The copy of the catalog the package ships with is found but can't be read, so no other
  /// catalog's guards can be compared with it, and none is used.
  case bundledCopyUnreadable

}

extension ProductCatalogError: LocalizedError {

  /// The error as a sentence.
  public var errorDescription: String? {

    switch self {
    case let .weakensGuards(weakenings):
      let guards: String = weakenings.map(\.description).joined(separator: ", ")
      return "The Insteon device catalog would let more be sent or written to a device than the bundled copy does (\(guards)), so it isn't used."
    case .bundledCopyMissing:
      return "The Insteon device catalog the package ships with isn't found, so no other copy can be checked against it, and none is used."
    case .bundledCopyUnreadable:
      return "The Insteon device catalog the package ships with couldn't be read, so no other copy can be checked against it, and none is used."
    }

  }

}

/// What came of asking for the published Insteon device catalog.
public enum ProductCatalogUpdate: Hashable, Sendable {

  /// The published catalog is the copy in use.
  case unchanged

  /// The published catalog differs: its JSON, to save, and its version.
  case updated(json: Data, version: DeviceCatalogVersion)

}

/// Why the published Insteon device catalog wasn't used.
public enum ProductCatalogUpdateError: Error, Hashable, Sendable {

  /// The published catalog is in a format the package doesn't read: a different MAJOR.MINOR
  /// than the shipped copy's. This isn't a failure; the copy in use stays.
  case incompatibleVersion(DeviceCatalogVersion)

  /// The published catalog is older than the copy in use or the shipped copy, with its
  /// version, so it isn't downloaded. This isn't a failure; the copy in use stays.
  case olderThanCurrent(DeviceCatalogVersion)

  /// The catalog's site answered with an HTTP status other than 200.
  case unexpectedStatus(Int)

  /// The published manifest couldn't be read.
  case malformedManifest

  /// The downloaded catalog didn't match its manifest's SHA-256.
  case checksumMismatch

  /// The catalog's address isn't HTTPS, so it isn't asked.
  case insecureLocation

  /// The catalog's site redirected to an address that isn't HTTPS.
  case insecureRedirect

  /// The catalog's site redirected to another host or port.
  case redirectRefused

  /// The published catalog matched its SHA-256 but couldn't be read as a catalog.
  case unreadableCatalog

  /// The published catalog would let an app send or write more to a device the copy the
  /// package ships with knows than that copy does, so it isn't used. The associated value is
  /// each weakened guard.
  case weakensGuards([GuardWeakening])

}
