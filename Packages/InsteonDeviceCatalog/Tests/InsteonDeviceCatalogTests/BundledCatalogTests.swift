import Foundation
import Testing
import InsteonDeviceCatalog

struct BundledCatalogTests {

  /// A directory of its own in the temporary directory, not yet made.
  static func temporaryDirectory() -> URL {

    let name: String = "BundledCatalogTests-" + UUID().uuidString

    return FileManager.default.temporaryDirectory.appending(path: name, directoryHint: .isDirectory)

  }

  @Test func looksForTheBundleInEitherLayoutInEachDirectoryOnce() {

    let bin: URL = URL(fileURLWithPath: "/opt/example/bin", isDirectory: true)
    let build: URL = URL(fileURLWithPath: "/opt/example/build/", isDirectory: true)
    let paths: [String] = DeviceCatalog.bundledResourceCandidates(nextTo: [bin, bin, build]).map(\.path)

    #expect(paths.count == 8)
    #expect(paths.first == "/opt/example/bin/swift-insteon_InsteonDeviceCatalog.bundle")
    #expect(paths.contains("/opt/example/bin/swift-insteon_InsteonDeviceCatalog.bundle/Contents/Resources"))
    #expect(paths.contains("/opt/example/build/swift-insteon_InsteonDeviceCatalog.resources"))

  }

  @Test func throwsRatherThanStoppingWhenTheBundleIsMissing() {

    let directory: URL = Self.temporaryDirectory()

    #expect(throws: DeviceCatalogError.missingBundledCatalog) {

      try DeviceCatalog.bundled(nextTo: [directory])

    }

  }

  @Test(arguments: ["swift-insteon_InsteonDeviceCatalog.resources", "swift-insteon_InsteonDeviceCatalog.bundle", "swift-insteon_InsteonDeviceCatalog.bundle/Contents/Resources"])
  func loadsTheCatalogFromABundleInADirectory(_ inside: String) throws {

    let directory: URL = Self.temporaryDirectory()
    let resources: URL = directory.appending(path: inside, directoryHint: .isDirectory)

    defer { try? FileManager.default.removeItem(at: directory) }

    let json: Data = try DeviceCatalog.bundledJSON()
    let file: URL = resources.appending(path: "catalog.json", directoryHint: .notDirectory)

    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    try json.write(to: file)

    let catalog: DeviceCatalog = try DeviceCatalog.bundled(nextTo: [directory])
    let bundled: DeviceCatalog = try DeviceCatalog.bundled()

    #expect(catalog == bundled)

  }

  @Test func loadsTheBundledCatalogFromItsFile() throws {

    let url: URL = try DeviceCatalog.bundledCatalogURL()
    let catalog: DeviceCatalog = try DeviceCatalog.load(contentsOf: url)
    let bundled: DeviceCatalog = try DeviceCatalog.bundled()

    #expect(url.lastPathComponent == "catalog.json")
    #expect(catalog == bundled)

  }

}
