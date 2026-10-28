#if canImport(CryptoKit)
import CryptoKit
import Foundation
import InsteonNetworking

/// The result of checking for a newer copy of the device database.
public enum DeviceDatabaseUpdate: Hashable, Sendable {

  /// The published database is the copy the app already has.
  case unchanged

  /// A different database is published: its JSON, to save in place of the app's copy, and the
  /// database read from it.
  case updated(json: Data, database: DeviceDatabase)

}

/// Errors downloading a newer copy of the device database.
public enum DeviceDatabaseUpdateError: Error, Hashable, Sendable {

  /// The server answered a request for the manifest or the database with a status other than
  /// 2xx, with that status.
  case unexpectedStatus(Int)

  /// The manifest isn't the JSON the INSTEON device database publishes, or names its
  /// database by anything but a plain file name.
  case malformedManifest

  /// The downloaded database's SHA-256 doesn't match the manifest's.
  case checksumMismatch

}

/// Downloads the published device database when it differs from the app's copy.
///
/// The database publishes a manifest with the database's SHA-256. The updater fetches the
/// manifest, compares its SHA-256 with the app's copy, and downloads the database only when
/// they differ. A downloaded database is used only if its bytes hash to the manifest's SHA-256
/// and it reads as a database in the format this package reads, so a download cut short, or a
/// database from a different version than the manifest, is never used. The hash shows that the
/// two files agree; HTTPS is what shows they came from the database's host.
///
/// ```swift
/// let saved: Data? = try? Data(contentsOf: savedURL)
///
/// switch try await DeviceDatabaseUpdater().update(replacing: saved) {
/// case .unchanged:
///   break
/// case let .updated(json, database):
///   try json.write(to: savedURL, options: .atomic)
///   use(database)
/// }
/// ```
///
/// Updating is optional: the package ships a copy, so an app works without ever updating. The
/// updater checks hashes with CryptoKit, so it's available only where CryptoKit is, on Apple
/// platforms.
public struct DeviceDatabaseUpdater: Sendable {

  /// Where the INSTEON device database publishes the format version this package reads.
  public static let defaultLocation = URL(string: "https://brandtdaniels.github.io/insteon-device-database/v\(DeviceDatabase.schemaVersion)/")!

  /// The client requests are sent through.
  public let client: any HTTPClient

  /// The directory the manifest and database are published in.
  public let location: URL

  /// Creates an updater.
  ///
  /// - Parameters:
  ///   - client: The client to send requests through. Defaults to a `URLSessionHTTPClient`.
  ///   - location: The directory the manifest and database are published in. Defaults to
  ///     ``DeviceDatabaseUpdater/defaultLocation``.
  public init(client: any HTTPClient = URLSessionHTTPClient(), location: URL = DeviceDatabaseUpdater.defaultLocation) {

    self.client = client
    self.location = location

  }

  /// Downloads the published database if it differs from the app's copy.
  ///
  /// - Parameter current: The JSON of the app's copy, such as one saved from an earlier
  ///   update, or `nil` for the copy the package ships with.
  /// - Returns: ``DeviceDatabaseUpdate/unchanged``, or the new database and its JSON.
  /// - Throws: `DeviceDatabaseError.unsupportedSchemaVersion(_:)` if the published database
  ///   is in another format version, so the app should keep its copy;
  ///   ``DeviceDatabaseUpdateError`` if a download fails its checks; `DecodingError` if a
  ///   database that matches its SHA-256 doesn't read as a database;
  ///   `DeviceDatabaseError.missingBundledDatabase` if `current` is `nil` and the shipped copy
  ///   is missing; or the client's error if a request gets no response.
  public func update(replacing current: Data?) async throws -> DeviceDatabaseUpdate {

    let manifest = try await manifest()

    guard manifest.schemaVersion == DeviceDatabase.schemaVersion else {

      throw DeviceDatabaseError.unsupportedSchemaVersion(manifest.schemaVersion)

    }

    let currentDigest = try current.map(Self.sha256(of:)) ?? Self.bundledDigest.get()

    if currentDigest == manifest.sha256 {

      return .unchanged

    }

    // Naming the expected SHA-256 in the request keeps a cache from answering with a copy of
    // the database saved before this version was published.
    let json = try await download(manifest.database, query: [URLQueryItem(name: "sha256", value: manifest.sha256)])

    guard Self.sha256(of: json) == manifest.sha256 else {

      throw DeviceDatabaseUpdateError.checksumMismatch

    }

    return .updated(json: json, database: try DeviceDatabase(json: json))

  }

  /// The manifest's fields this package reads.
  private struct Manifest: Decodable {

    let schemaVersion: Int

    let database: String

    let sha256: String

  }

  /// Fetches and checks the manifest.
  private func manifest() async throws -> Manifest {

    let json = try await download("manifest.json")

    guard let manifest = try? JSONDecoder().decode(Manifest.self, from: json) else {

      throw DeviceDatabaseUpdateError.malformedManifest

    }

    // The database must be a file beside the manifest, not a path or URL elsewhere.
    let isFileName = !manifest.database.isEmpty && !manifest.database.hasPrefix(".")
      && manifest.database.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
    let isDigest = manifest.sha256.count == 64 && manifest.sha256.allSatisfy { $0.isASCII && $0.isHexDigit && !$0.isUppercase }

    guard isFileName, isDigest else {

      throw DeviceDatabaseUpdateError.malformedManifest

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

    guard response.isSuccess else {

      throw DeviceDatabaseUpdateError.unexpectedStatus(response.statusCode)

    }

    return response.body

  }

  /// The SHA-256 of the copy the package ships with, worked out once.
  private static let bundledDigest = Result<String, any Error> {

    sha256(of: try DeviceDatabase.bundledJSON())

  }

  /// The SHA-256 of some bytes, as lowercase hexadecimal.
  private static func sha256(of data: Data) -> String {

    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

  }

}
#endif
