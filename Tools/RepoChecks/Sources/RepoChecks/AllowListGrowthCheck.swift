import Foundation
import RepoCheckSupport

/// Checks that a pull request doesn't add to the allow-lists, which may only lose entries.
///
/// Each list is compared with its version at the base ref. For the cli-thin list, any added line
/// that isn't a comment is growth. For the others, an entry is its key columns, so rewording a
/// reason isn't growth, and an entry repeated more often than at the base is.
public struct AllowListGrowthCheck: RepoCheck {
  /// The ref to compare with, such as `origin/main`.
  public var base: String

  /// Where git answers from; the repository at the root by default.
  public var git: GitReading?

  public init(base: String, git: GitReading? = nil) {
    self.base = base
    self.git = git
  }

  private enum Kind {
    case lines
    case entries(keyColumns: Int)
  }

  private struct List {
    let path: String
    let kind: Kind
    let advice: String
  }

  private static let lists = [
    List(path: "Scripts/check-cli-thin-allowlist.txt", kind: .lines, advice: "Move the code into the libraries instead of allowing it."),
    List(
      path: "Scripts/check-concurrency-allowlist.txt",
      kind: .entries(keyColumns: 3),
      advice: "Keep the work structured and the clock injected instead of allowing it."
    ),
    List(
      path: "Scripts/check-credentials-allowlist.txt",
      kind: .entries(keyColumns: 2),
      advice: "Leave the credential out of the string instead of allowing it."
    ),
    List(
      path: "Scripts/check-device-neutral-allowlist.txt",
      kind: .entries(keyColumns: 2),
      advice: "Take the name from the catalog, or use an invented one, instead of allowing it."
    )
  ]

  public func run(in root: URL, console: Console) throws -> CheckStatus {
    let git = git ?? GitProcess(directory: root)
    var failed = false

    for list in Self.lists {
      guard try git.fileExists(ref: base, path: list.path) else {
        console.write("The base branch has no allow-list yet, so there's nothing to compare.")
        continue
      }

      let added: [[UInt8]]
      let noun: String

      switch list.kind {
      case .lines:
        added = Self.byteLines(try git.diff(ref: base, path: list.path)).filter(Self.isAddedLine)
        noun = "lines"
      case .entries(let columns):
        let head = Self.entries(from: Self.readHead(root.appendingPathComponent(list.path)), columns: columns)
        let before = Self.entries(from: try git.show(ref: base, path: list.path), columns: columns)
        added = Self.subtracting(before, from: head)
        noun = "entries"
      }

      if added.isEmpty {
        console.write("The allow-list didn't grow.")
      } else {
        failed = true
        console.write("These \(noun) were added to \(list.path), which may only lose \(noun):")
        for line in added {
          console.write(bytes: line)
        }
        console.write(list.advice)
      }
    }

    return failed ? .failed : .passed
  }

  /// `grep -E '^\+[^+#]'`, on bytes as grep reads them in the C locale.
  private static func isAddedLine(_ line: [UInt8]) -> Bool {
    line.count >= 2 && line[0] == 0x2B && line[1] != 0x2B && line[1] != 0x23
  }

  /// The file's bytes, or none if it's missing. The shell blocks read bytes, so a carriage return
  /// or a byte that isn't UTF-8 is part of a line, not an error.
  private static func readHead(_ url: URL) -> [UInt8] {
    (try? Array(Data(contentsOf: url))) ?? []
  }

  /// The lines of the bytes, split at each newline.
  private static func byteLines(_ bytes: [UInt8]) -> [[UInt8]] {
    bytes.split(separator: 0x0A, omittingEmptySubsequences: false).map(Array.init)
  }

  /// `grep -v -e '^#' -e '^$' | cut -fN | sort`, on bytes.
  private static func entries(from bytes: [UInt8], columns: Int) -> [[UInt8]] {
    byteLines(bytes)
      .filter { !$0.isEmpty && $0[0] != 0x23 }
      .map { line in
        Array(line.split(separator: 0x09, maxSplits: Int.max, omittingEmptySubsequences: false).prefix(columns).joined(separator: [0x09]))
      }
      .sorted { $0.lexicographicallyPrecedes($1) }
  }

  /// `comm -13 BASE HEAD`: the lines of the head that the base doesn't have as many times.
  private static func subtracting(_ base: [[UInt8]], from head: [[UInt8]]) -> [[UInt8]] {
    var counts: [[UInt8]: Int] = [:]
    for line in base {
      counts[line, default: 0] += 1
    }
    var added: [[UInt8]] = []
    for line in head {
      if let count = counts[line], count > 0 {
        counts[line] = count - 1
      } else {
        added.append(line)
      }
    }
    return added
  }
}
