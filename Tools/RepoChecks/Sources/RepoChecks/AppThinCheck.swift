import Foundation
import RepoCheckSupport

/// Checks that an app's shared sources import only the libraries an interface may use.
///
/// An app is a user interface: it calls the client libraries and presents the result, so its
/// sources under `Apps/*/Sources` import InsteonCore, InsteonService, InsteonClient or InsteonDemo
/// and no lower-level Insteon module, and only the Apple frameworks that draw it and host it.
/// `repo-check cli-thin` holds the same sources to its rules about device behavior.
public struct AppThinCheck: RepoCheck {
  public init() {}

  /// The Insteon modules an app may import.
  static let allowedModules: Set<String> = ["InsteonCore", "InsteonService", "InsteonClient", "InsteonDemo"]

  /// The Apple frameworks an app may import: drawing, observation and hosting.
  static let allowedFrameworks: Set<String> = [
    "Foundation", "SwiftUI", "Observation", "UIKit", "AppKit", "AVFoundation", "UserNotifications", "BackgroundTasks"
  ]

  public func run(in root: URL, console: Console) throws -> CheckStatus {
    let found = try problems(in: root)

    console.write(found.isEmpty ? "The apps import only the libraries an interface may use." : found.joined(separator: "\n"))

    return CheckStatus(findings: found)
  }

  func problems(in root: URL) throws -> [String] {
    let apps = root.appendingPathComponent("Apps", isDirectory: true)
    guard FileManager.default.fileExists(atPath: apps.path) else { return [] }
    var found: [String] = []

    for entry in try SourceFiles.entries(under: apps) where entry.components.last!.hasSuffix(".swift") {
      guard entry.components.count >= 3, entry.components[1] == "Sources" else { continue }
      let path = "Apps/" + entry.relativePath
      for line in SwiftCodeScanner.lines(in: try TextFile.read(entry.url(under: apps))) {
        guard let module = Self.importedModule(in: line.code) else { continue }
        if !Self.allowedModules.contains(module), !Self.allowedFrameworks.contains(module) {
          found.append("\(path):\(line.number): imports \(module), which an app may not; use \(Self.allowedModules.sorted().joined(separator: ", ")) or a hosting framework")
        }
      }
    }

    return found
  }

  /// The kinds of declaration an import can name: `import struct Module.Name`.
  private static let importKinds: Set<String> = ["typealias", "struct", "class", "enum", "protocol", "var", "let", "func", "actor"]

  /// The module a line imports, if it is an import: the name before the first dot, after any
  /// attributes, access modifiers and kind keyword, and before a trailing semicolon.
  static func importedModule(in code: String) -> String? {
    var words = code.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == ";" }).map(String.init)
    while let first = words.first, first.hasPrefix("@") || ["public", "internal", "package", "private", "fileprivate"].contains(first) {
      words.removeFirst()
    }
    guard words.first == "import" else { return nil }
    words.removeFirst()
    if let first = words.first, importKinds.contains(first) { words.removeFirst() }
    guard let path = words.first, let module = path.split(separator: ".").first else { return nil }
    return String(module)
  }
}
