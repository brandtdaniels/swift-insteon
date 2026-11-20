import Foundation

/// A file or directory under a root.
public struct SourceEntry: Equatable, Sendable {
  /// The path from the root, one name per component.
  public let components: [String]

  /// Whether this is a directory. A symbolic link isn't one, whatever it points at.
  public let isDirectory: Bool

  public init(components: [String], isDirectory: Bool) {
    self.components = components
    self.isDirectory = isDirectory
  }

  /// The path from the root, with `/` between components.
  public var relativePath: String {
    components.joined(separator: "/")
  }

  /// The entry's URL under the root.
  public func url(under root: URL) -> URL {
    components.reduce(root) { $0.appendingPathComponent($1, isDirectory: false) }
  }
}

/// Discovery of the files under a root, in the order Python's `sorted(path.rglob("*"))` gives.
public enum SourceFiles {
  /// Directory names the scripts skipped, and so does the tool, without descending into them.
  public static let defaultPrunedNames: Set<String> = [".build", ".git"]

  /// Every entry under the root, sorted, leaving out any whose path has a pruned name as a
  /// component. A symbolic link to a directory is listed and not followed.
  public static func entries(under root: URL, pruning pruned: Set<String> = defaultPrunedNames) throws -> [SourceEntry] {
    var found: [SourceEntry] = []
    try collect(directory: root, components: [], pruning: pruned, into: &found)
    return found.sorted { isOrdered($0.components, before: $1.components) }
  }

  /// Whether one path sorts before another, comparing component by component as `pathlib` does,
  /// so `a/b.swift` sorts before `a.md`, and each component by code point.
  public static func isOrdered(_ a: [String], before b: [String]) -> Bool {
    for (left, right) in zip(a, b) where !PythonText.areEqual(left, right) {
      return PythonText.isOrdered(left, before: right)
    }
    return a.count < b.count
  }

  private static func collect(
    directory: URL,
    components: [String],
    pruning pruned: Set<String>,
    into found: inout [SourceEntry]
  ) throws {
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    for name in names where !pruned.contains(name) {
      let path = directory.appendingPathComponent(name).path
      let type = try FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType
      let isDirectory = type == .typeDirectory
      let entryComponents = components + [name]
      found.append(SourceEntry(components: entryComponents, isDirectory: isDirectory))
      if isDirectory {
        try collect(
          directory: directory.appendingPathComponent(name),
          components: entryComponents,
          pruning: pruned,
          into: &found
        )
      }
    }
  }
}
