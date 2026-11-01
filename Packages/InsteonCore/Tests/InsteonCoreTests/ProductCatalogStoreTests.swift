import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import Testing
import InsteonCore
import InsteonDeviceCatalog

struct ProductCatalogStoreTests {

  /// A directory of its own in the temporary directory, not yet made.
  static func temporaryDirectory() -> URL {

    FileManager.default.temporaryDirectory.appending(path: "ProductCatalogStoreTests-" + UUID().uuidString, directoryHint: .isDirectory)

  }

  /// A store whose files are in `insteon` inside a directory.
  static func store(in directory: URL) -> ProductCatalogStore {

    let folder: URL = directory.appending(path: "insteon", directoryHint: .isDirectory)

    return ProductCatalogStore(
      catalogPath: folder.appending(path: "catalog.json", directoryHint: .notDirectory).path(percentEncoded: false),
      versionPath: folder.appending(path: "catalog-version.json", directoryHint: .notDirectory).path(percentEncoded: false)
    )

  }

  /// A file's POSIX permissions.
  static func permissions(of path: String) throws -> Int {

    let attributes: [FileAttributeKey: Any] = try FileManager.default.attributesOfItem(atPath: path)
    let permissions: NSNumber? = attributes[.posixPermissions] as? NSNumber

    return permissions?.intValue ?? -1

  }

  let json: Data = Data(#"{"products":[]}"#.utf8)
  let version: DeviceCatalogVersion = DeviceCatalogVersion(major: 0, minor: 6, patch: 26)

  @Test func hasNoCopyBeforeSaving() {

    let store: ProductCatalogStore = Self.store(in: Self.temporaryDirectory())

    #expect(!store.hasCachedCopy)
    #expect(store.cachedJSON() == nil)
    #expect(store.cachedVersion() == nil)

  }

  @Test func savesAndReadsFilesOnlyTheUserCanRead() throws {

    let directory: URL = Self.temporaryDirectory()

    defer { try? FileManager.default.removeItem(at: directory) }

    let store: ProductCatalogStore = Self.store(in: directory)

    try store.save(json: json, version: version)

    #expect(store.hasCachedCopy)
    #expect(store.cachedJSON() == json)
    #expect(store.cachedVersion() == version)
    #expect(try Self.permissions(of: store.catalogPath) == 0o600)
    #expect(try Self.permissions(of: store.versionPath) == 0o600)
    #expect(try Self.permissions(of: store.directory) == 0o700)

  }

  @Test func writesTheVersionAsAString() throws {

    let directory: URL = Self.temporaryDirectory()

    defer { try? FileManager.default.removeItem(at: directory) }

    let store: ProductCatalogStore = Self.store(in: directory)

    try store.save(json: json, version: version)

    let written: Data? = FileManager.default.contents(atPath: store.versionPath)

    #expect(written == Data(#""0.6.26""#.utf8))
    #expect(ProductCatalogStore.version(json: Data(#""0.6.26""#.utf8)) == version)
    #expect(ProductCatalogStore.version(json: Data("not a version".utf8)) == nil)

  }

  @Test func replacesAnEarlierCopyWhole() throws {

    let directory: URL = Self.temporaryDirectory()

    defer { try? FileManager.default.removeItem(at: directory) }

    let store: ProductCatalogStore = Self.store(in: directory)
    let newer: Data = Data(#"{"products":[{"name":"Plug"}]}"#.utf8)
    let newerVersion: DeviceCatalogVersion = DeviceCatalogVersion(major: 0, minor: 6, patch: 27)

    try store.save(json: json, version: version)
    try store.save(json: newer, version: newerVersion)

    #expect(store.cachedJSON() == newer)
    #expect(store.cachedVersion() == newerVersion)

  }

  @Test func readsNoVersionWithoutACatalog() throws {

    let directory: URL = Self.temporaryDirectory()

    defer { try? FileManager.default.removeItem(at: directory) }

    let store: ProductCatalogStore = Self.store(in: directory)

    try store.save(json: json, version: version)
    try FileManager.default.removeItem(atPath: store.catalogPath)

    #expect(!store.hasCachedCopy)
    #expect(store.cachedVersion() == nil)

  }

  @Test func readsOnlyARegularFile() throws {

    let directory: URL = Self.temporaryDirectory()

    defer { try? FileManager.default.removeItem(at: directory) }

    let store: ProductCatalogStore = Self.store(in: directory)
    let elsewhere: String = directory.appending(path: "elsewhere.json", directoryHint: .notDirectory).path(percentEncoded: false)

    try FileManager.default.createDirectory(atPath: store.catalogPath, withIntermediateDirectories: true)
    try json.write(to: URL(filePath: elsewhere))
    try FileManager.default.createSymbolicLink(atPath: store.versionPath, withDestinationPath: elsewhere)

    #expect(store.hasCachedCopy)
    #expect(store.cachedJSON() == nil)
    #expect(store.cachedVersion() == nil)

  }

  @Test func throwsWhenTheDirectoryCantBeMade() throws {

    let directory: URL = Self.temporaryDirectory()

    defer { try? FileManager.default.removeItem(at: directory) }

    let store: ProductCatalogStore = Self.store(in: directory)

    // A file where the catalog's directory belongs, so the catalog can't be created in it.
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data().write(to: URL(filePath: store.directory))

    #expect(throws: ProductCatalogStoreError.writeFailed(code: ENOTDIR)) {

      try store.save(json: json, version: version)

    }

    #expect(store.cachedJSON() == nil)

  }

}
