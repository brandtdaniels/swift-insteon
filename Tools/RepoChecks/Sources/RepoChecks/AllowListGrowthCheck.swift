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
      guard git.fileExists(ref: base, path: list.path) else {
        console.write("The base branch has no allow-list yet, so there's nothing to compare.")
        continue
      }

      let added: [String]
      let noun: String

      switch list.kind {
      case .lines:
        added = try git.diff(ref: base, path: list.path).split(separator: "\n", omittingEmptySubsequences: false)
          .map(String.init).filter(Self.isAddedLine)
        noun = "lines"
      case .entries(let columns):
        let head = try Self.entries(from: Self.readHead(root.appendingPathComponent(list.path)), columns: columns)
        let before = try Self.entries(from: git.show(ref: base, path: list.path), columns: columns)
        added = Self.subtracting(before, from: head)
        noun = "entries"
      }

      if added.isEmpty {
        console.write("The allow-list didn't grow.")
      } else {
        failed = true
        console.write("These \(noun) were added to \(list.path), which may only lose \(noun):")
        for line in added {
          console.write(line)
        }
        console.write(list.advice)
      }
    }

    return failed ? .failed : .passed
  }

  /// `grep -E '^\+[^+#]'`.
  private static func isAddedLine(_ line: String) -> Bool {
    let scalars = Array(line.unicodeScalars)
    return scalars.count >= 2 && scalars[0] == "+" && scalars[1] != "+" && scalars[1] != "#"
  }

  private static func readHead(_ url: URL) throws -> String {
    FileManager.default.fileExists(atPath: url.path) ? try TextFile.read(url) : ""
  }

  /// `grep -v -e '^#' -e '^$' | cut -fN | sort`.
  private static func entries(from text: String, columns: Int) -> [String] {
    PythonText.splitLines(text)
      .filter { !$0.isEmpty && !PythonText.hasPrefix($0, "#") }
      .map { AllowListFile.columns(of: $0).prefix(columns).joined(separator: "\t") }
      .sorted { byteOrdered($0, $1) }
  }

  private static func byteOrdered(_ a: String, _ b: String) -> Bool {
    a.utf8.lexicographicallyPrecedes(b.utf8)
  }

  /// `comm -13 BASE HEAD`: the lines of the head that the base doesn't have as many times.
  private static func subtracting(_ base: [String], from head: [String]) -> [String] {
    var counts: [String: Int] = [:]
    for line in base {
      counts[line, default: 0] += 1
    }
    var added: [String] = []
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
