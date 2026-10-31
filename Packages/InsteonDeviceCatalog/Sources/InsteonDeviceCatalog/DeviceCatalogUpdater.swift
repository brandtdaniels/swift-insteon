import Crypto
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonNetworking

/// The result of checking for a newer copy of the device catalog.
public enum DeviceCatalogUpdate: Hashable, Sendable {

  /// The published catalog is the copy the app already has.
  case unchanged

  /// A different catalog is published: its JSON, to save in place of the app's copy, the
  /// catalog read from it, and its version, to save beside it.
  ///
  /// The version has the same MAJOR.MINOR as ``DeviceCatalog/bundledVersion()``. An app that
  /// saves it can tell, after updating this package, whether its saved copy is still in a
  /// format the package reads, and fall back on the bundled copy if it isn't.
  case updated(json: Data, catalog: DeviceCatalog, version: DeviceCatalogVersion)

}

/// Errors downloading a newer copy of the device catalog.
public enum DeviceCatalogUpdateError: Error, Hashable, Sendable {

  /// The server answered a request for the manifest or the catalog with a status other than
  /// 2xx, with that status.
  case unexpectedStatus(Int)

  /// The manifest isn't the JSON the Insteon device catalog publishes, gives a version not
  /// written `MAJOR.MINOR.PATCH`, or names its catalog by anything but a plain file name.
  case malformedManifest

  /// The published catalog is a version whose MAJOR.MINOR differs from
  /// ``DeviceCatalog/bundledVersion()``'s, with that version. Its format may have changed in
  /// ways this package doesn't read, so the app should keep its copy until it updates the
  /// package.
  case incompatibleVersion(DeviceCatalogVersion)

  /// The downloaded catalog's SHA-256 doesn't match the manifest's.
  case checksumMismatch

  /// The published catalog is a version older than the app's copy, or than
  /// ``DeviceCatalog/bundledVersion()``, with that version, so it isn't downloaded: a stale
  /// cache or a rolled-back site can't take back data a newer copy has.
  case olderThanCurrent(DeviceCatalogVersion)

}

/// Downloads the published device catalog when it differs from the app's copy.
///
/// The catalog publishes a manifest with the catalog's version and SHA-256. The updater
/// fetches the manifest and goes on only if the version has the same MAJOR.MINOR as the copy
/// the package ships with, ``DeviceCatalog/bundledVersion()``, since below 1.0 the catalog's
/// format can change in any MINOR. It then compares the manifest's SHA-256 with the app's
/// copy, and downloads the catalog only when they differ and the published version is at
/// least as new as the app's copy and the bundled copy, so a stale cache or a rolled-back site
/// never replaces newer data with older. A downloaded catalog is used only if
/// its bytes hash to the manifest's SHA-256 and it reads as a catalog, so a download cut
/// short, or a catalog from a different version than the manifest, is never used. The hash
/// shows that the two files agree; HTTPS is what shows they came from the catalog's host.
///
/// ```swift
/// let saved: Data? = try? Data(contentsOf: savedURL)
/// let savedVersion: DeviceCatalogVersion? = try? JSONDecoder().decode(
///   DeviceCatalogVersion.self,
///   from: Data(contentsOf: savedVersionURL)
/// )
///
/// switch try await DeviceCatalogUpdater().update(replacing: saved, currentVersion: savedVersion) {
/// case .unchanged:
///   break
/// case let .updated(json, catalog, version):
///   try json.write(to: savedURL, options: .atomic)
///   try JSONEncoder().encode(version).write(to: savedVersionURL, options: .atomic)
///   use(catalog)
/// }
/// ```
///
/// ## Redirects
///
/// The catalog isn't signed. Its integrity rests on HTTPS to the expected host, plus the
/// manifest's SHA-256, which only shows that the catalog matches a manifest fetched from the
/// same host. So the default client follows a redirect only to HTTPS at the same host
/// and port as the request, using ``DeviceCatalogUpdater/redirectPolicy``, and decides before
/// following it. A redirect that leaves HTTPS, even for one step, or goes to another host
/// fails the update with `HTTPClientError.insecureRedirect` or
/// `HTTPClientError.redirectRefused`, and nothing is downloaded from the address it named.
/// A redirect on the catalog's own host, such as one that adds a trailing slash, is followed.
/// A client passed in place of the default should refuse redirects the same way.
///
/// Updating is optional: the package ships a copy, so an app works without ever updating.
/// Hashes are worked out with swift-crypto, which uses CryptoKit on Apple platforms.
public struct DeviceCatalogUpdater: Sendable {

  /// Which redirects the default client follows: only those to HTTPS at the same host and
  /// port as the request.
  ///
  /// A client created for an updater, such as one with its own session, should use it too.
  public static let redirectPolicy: RedirectPolicy = .sameOriginHTTPSOnly

  /// Where the Insteon device catalog publishes the MAJOR version this package reads, `v0`.
  public static let defaultLocation = URL(string: "https://brandtdaniels.github.io/insteon-device-catalog/v0/")!

  /// The client requests are sent through.
  public let client: any HTTPClient

  /// The directory the manifest and catalog are published in.
  public let location: URL

  /// The largest file the updater reads: 16 MiB, several times the catalog's size.
  public static let maximumResponseSize: Int = 16 * 1_024 * 1_024

  /// Creates an updater.
  ///
  /// - Parameters:
  ///   - client: The client to send requests through. Defaults to a `URLSessionHTTPClient` with
  ///     ``DeviceCatalogUpdater/redirectPolicy`` that reads at most
  ///     ``DeviceCatalogUpdater/maximumResponseSize`` bytes.
  ///   - location: The directory the manifest and catalog are published in. Defaults to
  ///     ``DeviceCatalogUpdater/defaultLocation``.
  public init(
    client: any HTTPClient = URLSessionHTTPClient(
      redirectPolicy: DeviceCatalogUpdater.redirectPolicy,
      maximumResponseSize: DeviceCatalogUpdater.maximumResponseSize
    ),
    location: URL = DeviceCatalogUpdater.defaultLocation
  ) {

    self.client = client
    self.location = location

  }

  /// Downloads the published catalog if it differs from the app's copy and is at least as new
  /// as both the app's copy and the copy the package ships with.
  ///
  /// - Parameters:
  ///   - current: The JSON of the app's copy, such as one saved from an earlier update, or
  ///     `nil` for the copy the package ships with.
  ///   - currentVersion: The version saved beside the app's copy, or `nil` for the copy the
  ///     package ships with, or a copy saved without its version. A version in another format
  ///     than ``DeviceCatalog/bundledVersion()``'s isn't compared. The bundled copy's version is
  ///     always compared.
  /// - Returns: ``DeviceCatalogUpdate/unchanged``, or the new catalog, its JSON and its version.
  /// - Throws: ``DeviceCatalogUpdateError/incompatibleVersion(_:)`` if the published catalog
  ///   is in another format, so the app should keep its copy;
  ///   ``DeviceCatalogUpdateError/olderThanCurrent(_:)`` if it's older than the app's copy or
  ///   the bundled copy, before it's downloaded; another ``DeviceCatalogUpdateError`` if a
  ///   download fails its checks; `HTTPClientError.responseTooLarge(limit:)` for a file larger
  ///   than ``DeviceCatalogUpdater/maximumResponseSize``; `DecodingError` if a catalog that
  ///   matches its SHA-256 doesn't read as a catalog; `DeviceCatalogError.missingBundledCatalog`
  ///   if the shipped copy or its manifest is missing; or the client's error if a request gets
  ///   no response or is redirected somewhere its policy refuses, such as
  ///   `HTTPClientError.redirectRefused`.
  public func update(replacing current: Data?, currentVersion: DeviceCatalogVersion?) async throws -> DeviceCatalogUpdate {

    let manifest = try await manifest()
    let bundledVersion = try DeviceCatalog.bundledVersion()

    guard manifest.version.isCompatible(with: bundledVersion) else {

      throw DeviceCatalogUpdateError.incompatibleVersion(manifest.version)

    }

    let currentDigest = try current.map(Self.sha256(of:)) ?? Self.bundledDigest.get()

    if currentDigest == manifest.sha256 {

      return .unchanged

    }

    // A published version older than the copy in use, or than the bundled copy, would take
    // back data, such as a guard, that the newer copy has.
    let newest: DeviceCatalogVersion = [bundledVersion, currentVersion]
      .compactMap { (version: DeviceCatalogVersion?) -> DeviceCatalogVersion? in version }
      .filter { (version: DeviceCatalogVersion) -> Bool in version.isCompatible(with: bundledVersion) }
      .max() ?? bundledVersion

    guard manifest.version >= newest else {

      throw DeviceCatalogUpdateError.olderThanCurrent(manifest.version)

    }

    // Naming the expected SHA-256 in the request keeps a cache from answering with a copy of
    // the catalog saved before this version was published.
    let json = try await download(manifest.catalog, query: [URLQueryItem(name: "sha256", value: manifest.sha256)])

    guard Self.sha256(of: json) == manifest.sha256 else {

      throw DeviceCatalogUpdateError.checksumMismatch

    }

    return .updated(json: json, catalog: try DeviceCatalog(json: json), version: manifest.version)

  }

  /// Fetches and checks the manifest.
  private func manifest() async throws -> CatalogManifest {

    let json = try await download("manifest.json")

    guard let manifest = try? JSONDecoder().decode(CatalogManifest.self, from: json) else {

      throw DeviceCatalogUpdateError.malformedManifest

    }

    // The catalog must be a file beside the manifest, not a path or URL elsewhere.
    let isFileName = !manifest.catalog.isEmpty && !manifest.catalog.hasPrefix(".")
      && manifest.catalog.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
    let isDigest = manifest.sha256.count == 64 && manifest.sha256.allSatisfy { $0.isASCII && $0.isHexDigit && !$0.isUppercase }

    guard isFileName, isDigest else {

      throw DeviceCatalogUpdateError.malformedManifest

    }

    return manifest

  }

  /// Downloads a file from the location, bypassing the device's own cache.
  private func download(_ name: String, query: [URLQueryItem] = []) async throws -> Data {

    var url = location.appending(path: name)

    if !query.isEmpty {

      url.append(queryItems: query)

    }

    let response = try await client.send(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))

    // Whatever the client, a file larger than the catalog could be isn't read.
    guard response.body.count <= Self.maximumResponseSize else {

      throw HTTPClientError.responseTooLarge(limit: Self.maximumResponseSize)

    }

    guard response.isSuccess else {

      throw DeviceCatalogUpdateError.unexpectedStatus(response.statusCode)

    }

    return response.body

  }

  /// The SHA-256 of the copy the package ships with, worked out once.
  private static let bundledDigest = Result<String, any Error> {

    sha256(of: try DeviceCatalog.bundledJSON())

  }

  /// The SHA-256 of some bytes, as lowercase hexadecimal.
  private static func sha256(of data: Data) -> String {

    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

  }

}
