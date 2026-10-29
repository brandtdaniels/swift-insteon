/// Where the `insteon` command looks for the Insteon device catalog it ships with.
///
/// The catalog is a resource of InsteonDeviceCatalog, which the Swift Package Manager puts in a
/// bundle next to the executable: `swift-insteon_InsteonDeviceCatalog.bundle` on Apple
/// platforms and `swift-insteon_InsteonDeviceCatalog.resources` elsewhere. Copying only the
/// executable leaves the bundle behind, and `DeviceCatalog.bundled()` stops the process when
/// it can't find it, so the command looks for the catalog's file itself, and runs without
/// product names when it isn't there.
///
/// ```swift
/// CatalogLocation.candidatePaths(nextTo: ["/home/example/.local/bin"]).first
/// // "/home/example/.local/bin/swift-insteon_InsteonDeviceCatalog.bundle/catalog.json"
/// ```
public enum CatalogLocation {

  /// The names the Swift Package Manager gives the catalog's bundle: on Apple platforms, and
  /// elsewhere.
  public static let bundleNames = [
    "swift-insteon_InsteonDeviceCatalog.bundle",
    "swift-insteon_InsteonDeviceCatalog.resources"
  ]

  /// The catalog's file inside the bundle.
  public static let fileName = "catalog.json"

  /// The paths the catalog's file can be at, in the order to try them: in a bundle of either
  /// name, flat or with the `Contents/Resources` layout of a macOS bundle, in each directory.
  ///
  /// - Parameter directories: The directories to look in, such as the executable's own, with
  ///   and without symbolic links resolved. Each is looked in once.
  /// - Returns: The paths.
  public static func candidatePaths(nextTo directories: [String]) -> [String] {

    var seen: Set<String> = []
    var paths: [String] = []

    for directory in directories where !directory.isEmpty && seen.insert(directory).inserted {

      for bundle in bundleNames {

        for inside in ["", "Contents/Resources/"] {

          paths.append(joined(directory, bundle) + "/" + inside + fileName)

        }

      }

    }

    return paths

  }

  private static func joined(_ directory: String, _ name: String) -> String {

    directory.hasSuffix("/") ? directory + name : directory + "/" + name

  }

}
