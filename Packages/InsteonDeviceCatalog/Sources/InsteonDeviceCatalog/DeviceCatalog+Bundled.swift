import Foundation

// Finding the copy of the catalog the package ships with.
//
// The Swift Package Manager puts the package's resources in a bundle, and the accessor it
// generates for them stops the process when the bundle isn't where it expects, such as when a
// command was copied without the bundle beside it. So the package looks for the bundle itself,
// where the accessor and Xcode's would, and throws when it isn't anywhere.
extension DeviceCatalog {

  /// The names the Swift Package Manager gives the bundle of the package's resources: on Apple
  /// platforms, then elsewhere.
  ///
  /// A command that uses the package has to be installed with this bundle beside it, such as
  /// `swift-insteon_InsteonDeviceCatalog.bundle` next to the executable.
  public static let bundleNames: [String] = [
    "swift-insteon_InsteonDeviceCatalog.bundle",
    "swift-insteon_InsteonDeviceCatalog.resources"
  ]

  /// The directories the package's resources can be in, in the order they're tried: in a
  /// bundle of either of ``DeviceCatalog/bundleNames``, flat or with the `Contents/Resources`
  /// layout of a macOS bundle, in each directory.
  ///
  /// ```swift
  /// let directory = URL(fileURLWithPath: "/home/example/.local/bin", isDirectory: true)
  ///
  /// DeviceCatalog.bundledResourceCandidates(nextTo: [directory]).first?.path
  /// // "/home/example/.local/bin/swift-insteon_InsteonDeviceCatalog.bundle"
  /// ```
  ///
  /// - Parameter directories: The directories to look in, such as an executable's own, with
  ///   and without symbolic links resolved. Each is looked in once.
  /// - Returns: The directories that may hold the resources, whether or not they're there.
  public static func bundledResourceCandidates(nextTo directories: [URL]) -> [URL] {

    var seen: Set<String> = []
    var candidates: [URL] = []

    for directory in directories {

      let key: String = directory.standardizedFileURL.path

      if key.isEmpty || !seen.insert(key).inserted {

        continue

      }

      for name in bundleNames {

        let bundle: URL = directory.appending(path: name, directoryHint: .isDirectory)

        candidates.append(bundle)
        candidates.append(bundle.appending(path: "Contents/Resources", directoryHint: .isDirectory))

      }

    }

    return candidates

  }

  /// Loads a catalog from a file, such as an app's saved copy or the one
  /// ``DeviceCatalog/bundledCatalogURL()`` finds.
  ///
  /// - Parameter url: The file's URL.
  /// - Returns: The catalog.
  /// - Throws: The error reading the file, or `DecodingError` if it isn't a catalog.
  public static func load(contentsOf url: URL) throws -> DeviceCatalog {

    let json: Data = try Data(contentsOf: url)

    return try DeviceCatalog(json: json)

  }

  /// Loads the copy of the catalog the package ships with.
  ///
  /// The copy is read once, the first time it's asked for. It's looked for beside the main
  /// bundle, the executable, with symbolic links resolved too, and the package's own code, as
  /// ``DeviceCatalog/bundledResourceCandidates(nextTo:)`` lists, so a missing bundle throws
  /// rather than stopping the process.
  ///
  /// - Returns: The catalog.
  /// - Throws: ``DeviceCatalogError/missingBundledCatalog`` if the copy isn't found, or the
  ///   error reading it.
  public static func bundled() throws -> DeviceCatalog {

    try bundledCopy.get()

  }

  /// Loads the copy of the catalog the package ships with from a bundle in the given
  /// directories, such as for an app that installs the bundle somewhere of its own.
  ///
  /// Unlike ``DeviceCatalog/bundled()``, the copy is read again each time.
  ///
  /// - Parameter directories: The directories the bundle can be in, as
  ///   ``DeviceCatalog/bundledResourceCandidates(nextTo:)`` takes them.
  /// - Returns: The catalog.
  /// - Throws: ``DeviceCatalogError/missingBundledCatalog`` if the copy isn't in any of them,
  ///   or the error reading it.
  public static func bundled(nextTo directories: [URL]) throws -> DeviceCatalog {

    let url: URL = try bundledResource(named: catalogFileName, nextTo: directories)

    return try load(contentsOf: url)

  }

  /// The copy the package ships with, or the error reading it.
  private static let bundledCopy = Result<DeviceCatalog, any Error> {

    let url: URL = try bundledCatalogURL()

    return try load(contentsOf: url)

  }

  /// The file of the copy of the catalog the package ships with, such as to say where it was
  /// read from.
  ///
  /// - Returns: The file's URL.
  /// - Throws: ``DeviceCatalogError/missingBundledCatalog`` if the copy isn't found.
  public static func bundledCatalogURL() throws -> URL {

    try bundledResource(named: catalogFileName, nextTo: searchDirectories())

  }

  /// The version of the copy the package ships with, from the manifest shipped beside it.
  ///
  /// The package reads catalogs in this version's format: ones with the same MAJOR.MINOR.
  /// ``DeviceCatalogUpdater`` uses a downloaded catalog only if its version is compatible with
  /// this one.
  ///
  /// - Returns: The version, such as 0.5.11.
  /// - Throws: ``DeviceCatalogError/missingBundledCatalog`` if the manifest isn't found, or the
  ///   error reading it.
  public static func bundledVersion() throws -> DeviceCatalogVersion {

    try bundledManifest.get().version

  }

  /// The manifest of the copy the package ships with, or the error reading it.
  private static let bundledManifest = Result<CatalogManifest, any Error> {

    let url: URL = try bundledResource(named: manifestFileName, nextTo: searchDirectories())
    let json: Data = try Data(contentsOf: url)

    return try JSONDecoder().decode(CatalogManifest.self, from: json)

  }

  /// The JSON of the copy the package ships with, such as to save as an app's own copy.
  ///
  /// - Returns: The JSON.
  /// - Throws: ``DeviceCatalogError/missingBundledCatalog`` if the copy isn't found, or the
  ///   error reading it.
  public static func bundledJSON() throws -> Data {

    let url: URL = try bundledCatalogURL()

    return try Data(contentsOf: url)

  }

  /// The catalog's file in the bundle.
  private static let catalogFileName: String = "catalog.json"

  /// The manifest's file in the bundle.
  private static let manifestFileName: String = "manifest.json"

  /// The first readable file with a name in a bundle in the directories.
  private static func bundledResource(named name: String, nextTo directories: [URL]) throws -> URL {

    for candidate in bundledResourceCandidates(nextTo: directories) {

      let url: URL = candidate.appending(path: name, directoryHint: .notDirectory)

      if FileManager.default.isReadableFile(atPath: url.path) {

        return url

      }

    }

    throw DeviceCatalogError.missingBundledCatalog

  }

  /// The directories the bundle can be in: where the Swift Package Manager's accessor looks,
  /// beside the main bundle, which is a command's own directory; the executable's directory,
  /// with symbolic links resolved too, for a command linked into a directory on `PATH`; where
  /// Xcode's accessor looks, in the main bundle's resources and the resources of the bundle
  /// with the package's code; and beside that bundle, as with a test bundle.
  private static func searchDirectories() -> [URL] {

    let main: Bundle = Bundle.main
    let code: Bundle = Bundle(for: BundleFinder.self)

    var directories: [URL] = [main.bundleURL]

    if let executable = main.executableURL {

      directories.append(executable.deletingLastPathComponent())
      directories.append(executable.resolvingSymlinksInPath().deletingLastPathComponent())

    }

    if let resources = main.resourceURL {

      directories.append(resources)

    }

    if let resources = code.resourceURL {

      directories.append(resources)

    }

    directories.append(code.bundleURL)
    directories.append(code.bundleURL.deletingLastPathComponent())

    return directories

  }

}

/// A class in the package's code, to find the bundle the code is in.
private final class BundleFinder {}
