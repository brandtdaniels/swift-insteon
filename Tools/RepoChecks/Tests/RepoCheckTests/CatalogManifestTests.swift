import Foundation
import RepoCheckSupport
import Testing

@testable import RepoChecks

@Suite("catalog-manifest")
struct CatalogManifestTests {
  private func manifest(_ json: String) throws -> (ScratchDirectory, URL) {
    let directory = try ScratchDirectory()
    try directory.write(json, to: "manifest.json")
    return (directory, directory.url(for: "manifest.json"))
  }

  @Test("reads the SHA-256 and the version")
  func readsFields() throws {
    let (directory, url) = try manifest(#"{"built": "x", "sha256": "abc123", "version": "0.10.1", "devices": 151}"#)

    #expect(try CatalogManifest.value(of: .sha256, at: url) == "abc123")
    #expect(try CatalogManifest.value(of: .version, at: url) == "0.10.1")
    _ = directory
  }

  @Test("refuses a manifest without the field, one that isn't an object, and a missing file")
  func refusals() throws {
    let (directory, url) = try manifest(#"{"sha256": "abc"}"#)
    #expect(throws: CheckFailure("\(url.path): has no version")) { try CatalogManifest.value(of: .version, at: url) }

    try directory.write("[1]", to: "list.json")
    #expect(throws: CheckFailure.self) { try CatalogManifest.value(of: .version, at: directory.url(for: "list.json")) }
    #expect(throws: CheckFailure.self) { try CatalogManifest.value(of: .version, at: directory.url(for: "missing.json")) }
  }

  @Test("reads the bundled manifest")
  func bundledManifest() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let url = root.appendingPathComponent("Packages/InsteonDeviceCatalog/Sources/InsteonDeviceCatalog/Resources/manifest.json")

    #expect(try CatalogManifest.value(of: .sha256, at: url).count == 64)
  }
}
