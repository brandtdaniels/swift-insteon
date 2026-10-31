import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonDeviceCatalog
import InsteonNetworking

/// A copy of the Insteon device catalog, which names products and describes what they do.
///
/// A front end loads the copy the package ships with, or a newer one it downloaded with
/// ``update(replacing:from:requestTimeout:resourceTimeout:)`` and saved, and hands it to
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
  /// - Parameter json: The catalog's JSON.
  /// - Throws: `DecodingError` if it isn't a catalog.
  public init(json: Data) throws {

    self.catalog = try DeviceCatalog(json: json)

  }

  /// Loads a catalog from a file, such as the one ``bundledCatalogURL()`` finds.
  ///
  /// - Parameter url: The file's URL.
  /// - Returns: The catalog.
  /// - Throws: The error reading the file, or `DecodingError` if it isn't a catalog.
  public static func load(contentsOf url: URL) throws -> ProductCatalog {

    try ProductCatalog(DeviceCatalog.load(contentsOf: url))

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

  /// The product a device's identity names, such as "Dimmer Switch 2477D (SwitchLinc Dimmer)".
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

  /// Downloads the published catalog when it's in the format the package reads and differs
  /// from a copy.
  ///
  /// Only an HTTPS address is asked, and only the catalog's site, with a session that keeps no cookies, credentials or
  /// cache, so nothing about a Hub is ever sent. A redirect is followed only to HTTPS on the
  /// same host and port. The published catalog is checked against its manifest's SHA-256.
  ///
  /// - Parameters:
  ///   - current: The JSON of the copy in use, or `nil` for the copy the package ships with.
  ///   - location: Where the catalog is published. Defaults to ``updateLocation``.
  ///   - requestTimeout: How long each request may take, in seconds. Defaults to 30.
  ///   - resourceTimeout: How long the whole download may take, in seconds. Defaults to 120.
  /// - Returns: Whether the published catalog differs, and if it does, its JSON and version.
  /// - Throws: ``ProductCatalogUpdateError`` if the published catalog isn't used,
  ///   `CancellationError`, or the network's error, which ``InsteonErrorDescription``
  ///   describes.
  public static func update(
    replacing current: Data?,
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
    let client: URLSessionHTTPClient = URLSessionHTTPClient(session: session, redirectPolicy: DeviceCatalogUpdater.redirectPolicy)
    let updater: DeviceCatalogUpdater = DeviceCatalogUpdater(client: client, location: location)
    let result: DeviceCatalogUpdate

    do {

      result = try await updater.update(replacing: current)

    } catch let error as CancellationError {

      throw error

    } catch let error as DeviceCatalogUpdateError {

      switch error {
      case let .incompatibleVersion(published):
        throw ProductCatalogUpdateError.incompatibleVersion(published)
      case let .unexpectedStatus(status):
        throw ProductCatalogUpdateError.unexpectedStatus(status)
      case .malformedManifest:
        throw ProductCatalogUpdateError.malformedManifest
      case .checksumMismatch:
        throw ProductCatalogUpdateError.checksumMismatch
      }

    } catch HTTPClientError.insecureRedirect {

      throw ProductCatalogUpdateError.insecureRedirect

    } catch HTTPClientError.redirectRefused {

      throw ProductCatalogUpdateError.redirectRefused

    } catch is DecodingError {

      throw ProductCatalogUpdateError.unreadableCatalog

    }

    switch result {
    case .unchanged:
      return .unchanged
    case let .updated(json, _, version):
      return .updated(json: json, version: version)
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

}
