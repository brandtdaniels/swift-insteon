import Foundation
import RepoCheckSupport

/// A line whose strings interpolate a credential's name.
public struct CredentialsViolation: Equatable {
  /// The path under the packages directory.
  public let path: String
  /// The names, sorted and joined with commas, or `CredentialsCheck.unclosed`.
  public let names: String
  public let line: Int
}

/// Checks the sources for credentials written into a string by interpolation.
///
/// A Hub's username and password, and any token or Authorization header, go only into the
/// request that needs them. Written into a string, such as `"\(password)"` in a message, a log
/// line or an error's description, they can end up on a screen or in a file. So no string in the
/// sources interpolates anything named for a credential: a name or a string literal inside the
/// interpolation, with a word that says so. Names are read as words split at capitals and
/// underscores, so `passwordPrompt` is read as "password prompt" and matches, and `tokenizer`
/// doesn't.
///
/// It reads the Swift files under `Packages/*/Sources`, the command included. A line in the
/// allow-list is known and has a reason; any other is a failure. An interpolation that isn't
/// closed on its line is a failure too, since the check can't read it. An entry that matches
/// nothing is a failure, so the list only shrinks.
public struct CredentialsCheck: RepoCheck {
  /// The packages directory, each package with a `Sources`; `Packages` under the root by default.
  public var packages: URL?

  /// The known lines; `Scripts/check-credentials-allowlist.txt` under the root by default.
  public var allowlist: URL?

  /// Whether to write the allow-list from the sources instead of checking them.
  public var update: Bool

  public init(packages: URL? = nil, allowlist: URL? = nil, update: Bool = false) {
    self.packages = packages
    self.allowlist = allowlist
    self.update = update
  }

  /// What a line with an interpolation that isn't closed on it is reported as. It can't be allowed.
  public static let unclosed = "(an interpolation not closed on its line)"

  // Words that say a name holds a credential, and pairs of words that do together.
  private static let credentialWords: Set<String> = [
    "password", "passwords", "passwd", "pwd", "passphrase",
    "token", "tokens", "secret", "secrets",
    "credential", "credentials", "creds",
    "authorization", "bearer", "apikey"
  ]

  private static let credentialPairs: Set<[String]> = [["api", "key"], ["private", "key"], ["access", "key"]]

  private static let word = PythonPattern(python: #"[A-Za-z_][A-Za-z0-9_]*"#)

  // A word's parts, split at underscores and capitals: `HUB_PASSWORD` is HUB and
  // PASSWORD, `apiKey` is api and Key, and `APIKey` is API and Key.
  private static let part = PythonPattern(python: #"[A-Z]+(?![a-z])|[A-Z]?[a-z]+|[0-9]+"#)

  /// Whether a word, such as a name, says it holds a credential.
  public static func isCredential(_ word: String) -> Bool {
    let split = part.allMatches(in: word).map { $0.lowercased() }

    return split.contains(where: credentialWords.contains)
      || zip(split, split.dropFirst()).contains { credentialPairs.contains([$0, $1]) }
  }

  static let allowlistHeader = """
    # Lines whose strings Scripts/check-credentials.py knows interpolate a name that looks like a
    # credential's, each with a reason. Each entry is a path under Packages, the names, separated
    # by commas, and why the line is safe, separated by tabs. Entries only go: CI fails a pull
    # request that adds one.

    """

  public func run(in root: URL, console: Console) throws -> CheckStatus {
    let packages = packages ?? root.appendingPathComponent("Packages", isDirectory: true)
    let allowlist = allowlist ?? root.appendingPathComponent("Scripts/check-credentials-allowlist.txt")
    let found = try Self.violations(in: packages)

    if update {
      let reasons = try Self.readAllowlist(at: allowlist).reasons
      let lines = found.filter { $0.names != Self.unclosed }.map {
        "\($0.path)\t\($0.names)\t\(reasons[Entry(path: $0.path, names: $0.names)] ?? "")"
      }
      try AllowListFile.write(header: Self.allowlistHeader, lines: lines, to: allowlist)
      console.write("Wrote \(found.count) known lines to \(allowlist.path). Give each new one a reason.")
      return .passed
    }

    let allowed = try Self.readAllowlist(at: allowlist).entries
    var remaining = allowed
    var failed = false

    for violation in found {
      let key = Entry(path: violation.path, names: violation.names)

      if violation.names == Self.unclosed {
        failed = true
        console.write("\(violation.path):\(violation.line): an interpolation isn't closed on its line, so the check can't read it")
        console.write("  Instead, keep each interpolation on one line, such as by naming its value first.")
        continue
      }

      if remaining[key] > 0 {
        remaining[key] -= 1
        continue
      }

      failed = true
      console.write("\(violation.path):\(violation.line): interpolates \(violation.names)")
      console.write("  Instead, leave the credential out of the string, such as by naming what it's for.")
    }

    for (entry, count) in remaining.counts.sorted(by: { AllowListFile.isOrdered($0.key.columns, before: $1.key.columns) }) where count > 0 {
      failed = true
      console.write("\(allowlist.lastPathComponent): no longer found, so remove it: \(entry.path)\t\(entry.names)")
    }

    if failed {
      return .failed
    }

    console.write("No credentials interpolated into strings (\(allowed.total) known, in \(allowlist.lastPathComponent)).")
    return .passed
  }

  struct Entry: Hashable {
    let path: String
    let names: String

    var columns: [String] { [path, names] }
  }

  static func readAllowlist(at url: URL) throws -> (entries: EntryCounter<Entry>, reasons: [Entry: String]) {
    var entries = EntryCounter<Entry>()
    var reasons: [Entry: String] = [:]

    for line in try AllowListFile.entryLines(at: url) {
      let parts = AllowListFile.columns(of: line)

      if parts.count != 3 || PythonText.strip(parts[2]).isEmpty {
        throw CheckFailure("\(url.path): not an entry, which is a path, names and a reason separated by tabs: \(line)")
      }

      let key = Entry(path: parts[0], names: parts[1])
      entries.add(key)
      reasons[key] = parts[2]
    }

    return (entries, reasons)
  }

  /// Each line whose strings interpolate a credential's name, in file order. A line with an
  /// interpolation that isn't closed on it has `unclosed` for its names.
  public static func violations(in packages: URL) throws -> [CredentialsViolation] {
    var found: [CredentialsViolation] = []

    for file in try ConcurrencyCheck.swiftFiles(inSourcesUnder: packages) {
      for line in SwiftCodeScanner.lines(in: try TextFile.read(file.url(under: packages))) {
        let names = word.allMatches(in: line.interpolations.joined(separator: " ")).filter(isCredential)

        if line.hasUnclosedInterpolation {
          found.append(CredentialsViolation(path: file.relativePath, names: unclosed, line: line.number))
        } else if !names.isEmpty {
          let sorted = Set(names).sorted { PythonText.isOrdered($0, before: $1) }
          found.append(CredentialsViolation(path: file.relativePath, names: sorted.joined(separator: ","), line: line.number))
        }
      }
    }

    return found
  }
}
