import Foundation
import RepoCheckSupport

/// One change to a file under a tree.
public enum FileEdit: Equatable, Sendable {
  case write(path: String, data: Data)
  case remove(path: String)
  case makeDirectory(path: String)

  public var path: String {
    switch self {
    case .write(let path, _), .remove(let path), .makeDirectory(let path):
      return path
    }
  }
}

/// A copy of a repository that mutants are applied to and taken back from.
public final class MutableTree {
  /// Names left out of the copy: build products, version control and caches.
  public static let leftOut: Set<String> = [".build", ".git", ".swiftpm", "__pycache__", ".DS_Store"]

  private let scratch: ScratchDirectory

  /// The copy's root.
  public var root: URL { scratch.url }

  /// Copies the repository into a scratch directory, leaving out the entries `including` refuses.
  /// The directory is made from its resolved path, which is the one the Python scripts compute.
  public init(copying source: URL, including: (SourceEntry) -> Bool = { _ in true }) throws {
    scratch = try ScratchDirectory(prefix: "repo-check-tree", resolvingSymlinks: true)
    for entry in try SourceFiles.entries(under: source, pruning: Self.leftOut) where including(entry) {
      let destination = entry.url(under: scratch.url)
      try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
      if entry.isDirectory {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
      } else {
        try FileManager.default.copyItem(at: entry.url(under: source), to: destination)
      }
    }
  }

  /// The relative paths of the files under a directory of the tree, in path order.
  public func files(under directory: String) throws -> [String] {
    let base = scratch.url(for: directory)
    guard FileManager.default.fileExists(atPath: base.path) else {
      return []
    }
    return try SourceFiles.entries(under: base, pruning: [])
      .filter { !$0.isDirectory }
      .map { directory + "/" + $0.relativePath }
  }

  /// The contents of a file of the tree.
  public func read(_ path: String) throws -> Data {
    try Data(contentsOf: scratch.url(for: path))
  }

  /// Applies the edits and returns what takes them back.
  public func apply(_ edits: [FileEdit]) throws -> Undo {
    var steps: [Undo.Step] = []
    do {
      for edit in edits {
        let url = scratch.url(for: edit.path)
        let existing = try? Data(contentsOf: url)
        switch edit {
        case .write(_, let data):
          steps.append(.restoreFile(path: edit.path, contents: existing))
          try scratch.write(data, to: edit.path)
        case .remove:
          steps.append(.restoreFile(path: edit.path, contents: existing))
          try FileManager.default.removeItem(at: url)
        case .makeDirectory:
          steps.append(.removeDirectory(path: edit.path))
          try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        }
      }
    } catch {
      try? restore(Undo(steps: steps))
      throw error
    }
    return Undo(steps: steps)
  }

  /// Takes back what the edits did.
  public func restore(_ undo: Undo) throws {
    for step in undo.steps.reversed() {
      switch step {
      case .restoreFile(let path, let contents):
        if let contents {
          try scratch.write(contents, to: path)
        } else {
          try? FileManager.default.removeItem(at: scratch.url(for: path))
        }
      case .removeDirectory(let path):
        try? FileManager.default.removeItem(at: scratch.url(for: path))
      }
    }
  }

  /// What takes back a set of edits.
  public struct Undo {
    enum Step {
      case restoreFile(path: String, contents: Data?)
      case removeDirectory(path: String)
    }

    let steps: [Step]
  }
}

extension MutableTree {
  /// The relative paths of the files whose names end in one of the suffixes, in path order,
  /// leaving out those under a name in `skipping`.
  public func filesWithSuffixes(_ suffixes: [String], skipping: Set<String> = [".build", ".git"]) throws -> [String] {
    try SourceFiles.entries(under: root, pruning: skipping)
      .filter { entry in !entry.isDirectory && suffixes.contains { entry.components.last!.hasSuffix($0) } }
      .map(\.relativePath)
  }
}
