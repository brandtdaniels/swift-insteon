import Foundation
import RepoCheckSupport

/// A library line that breaks a concurrency rule.
public struct ConcurrencyViolation: Equatable {
  /// The path under the packages directory.
  public let path: String
  public let rule: String
  /// The line's code with its whitespace collapsed, as the allow-list holds it.
  public let code: String
  public let line: Int
}

/// Checks the libraries for concurrency that escapes structure or a test's clock.
///
/// The libraries keep their work structured and their time on a clock the caller can replace,
/// so a canceled call stops what it started and a test's clock sets every timeout. So their
/// sources mustn't use an unstructured task (`Task { ... }`, `Task(priority:) { ... }` or
/// `Task.detached`), `@unchecked Sendable`, `Task.sleep`, or `ContinuousClock()` or
/// `SuspendingClock()` except as a parameter's default value.
///
/// It reads the Swift files under `Packages/*/Sources`, except the `insteon` command and the test
/// doubles in `InsteonTestSupport`. A line in the allow-list is known and has a reason; any
/// other is a failure. An entry that matches nothing is a failure too, so the list only shrinks.
public struct ConcurrencyCheck: RepoCheck {
  /// The packages directory, each package with a `Sources`; `Packages` under the root by default.
  public var packages: URL?

  /// The known lines; `Scripts/check-concurrency-allowlist.txt` under the root by default.
  public var allowlist: URL?

  /// Whether to write the allow-list from the sources instead of checking them.
  public var update: Bool

  public init(packages: URL? = nil, allowlist: URL? = nil, update: Bool = false) {
    self.packages = packages
    self.allowlist = allowlist
    self.update = update
  }

  // Sources that aren't library code: the command, and the test doubles.
  static let excluded: [[String]] = [["InsteonCLI", "Sources", "insteon"], ["InsteonTestSupport"]]

  private struct Rule {
    let name: String
    let breaks: @Sendable (String) -> Bool
    let advice: String
  }

  private static let unstructuredTask = PythonPattern(
    python: #"\bTask(?:<[^>{]*>)?\s*(?:\([^)]*\))?\s*\{|\bTask\.detached\b|\bTask\.init\b"#
  )
  private static let unchecked = PythonPattern(python: #"@unchecked\s+Sendable\b"#)
  private static let taskSleep = PythonPattern(python: #"\bTask\.sleep\b"#)
  private static let realClock = PythonPattern(python: #"\b(?:ContinuousClock|SuspendingClock)\(\)"#)
  // A parameter's default value: `name: Type = ContinuousClock()`, on a line that declares no
  // property.
  private static let defaultArgument = PythonPattern(python: #"\w+\s*:\s*[^=]+=\s*$"#)
  private static let declaration = PythonPattern(python: #"\b(?:let|var)\b"#)

  private static let rules: [Rule] = [
    Rule(
      name: "unstructured-task",
      breaks: { unstructuredTask.search($0) != nil },
      advice: "use structured concurrency, such as async let or a task group"
    ),
    Rule(
      name: "unchecked-sendable",
      breaks: { unchecked.search($0) != nil },
      advice: "make the type Sendable the compiler can check, such as an actor, or a Mutex's state"
    ),
    Rule(
      name: "task-sleep",
      breaks: { taskSleep.search($0) != nil },
      advice: "sleep on a clock the caller passes, such as clock.sleep(for:)"
    ),
    Rule(
      name: "real-clock",
      breaks: { code in
        realClock.allMatchPrefixes(in: code).contains { before in
          defaultArgument.search(before) == nil || declaration.search(before) != nil
        }
      },
      advice: "take the clock as a parameter, with ContinuousClock() as its default"
    )
  ]

  static let allowlistHeader = """
    # Lines of the libraries that `repo-check concurrency` knows break its rules, each with a
    # reason. Each entry is a path under Packages, the rule, the line's code without comments or
    # strings, and why it's needed, separated by tabs. Entries only go: CI fails a pull request
    # that adds one.

    """

  public func run(in root: URL, console: Console) throws -> CheckStatus {
    let packages = packages ?? root.appendingPathComponent("Packages", isDirectory: true)
    let allowlist = allowlist ?? root.appendingPathComponent("Scripts/check-concurrency-allowlist.txt")
    let found = try Self.violations(in: packages)

    if update {
      let reasons = FileManager.default.fileExists(atPath: allowlist.path) ? try Self.readAllowlist(at: allowlist).reasons : [:]
      let lines = found.map { "\($0.path)\t\($0.rule)\t\($0.code)\t\(reasons[Entry(path: $0.path, rule: $0.rule, code: $0.code)] ?? "")" }
      try AllowListFile.write(header: Self.allowlistHeader, lines: lines, to: allowlist)
      console.write("Wrote \(found.count) known lines to \(allowlist.path). Give each new one a reason.")
      return .passed
    }

    let allowed = try Self.readAllowlist(at: allowlist).entries
    var remaining = allowed
    let advice = Dictionary(uniqueKeysWithValues: Self.rules.map { ($0.name, $0.advice) })
    var failed = false

    for violation in found {
      let key = Entry(path: violation.path, rule: violation.rule, code: violation.code)

      if remaining[key] > 0 {
        remaining[key] -= 1
        continue
      }

      failed = true
      console.write("\(violation.path):\(violation.line): \(violation.rule): \(violation.code)")
      console.write("  Instead, \(advice[violation.rule]!).")
    }

    for (entry, count) in remaining.counts.sorted(by: { AllowListFile.isOrdered($0.key.columns, before: $1.key.columns) }) where count > 0 {
      failed = true
      console.write("\(allowlist.lastPathComponent): no longer found, so remove it: \(entry.path)\t\(entry.rule)\t\(entry.code)")
    }

    if failed {
      return .failed
    }

    console.write(
      "No new unstructured tasks, unchecked Sendable types or real clocks (\(allowed.total) known, in \(allowlist.lastPathComponent))."
    )
    return .passed
  }

  struct Entry: Hashable {
    let path: String
    let rule: String
    let code: String

    var columns: [String] { [path, rule, code] }
  }

  static func readAllowlist(at url: URL) throws -> (entries: EntryCounter<Entry>, reasons: [Entry: String]) {
    var entries = EntryCounter<Entry>()
    var reasons: [Entry: String] = [:]

    for line in try AllowListFile.entryLines(at: url) {
      let parts = AllowListFile.columns(of: line)

      if parts.count != 4 || PythonText.strip(parts[3]).isEmpty {
        throw CheckFailure("\(url.path): not an entry, which is a path, a rule, code and a reason separated by tabs: \(line)")
      }

      let key = Entry(path: parts[0], rule: parts[1], code: parts[2])
      entries.add(key)
      reasons[key] = parts[3]
    }

    return (entries, reasons)
  }

  /// Each line that breaks a rule, in file order, by its path under the packages directory.
  public static func violations(in packages: URL) throws -> [ConcurrencyViolation] {
    var found: [ConcurrencyViolation] = []

    for file in try swiftFiles(inSourcesUnder: packages) {
      if excluded.contains(where: { Array(file.components.prefix($0.count)) == $0 }) {
        continue
      }

      for line in SwiftCodeScanner.lines(in: try TextFile.read(file.url(under: packages))) {
        for rule in rules where rule.breaks(line.code) {
          found.append(
            ConcurrencyViolation(path: file.relativePath, rule: rule.name, code: PythonText.collapsingWhitespace(line.code), line: line.number)
          )
        }
      }
    }

    return found
  }

  /// The entries of `*/Sources/**/*.swift` under a directory, in path order.
  static func swiftFiles(inSourcesUnder packages: URL) throws -> [SourceEntry] {
    guard let packageNames = try? FileManager.default.contentsOfDirectory(atPath: packages.path) else {
      return []
    }

    var found: [SourceEntry] = []

    for name in packageNames {
      let sources = packages.appendingPathComponent(name).appendingPathComponent("Sources")
      var isDirectory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: sources.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        continue
      }

      for entry in try SourceFiles.entries(under: sources, pruning: []) where entry.components.last!.hasSuffix(".swift") {
        found.append(SourceEntry(components: [name, "Sources"] + entry.components, isDirectory: entry.isDirectory))
      }
    }

    return found.sorted { SourceFiles.isOrdered($0.components, before: $1.components) }
  }
}
