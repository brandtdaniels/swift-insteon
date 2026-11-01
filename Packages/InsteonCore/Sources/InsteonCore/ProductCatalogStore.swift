import Foundation
import InsteonDeviceCatalog

/// A downloaded copy of the Insteon device catalog kept in two files: the catalog's JSON, and
/// its version beside it.
///
/// Both files are written readable only by the current user and replaced whole, so a reader
/// never sees half of one. A front end saves the JSON that
/// ``ProductCatalog/update(replacing:currentVersion:from:requestTimeout:resourceTimeout:)``
/// returns, and reads it back on the next launch:
///
/// ```swift
/// let store = ProductCatalogStore(
///   catalogPath: "/home/example/.cache/insteon/catalog.json",
///   versionPath: "/home/example/.cache/insteon/catalog-version.json"
/// )
///
/// if let json = store.cachedJSON() {
///   let catalog = try ProductCatalog(json: json)
/// }
/// ```
///
/// Only a regular file is read, so a directory, a symbolic link or a named pipe at either path
/// reads as no copy.
public struct ProductCatalogStore: Hashable, Sendable {

  /// The catalog's file.
  public var catalogPath: String

  /// The file of the catalog's version, a JSON string such as `"0.6.26"`.
  public var versionPath: String

  /// Creates a store for a catalog's two files.
  ///
  /// - Parameters:
  ///   - catalogPath: The catalog's file.
  ///   - versionPath: The file of the catalog's version.
  public init(catalogPath: String, versionPath: String) {

    self.catalogPath = catalogPath
    self.versionPath = versionPath

  }

  /// The directory the catalog's file is in, such as `/home/example/.cache/insteon`.
  public var directory: String {

    PrivateFile.directory(of: catalogPath)

  }

  /// Whether there's a copy of the catalog, readable or not.
  public var hasCachedCopy: Bool {

    PrivateFile.exists(catalogPath)

  }

  /// The copy's version, or `nil` if there's no copy or its version can't be read.
  public func cachedVersion() -> DeviceCatalogVersion? {

    guard hasCachedCopy, let data = PrivateFile.read(versionPath) else {

      return nil

    }

    return Self.version(json: data)

  }

  /// The copy's JSON, or `nil` if there's none or it can't be read.
  public func cachedJSON() -> Data? {

    PrivateFile.read(catalogPath)

  }

  /// Saves a catalog and its version, each readable only by the current user and replaced
  /// whole.
  ///
  /// The catalog is written before its version, so a version left older than its catalog
  /// after a failed write names a catalog of the same format, as long as only a catalog the
  /// package reads is saved.
  ///
  /// The catalog's directory is created readable only by the current user, any directory
  /// above it that isn't there is created with the system's default permissions, and a
  /// directory that's already there is left as it is.
  ///
  /// - Parameters:
  ///   - json: The catalog's JSON.
  ///   - version: The catalog's version.
  /// - Throws: ``ProductCatalogStoreError/writeFailed(code:)`` with the system's error code if
  ///   either file couldn't be written.
  public func save(json: Data, version: DeviceCatalogVersion) throws {

    let versionJSON: Data = try Self.versionJSON(version)

    do {

      try PrivateFile.replace(catalogPath, with: json)
      try PrivateFile.replace(versionPath, with: versionJSON)

    } catch let DeviceRegistryStoreError.writeFailed(code) {

      throw ProductCatalogStoreError.writeFailed(code: code)

    }

  }

  /// Reads a catalog's version from its file's JSON, a string such as `"0.6.26"`.
  ///
  /// - Parameter json: The file's contents.
  /// - Returns: The version, or `nil` if the contents aren't a version.
  public static func version(json: Data) -> DeviceCatalogVersion? {

    try? JSONDecoder().decode(DeviceCatalogVersion.self, from: json)

  }

  /// A catalog's version as its file's JSON, a string such as `"0.6.26"`.
  ///
  /// - Parameter version: The version.
  /// - Returns: The JSON.
  /// - Throws: `EncodingError` if the version can't be encoded.
  public static func versionJSON(_ version: DeviceCatalogVersion) throws -> Data {

    try JSONEncoder().encode(version)

  }

}

/// Why ``ProductCatalogStore/save(json:version:)`` didn't save a catalog.
public enum ProductCatalogStoreError: Error, Hashable, Sendable, CustomStringConvertible {

  /// A file couldn't be written, with the system's error code, such as `EACCES` or `ENOSPC`.
  case writeFailed(code: Int32)

  /// The error as a sentence.
  public var description: String {

    switch self {
    case let .writeFailed(code):
      "The Insteon device catalog couldn't be saved (error \(code))."
    }

  }

}
