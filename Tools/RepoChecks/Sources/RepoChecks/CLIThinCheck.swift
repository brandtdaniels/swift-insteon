import Foundation
import RepoCheckSupport

/// A line of the command's sources that breaks a rule.
public struct CLIThinViolation: Equatable {
  /// The path from the source directory's parent, such as `insteon/DeviceCommands.swift`.
  public let path: String
  public let rule: String
  /// The line's code with its whitespace collapsed, as the allow-list holds it.
  public let code: String
  public let line: Int
}

/// Checks that the `insteon` command and the apps' shared sources stay a thin layer over the libraries.
///
/// The command parses arguments, prompts and prints; what a device is and how to control it
/// comes from the Insteon device catalog through the libraries. So its sources mustn't compare a
/// device's category, subcategory, firmware version, engine or group kind, and mustn't hold
/// protocol bytes or command numbers: hexadecimal literals, decimal command bytes, or the
/// protocol's command enumerations. A comparison with `nil` only asks whether a value is known,
/// so it's allowed.
///
/// A line that's in the allow-list is known and waits to move into the libraries; any other is
/// new, and so is a failure. An allow-list entry that matches nothing is a failure
/// too, so the list only shrinks.
public struct CLIThinCheck: RepoCheck {
  /// The directories to read; the command and its support library under the root by default.
  public var sources: [URL]?

  /// The known lines; `Scripts/check-cli-thin-allowlist.txt` under the root by default.
  public var allowlist: URL?

  /// Whether to write the allow-list from the sources instead of checking them.
  public var update: Bool

  public init(sources: [URL]? = nil, allowlist: URL? = nil, update: Bool = false) {
    self.sources = sources
    self.allowlist = allowlist
    self.update = update
  }

  // The raw passthroughs, `insteon device ADDRESS send` and `insteon modem send`, send bytes as
  // the person typed them, so they hold protocol bytes by design. Only the rules about bytes and
  // command numbers are waived for them; they still mustn't compare identities.
  static let passthroughFiles: Set<String> = ["ExploreCommands.swift"]

  // A comparison: ==, !=, <=, >=, ~=, or < or > with spaces around them, so `->` and generics
  // aren't comparisons.
  private static let comparison = #"(?:==|!=|<=|>=|~=|\s<\s|\s>\s)"#

  // What may follow a value before it's compared: an optional's `?`, and its `.rawValue`.
  private static let raw = #"\??(?:\.rawValue)?\??"#

  private static let kinds = #"(?:dimmer|relay|fan|sensor|button)"#

  private static let nilComparison = PythonPattern(python: #"\s*(?:==|!=)\s*nil\b|\bnil\s*(?:==|!=)\s*"#)

  struct Rule {
    let name: String
    let pattern: PythonPattern
    let waivedForPassthrough: Bool
    let advice: String
  }

  static let rules: [Rule] = {
    let c = comparison
    let r = raw
    let k = kinds
    return [
      Rule(
        name: "category",
        pattern: PythonPattern(
          python: #"\w*[cC]ategory"# + r + #"\s*"# + c + #"|"# + c + #"\s*[\w.?]*[cC]ategory\b"#
            + #"|\bcase\s+\.(?:dimmableLightingControl|switchedLightingControl)\b"#
            + #"|\bswitch\s+[\w.?]*[cC]ategory\b"#
            + #"|\.contains\(\s*[\w.?]*[cC]ategory\b"#
        ),
        waivedForPassthrough: false,
        advice: "ask the libraries what the device can do, such as a Device's capabilities"
      ),
      Rule(
        name: "firmware",
        pattern: PythonPattern(
          python: #"\w*[fF]irmware\w*"# + r + #"\s*(?:\?\?\s*[\w.]+\)?\s*)?"# + c + #"|"# + c + #"\s*[\w.?]*[fF]irmware\w*"#
        ),
        waivedForPassthrough: false,
        advice: "let the Insteon device catalog choose by firmware version"
      ),
      Rule(
        name: "group-kind",
        pattern: PythonPattern(
          python: #"\bkind"# + r + #"\s*(?:==|!=)"#
            + #"|(?:==|!=)\s*[\w.?]*\bkind\b"#
            + #"|(?:==|!=)\s*\."# + k + #"\b"#
            + #"|\bcase\s+\."# + k + #"\b"#
            + #"|\.contains\(\s*[\w.?]*\bkind\b"#
            + #"|\[\s*\."# + k + #"\b"#
            + #"|\bmainGroupType\b|\bGroupType\.Kind\b"#
        ),
        waivedForPassthrough: false,
        advice: "ask the libraries what the group can do, such as DeviceGroup.canDim"
      ),
      Rule(
        name: "engine",
        pattern: PythonPattern(python: #"(?:==|!=)\s*\.(?:i1|i2|i2cs|i3)\b|\bcase\s+\.(?:i1|i2|i2cs|i3)\b"#),
        waivedForPassthrough: false,
        advice: "let the libraries choose the form a message takes for the device's engine"
      ),
      Rule(
        name: "hex-literal",
        pattern: PythonPattern(python: #"\b0[xX][0-9A-Fa-f]+\b"#),
        waivedForPassthrough: true,
        advice: "name the command or value in a library, or take it from the catalog"
      ),
      Rule(
        name: "command-byte",
        pattern: PythonPattern(python: #"\bcommand[12]\s*:\s*\d+\b(?!\.)"#),
        waivedForPassthrough: true,
        advice: "name the command or value in a library, or take it from the catalog"
      ),
      Rule(
        name: "protocol-command",
        pattern: PythonPattern(python: #"\b(?:StandardDirectCommand|ExtendedDirectCommand)\b"#),
        waivedForPassthrough: true,
        advice: "call a library operation, such as Device.turnOn(level:group:)"
      )
    ]
  }()

  static let allowlistHeader = """
    # Lines of the `insteon` command that `repo-check cli-thin` knows break its rules, waiting
    # to move into the libraries. Each entry is a path under Packages/InsteonCLI/Sources, the rule,
    # and the line's code without comments or strings, separated by tabs. Entries only go: a
    # change that moves code into the libraries removes them, with --update, and CI fails a pull
    # request that adds one.

    """

  public func run(in root: URL, console: Console) throws -> CheckStatus {
    let sources = sources ?? Self.defaultSources(in: root)
    let allowlist = allowlist ?? Self.defaultAllowlist(in: root)
    let found = try Self.violations(in: sources)

    if update {
      let lines = found.map { "\($0.path)\t\($0.rule)\t\($0.code)" }
      try AllowListFile.write(header: Self.allowlistHeader, lines: lines, to: allowlist)
      console.write("Wrote \(found.count) known lines to \(allowlist.path).")
      return .passed
    }

    let allowed = try Self.readAllowlist(at: allowlist)
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
      console.write("  The insteon command doesn't decide what a device does: \(advice[violation.rule]!).")
    }

    for (entry, count) in remaining.counts.sorted(by: { AllowListFile.isOrdered($0.key.columns, before: $1.key.columns) }) where count > 0 {
      failed = true
      console.write("\(allowlist.lastPathComponent): no longer found, so remove it: \(entry.path)\t\(entry.rule)\t\(entry.code)")
    }

    if failed {
      return .failed
    }

    console.write(
      "The insteon command stays thin: no new lines break the rules (\(allowed.total) known, in \(allowlist.lastPathComponent))."
    )
    return .passed
  }

  /// The directories read by default.
  static func defaultSources(in root: URL) -> [URL] {
    let command = ["insteon", "InsteonCLISupport"].map {
      root.appendingPathComponent("Packages/InsteonCLI/Sources/\($0)", isDirectory: true)
    }
    return command + appSources(in: root)
  }

  /// The shared sources of each app under `Apps`, which are user interfaces held to the same rules.
  static func appSources(in root: URL) -> [URL] {
    let apps = root.appendingPathComponent("Apps", isDirectory: true)
    let names = (try? FileManager.default.contentsOfDirectory(atPath: apps.path)) ?? []
    return names.sorted().flatMap { app -> [URL] in
      let sources = apps.appendingPathComponent("\(app)/Sources", isDirectory: true)
      let targets = (try? FileManager.default.contentsOfDirectory(atPath: sources.path)) ?? []
      return targets.sorted().map { sources.appendingPathComponent($0, isDirectory: true) }
    }
  }

  static func defaultAllowlist(in root: URL) -> URL {
    root.appendingPathComponent("Scripts/check-cli-thin-allowlist.txt")
  }

  struct Entry: Hashable {
    let path: String
    let rule: String
    let code: String

    var columns: [String] { [path, rule, code] }
  }

  /// The allow-list's entries, each as many times as it's listed.
  static func readAllowlist(at url: URL) throws -> EntryCounter<Entry> {
    var entries = EntryCounter<Entry>()

    for line in try AllowListFile.entryLines(at: url) {
      let parts = AllowListFile.columns(of: line, splits: 2)

      if parts.count != 3 {
        throw CheckFailure("\(url.path): not an entry, which is a path, a rule and code separated by tabs: \(line)")
      }

      entries.add(Entry(path: parts[0], rule: parts[1], code: parts[2]))
    }

    return entries
  }

  /// Each line that breaks a rule, in file order, by its path from its directory's parent.
  public static func violations(in roots: [URL]) throws -> [CLIThinViolation] {
    var found: [CLIThinViolation] = []

    for root in roots {
      guard FileManager.default.fileExists(atPath: root.path) else {
        continue
      }

      for entry in try SourceFiles.entries(under: root, pruning: []) where entry.components.last!.hasSuffix(".swift") {
        let relative = root.lastPathComponent + "/" + entry.relativePath
        let isPassthrough = passthroughFiles.contains(entry.components.last!)

        for line in SwiftCodeScanner.lines(in: try TextFile.read(entry.url(under: root))) {
          let checked = nilComparison.replacingAll(in: line.code, with: " ")

          for rule in rules {
            if isPassthrough && rule.waivedForPassthrough {
              continue
            }

            if rule.pattern.search(checked) != nil {
              found.append(
                CLIThinViolation(
                  path: relative,
                  rule: rule.name,
                  code: PythonText.collapsingWhitespace(line.code),
                  line: line.number
                )
              )
            }
          }
        }
      }
    }

    return found
  }
}
