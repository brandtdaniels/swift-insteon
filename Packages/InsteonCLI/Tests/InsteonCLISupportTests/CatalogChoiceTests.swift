import Foundation
import Testing
import InsteonCLISupport
import InsteonCore
import InsteonDeviceCatalog
import InsteonProtocol

/// Which copy of the catalog the command loads. A catalog here is a made-up name, so the
/// tests see which copy was read.
struct CatalogChoiceTests {

  let bundled = DeviceCatalogVersion(major: 0, minor: 6, patch: 20)
  let newer = DeviceCatalogVersion(major: 0, minor: 6, patch: 21)
  let cachedJSON = Data("cached".utf8)
  let catalogPath = "/home/example/.cache/insteon/catalog.json"
  let versionPath = "/home/example/.cache/insteon/catalog-version.json"

  /// What a choice read and said.
  final class Record {

    var warnings: [String] = []

    var bundledLoads: Int = 0

  }

  private func choose(
    _ copies: FakeCatalogCopies,
    reading: (Data) throws -> String = { String(decoding: $0, as: UTF8.self) },
    bundledCatalog: String? = "bundled",
    record: Record = Record()
  ) -> CatalogCache.Choice<String>? {

    CatalogCache.choose(
      copies,
      reading: reading,
      bundled: { () -> String? in

        record.bundledLoads += 1

        return bundledCatalog

      },
      warn: { record.warnings.append($0) }
    )

  }

  @Test func usesTheBundledCopyWithoutACachedOne() {

    let record = Record()

    #expect(choose(FakeCatalogCopies(bundled: bundled), record: record) == CatalogCache.Choice(catalog: "bundled", source: .bundled))
    #expect(record.warnings.isEmpty)

  }

  @Test func usesTheCachedCopyWhenItsNewEnoughAndReads() {

    let record = Record()
    let choice = choose(FakeCatalogCopies(bundled: bundled, cached: newer, json: cachedJSON), record: record)

    #expect(choice == CatalogCache.Choice(catalog: "cached", source: .cached))
    #expect(record.bundledLoads == 0)
    #expect(record.warnings.isEmpty)

  }

  @Test func usesTheBundledCopyQuietlyOverAnOlderCachedOne() {

    let older = DeviceCatalogVersion(major: 0, minor: 6, patch: 19)
    let record = Record()

    #expect(choose(FakeCatalogCopies(bundled: bundled, cached: older, json: cachedJSON), record: record)?.source == .bundled)
    #expect(record.warnings.isEmpty)

  }

  @Test func warnsWhenTheCachedVersionCantBeRead() {

    let record = Record()
    let choice = choose(FakeCatalogCopies(bundled: bundled, cached: nil, json: cachedJSON), record: record)

    #expect(choice?.source == .bundled)
    #expect(
      record.warnings == [
        "insteon: warning: the cached Insteon device catalog's version, \(versionPath), couldn't be read, so the cached copy isn't used. "
          + "'insteon catalog update' downloads it again."
      ]
    )

  }

  @Test func warnsAndUsesTheBundledCopyWhenTheCachedOneCantBeRead() {

    let unreadable = "insteon: warning: the cached Insteon device catalog at \(catalogPath) couldn't be read, "
      + "so it isn't used. 'insteon catalog update' downloads it again."

    let missingRecord = Record()
    let missing = choose(FakeCatalogCopies(bundled: bundled, cached: newer, json: nil, hasFile: true), record: missingRecord)

    let notACatalogRecord = Record()
    let notACatalog = choose(
      FakeCatalogCopies(bundled: bundled, cached: newer, json: cachedJSON),
      reading: { (_: Data) throws -> String in throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Not a catalog.")) },
      record: notACatalogRecord
    )

    #expect(missing?.source == .bundled)
    #expect(missingRecord.warnings == [unreadable])
    #expect(notACatalog?.source == .bundled)
    #expect(notACatalogRecord.warnings == [unreadable])

  }

  @Test func warnsAndUsesTheBundledCopyWhenTheCachedOneWeakensItsGuards() {

    let weakenings = [GuardWeakening(category: 0x01, subcategory: 0x02, firmwareVersion: nil, kind: .flagBits, detail: "example")]
    let record = Record()
    let choice = choose(
      FakeCatalogCopies(bundled: bundled, cached: newer, json: cachedJSON),
      reading: { (_: Data) throws -> String in throw ProductCatalogError.weakensGuards(weakenings) },
      record: record
    )

    #expect(choice == CatalogCache.Choice(catalog: "bundled", source: .bundled))
    #expect(record.warnings == [CatalogText.cachedWeakensGuards(path: catalogPath, weakenings)])

  }

  @Test func usesNoCopyWhenTheCachedOneCantBeChecked() {

    let record = Record()
    let choice = choose(
      FakeCatalogCopies(bundled: bundled, cached: newer, json: cachedJSON),
      reading: { (_: Data) throws -> String in throw ProductCatalogError.bundledCopyMissing },
      record: record
    )

    #expect(choice == nil)
    #expect(record.bundledLoads == 0)
    #expect(record.warnings == [CatalogText.cachedUnchecked(path: catalogPath, bundledIsMissing: true)])

  }

  @Test func usesNoCopyWhenTheBundledOneCantBeLoaded() {

    #expect(choose(FakeCatalogCopies(bundled: bundled), bundledCatalog: nil) == nil)

  }

  @Test func namesTheCachedFileByItsPathInTheCacheDirectoryWithoutOne() {

    let record = Record()

    _ = choose(FakeCatalogCopies(bundled: bundled, cached: newer, json: nil, hasFile: true, catalogPath: nil), record: record)

    #expect(record.warnings.first?.contains("at \(CatalogCache.relativePath) couldn't be read") == true)

  }

}
