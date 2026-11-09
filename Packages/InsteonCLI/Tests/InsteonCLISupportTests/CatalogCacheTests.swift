import Foundation
import Testing
import InsteonCLISupport
import InsteonCore
import InsteonDeviceCatalog
import InsteonProtocol

struct CatalogCacheTests {

  // Made-up versions; only their numbers matter.
  let bundled = DeviceCatalogVersion(major: 0, minor: 6, patch: 20)

  // MARK: - Which copy

  @Test func usesTheBundledCopyWithoutACachedOne() {

    #expect(CatalogCache.source(bundled: bundled, cached: nil) == .bundled)

  }

  @Test func usesACachedCopyWithAHigherOrEqualPatch() {

    let newer = DeviceCatalogVersion(major: 0, minor: 6, patch: 21)

    #expect(CatalogCache.source(bundled: bundled, cached: newer) == .cached)
    #expect(CatalogCache.source(bundled: bundled, cached: bundled) == .cached)

  }

  @Test func usesTheBundledCopyOverACachedOneWithALowerPatch() {

    let older = DeviceCatalogVersion(major: 0, minor: 6, patch: 19)

    #expect(CatalogCache.source(bundled: bundled, cached: older) == .bundled)

  }

  @Test func usesTheBundledCopyOverACachedOneInAnotherFormat() {

    let nextMinor = DeviceCatalogVersion(major: 0, minor: 7, patch: 0)
    let earlierMinor = DeviceCatalogVersion(major: 0, minor: 5, patch: 99)
    let nextMajor = DeviceCatalogVersion(major: 1, minor: 6, patch: 20)

    #expect(CatalogCache.source(bundled: bundled, cached: nextMinor) == .bundled)
    #expect(CatalogCache.source(bundled: bundled, cached: earlierMinor) == .bundled)
    #expect(CatalogCache.source(bundled: bundled, cached: nextMajor) == .bundled)

  }

  @Test func usesNoCachedCopyWithoutABundledOneToCheckItAgainst() {

    let cached = DeviceCatalogVersion(major: 0, minor: 6, patch: 3)

    #expect(CatalogCache.source(bundled: nil, cached: cached) == .bundled)
    #expect(CatalogCache.source(bundled: nil, cached: nil) == .bundled)

  }

  // MARK: - Files

  @Test func keepsTheCatalogInTheCacheDirectory() {

    let environment: [String: String] = ["HOME": "/home/example"]

    #expect(CatalogCache.path(environment: environment) == "/home/example/.cache/insteon/catalog.json")
    #expect(CatalogCache.versionPath(environment: environment) == "/home/example/.cache/insteon/catalog-version.json")
    #expect(
      CatalogCache.path(environment: ["HOME": "/home/example", "XDG_CACHE_HOME": "/var/cache/example"])
        == "/var/cache/example/insteon/catalog.json"
    )
    #expect(CatalogCache.path(environment: [:]) == nil)

  }

  @Test func readsAndWritesTheVersionAsAString() throws {

    let version = DeviceCatalogVersion(major: 0, minor: 6, patch: 26)
    let json: Data = try CatalogCache.versionJSON(version)

    #expect(String(decoding: json, as: UTF8.self) == "\"0.6.26\"")
    #expect(CatalogCache.version(json: json) == version)
    #expect(CatalogCache.version(json: Data("\"0.6\"".utf8)) == nil)
    #expect(CatalogCache.version(json: Data("not json".utf8)) == nil)

  }

  // MARK: - Text

  @Test func printsTheVersionsAndTheCopyInUse() {

    let cached = DeviceCatalogVersion(major: 0, minor: 6, patch: 26)

    #expect(
      CatalogText.status(bundled: bundled, cached: cached, hasCachedFile: true, inUse: .cached)
        == ["Bundled:  0.6.20", "Cached:   0.6.26", "In use:   cached"]
    )
    #expect(
      CatalogText.status(bundled: bundled, cached: nil, hasCachedFile: false, inUse: .bundled)
        == ["Bundled:  0.6.20", "Cached:   none", "In use:   bundled"]
    )
    #expect(
      CatalogText.status(bundled: nil, cached: nil, hasCachedFile: true, inUse: nil)
        == ["Bundled:  missing", "Cached:   unreadable", "In use:   none"]
    )

  }

  @Test func saysWhatAnUpdateDid() {

    let version = DeviceCatalogVersion(major: 0, minor: 6, patch: 26)

    #expect(CatalogText.updated(to: version) == "Updated the Insteon device catalog to 0.6.26.")
    #expect(CatalogText.upToDate(version) == "The Insteon device catalog is up to date (0.6.26).")
    let older: String = CatalogText.publishedIsOlder(published: bundled, current: version)

    #expect(older.contains("0.6.20"))
    #expect(older.contains("0.6.26"))
    #expect(older.contains("current copy stays"))

  }

  @Test func saysWhenThePublishedCatalogNeedsANewerPackage() {

    let newer = DeviceCatalogVersion(major: 0, minor: 7, patch: 0)
    let older = DeviceCatalogVersion(major: 0, minor: 5, patch: 9)

    let needsNewer: String = CatalogText.incompatible(published: newer, bundled: bundled, current: bundled)
    let isOlder: String = CatalogText.incompatible(published: older, bundled: bundled, current: bundled)

    #expect(needsNewer.contains("needs a newer swift-insteon"))
    #expect(needsNewer.contains("the current copy, 0.6.20, stays"))
    #expect(isOlder.contains("older format"))
    #expect(!isOlder.contains("needs a newer swift-insteon"))

  }

  // MARK: - The cached copy

  @Test func usesNoCachedCopyWhenTheBundledCopyIsMissingOrUnreadable() {

    let path = "/home/example/.cache/insteon/catalog.json"

    for (error, isMissing) in [(ProductCatalogError.bundledCopyMissing, true), (.bundledCopyUnreadable, false)] {

      guard case let .useNone(warning) = CatalogCache.cachedCatalog(Data(), path: path, reading: { (_: Data) throws -> ProductCatalog in throw error }) else {

        Issue.record("Expected no catalog for \(error).")

        continue

      }

      #expect(warning == CatalogText.cachedUnchecked(path: path, bundledIsMissing: isMissing))

    }

  }

  @Test func usesTheBundledCopyWhenTheCachedOneWeakensItsGuards() {

    let weakenings = [GuardWeakening(category: 0x01, subcategory: 0x7A, firmwareVersion: nil, kind: .flagBits, detail: "Get Operating Flags 0x00 kept bits 0x40")]
    let outcome = CatalogCache.cachedCatalog(Data(), path: "/c.json", reading: { (_: Data) throws -> ProductCatalog in throw ProductCatalogError.weakensGuards(weakenings) })

    guard case let .useBundled(warning) = outcome else {

      Issue.record("Expected the bundled copy, got \(outcome).")

      return

    }

    #expect(warning == CatalogText.cachedWeakensGuards(path: "/c.json", weakenings))

  }

  @Test func readsTheBundledCopyAsTheCachedOne() throws {

    let json: Data = try Data(contentsOf: ProductCatalog.bundledCatalogURL())

    guard case .use = CatalogCache.cachedCatalog(json, path: "/c.json", reading: ProductCatalog.init(json:)) else {

      Issue.record("Expected the cached copy to be used.")

      return

    }

    guard case .unreadable = CatalogCache.cachedCatalog(Data("{}".utf8), path: "/c.json", reading: ProductCatalog.init(json:)) else {

      Issue.record("Expected an unreadable copy.")

      return

    }

  }

  // MARK: - Weakened guards

  @Test func blamesTheBundledCopyWhenTheCachedOneCantBeChecked() {

    #expect(CatalogText.cachedUnchecked(path: "/home/example/.cache/insteon/catalog.json", bundledIsMissing: true) == "insteon: warning: the cached "
      + "Insteon device catalog at /home/example/.cache/insteon/catalog.json isn't used: the catalog the command ships with isn't next to it, "
      + "so nothing can check the cached copy's guards. Scripts/install-insteon.sh installs the command with it.")
    #expect(CatalogText.cachedUnchecked(path: "/home/example/.cache/insteon/catalog.json", bundledIsMissing: false) == "insteon: warning: the cached "
      + "Insteon device catalog at /home/example/.cache/insteon/catalog.json isn't used: the catalog the command ships with couldn't be read, "
      + "so nothing can check the cached copy's guards. Scripts/install-insteon.sh installs the command with it.")

  }

  @Test func saysWhichGuardsAPublishedOrCachedCatalogWeakens() {

    let weakenings: [GuardWeakening] = [
      GuardWeakening(category: 0x01, subcategory: 0x7A, firmwareVersion: nil, kind: .unlocksProtectedCommand, detail: "Set Operating Flags 0x0C"),
      GuardWeakening(category: 0x01, subcategory: 0x7A, firmwareVersion: nil, kind: .flagsQuery, detail: "D7 Get Operating Flags 0x00")
    ]
    let current = DeviceCatalogVersion(major: 0, minor: 6, patch: 21)

    #expect(CatalogText.publishedWeakensGuards(weakenings, current: current) == "The published Insteon device catalog would let more be sent or written to a device than the bundled copy does, "
      + "weakening the guards that keep it reachable and unlocked (0x01/0x7A unlocksProtectedCommand Set Operating Flags 0x0C, 0x01/0x7A flagsQuery D7 Get Operating Flags 0x00), "
      + "so it isn't used and the current copy, 0.6.21, stays.")
    #expect(CatalogText.cachedWeakensGuards(path: "/home/example/.cache/insteon/catalog.json", weakenings) == "insteon: warning: the cached Insteon device catalog "
      + "at /home/example/.cache/insteon/catalog.json would let more be sent or written to a device than the bundled copy does, "
      + "weakening the guards that keep it reachable and unlocked (0x01/0x7A unlocksProtectedCommand Set Operating Flags 0x0C, 0x01/0x7A flagsQuery D7 Get Operating Flags 0x00), so the bundled copy is used. "
      + "'insteon catalog update' replaces it.")

  }

}
