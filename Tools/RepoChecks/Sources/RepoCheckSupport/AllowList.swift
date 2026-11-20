import Foundation

/// A multiset of allow-list entries, as the scripts' `collections.Counter` held them.
public struct EntryCounter<Key: Hashable> {
  public private(set) var counts: [Key: Int] = [:]

  public init() {}

  public mutating func add(_ key: Key) {
    counts[key, default: 0] += 1
  }

  public subscript(_ key: Key) -> Int {
    get { counts[key] ?? 0 }
    set { counts[key] = newValue }
  }

  /// The total of the counts.
  public var total: Int {
    counts.values.reduce(0, +)
  }
}

/// Reading and writing the allow-list files the checks share: a header of `#` lines, then one
/// entry per line with tab-separated columns.
public enum AllowListFile {
  /// The non-blank, non-comment lines of the file, or none if it doesn't exist.
  public static func entryLines(at url: URL) throws -> [String] {
    guard FileManager.default.fileExists(atPath: url.path) else {
      return []
    }
    return PythonText.splitLines(try TextFile.read(url)).filter {
      !PythonText.strip($0).isEmpty && !PythonText.hasPrefix($0, "#")
    }
  }

  /// `line.split("\t")`, or with at most `limit` splits like `line.split("\t", limit)`.
  public static func columns(of line: String, splits limit: Int? = nil) -> [String] {
    var parts: [String] = []
    var current = String.UnicodeScalarView()
    for scalar in line.unicodeScalars {
      if scalar == "\t", limit == nil || parts.count < limit! {
        parts.append(String(current))
        current = String.UnicodeScalarView()
      } else {
        current.append(scalar)
      }
    }
    parts.append(String(current))
    return parts
  }

  /// Writes the header and the lines, each ended by a newline.
  public static func write(header: String, lines: [String], to url: URL) throws {
    let body = header + lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    try Data(body.utf8).write(to: url)
  }

  /// Whether the first tuple of texts sorts before the second, element by element, by code point.
  public static func isOrdered(_ a: [String], before b: [String]) -> Bool {
    for (left, right) in zip(a, b) where !PythonText.areEqual(left, right) {
      return PythonText.isOrdered(left, before: right)
    }
    return a.count < b.count
  }
}
