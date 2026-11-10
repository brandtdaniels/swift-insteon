import Foundation
import InsteonCLISupport
import InsteonCore

/// The `insteon` command's copies of the catalog as a test sets them: made-up versions and
/// contents, where only the numbers and bytes matter.
struct FakeCatalogCopies: CatalogCopies {

  var bundled: DeviceCatalogVersion?

  var cached: DeviceCatalogVersion?

  var json: Data?

  /// Whether there's a cached file, readable or not; by default, when there's a version or JSON.
  var hasFile: Bool?

  var catalogPath: String? = "/home/example/.cache/insteon/catalog.json"

  var versionPath: String? = "/home/example/.cache/insteon/catalog-version.json"

  func bundledVersion() -> DeviceCatalogVersion? { bundled }

  var hasCachedCopy: Bool { hasFile ?? (json != nil || cached != nil) }

  func cachedVersion() -> DeviceCatalogVersion? { cached }

  func cachedJSON() -> Data? { json }

}
