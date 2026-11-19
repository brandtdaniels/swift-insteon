import Foundation
import RepoCheckSupport

/// A file that names a real product or operating flag.
public struct DeviceNeutralViolation: Equatable {
  /// The path from the repository's root.
  public let path: String
  public let word: String
  /// The line the word is first on in the file.
  public let line: Int
}

/// Checks that InsteonCore, the insteon command and the in-memory modem know no device.
///
/// What a device is and does comes from the Insteon device catalog, so the libraries a front end
/// uses, their command and their tests, sources and docs alike, don't name a real product or one
/// of its operating flags: a test builds an invented catalog with invented names instead. The
/// words ruled out come from the bundled catalog as the check runs, so they follow it:
///
/// - each device's name, aliases and model, apart from a modem's or a Hub's, which the libraries
///   talk through rather than control, matched with the case the catalog gives;
/// - each command set's id, apart from one only a modem's or a Hub's profile names, and each
///   operating flag's name and label and extended setting's name in every command set, matched
///   in any case;
/// - the words in `explicit`, product names the catalog doesn't spell that way, in any case.
///
/// Words that differ only in case are one word, so one use is one finding. A word in `generic`
/// is left out, in any case, since it's also a word of the protocol or of plain English. A word
/// matches only whole.
///
/// A file and word in the allow-list are known, and wait to be made neutral; any other is a
/// failure, and so is an entry that matches nothing.
public struct DeviceNeutralCheck: RepoCheck {
  /// The catalog the words come from; the bundled one under the root by default.
  public var catalog: URL?

  /// The known files and words; `Scripts/check-device-neutral-allowlist.txt` under the root by default.
  public var allowlist: URL?

  /// Whether to write the allow-list from the files instead of checking them.
  public var update: Bool

  public init(catalog: URL? = nil, allowlist: URL? = nil, update: Bool = false) {
    self.catalog = catalog
    self.allowlist = allowlist
    self.update = update
  }

  /// The directories read, from the root.
  static let checked = [
    "Packages/InsteonCore",
    "Packages/InsteonCLI",
    "Packages/InsteonTestSupport/Sources/InsteonLinkingTestSupport"
  ]

  // Products the catalog spells otherwise, ruled out too, in any case.
  static let explicit: Set<String> = ["I/O Linc", "IOLinc", "IO Linc"]

  // Words the catalog uses that are also the protocol's or plain English, so they're allowed, in
  // any case.
  static let generic: Set<String> = [
    // A message a battery-powered device sends, and its battery level.
    "heartbeat", "batterylevel",
    // The Get Operating Flags and Set Operating Flags commands' byte.
    "operatingflags",
    // A responder record's on-level and ramp rate, which every dimmer's link data names.
    "onlevel", "ramprate",
    // Plain English.
    "grouped", "configuration", "beeper"
  ]

  // A device the libraries talk through, rather than control, has one of these capabilities.
  static let transportCapabilities: Set<String> = ["modem", "hub"]

  static let allowlistHeader = """
    # Files that Scripts/check-device-neutral.py knows name a real product or operating flag, each
    # with a reason. Each entry is a path from the repository's root, the word, and why it stays,
    # separated by tabs. Entries only go: CI fails a pull request that adds one.

    """

  public func run(in root: URL, console: Console) throws -> CheckStatus {
    let catalog = catalog
      ?? root.appendingPathComponent("Packages/InsteonDeviceCatalog/Sources/InsteonDeviceCatalog/Resources/catalog.json")
    let allowlist = allowlist ?? root.appendingPathComponent("Scripts/check-device-neutral-allowlist.txt")
    let found = try Self.violations(in: root, words: try Self.forbiddenWords(catalog: catalog))

    if update {
      let reasons = try Self.readAllowlist(at: allowlist).reasons
      let lines = found.map { "\($0.path)\t\($0.word)\t\(reasons[Entry(path: $0.path, word: $0.word)] ?? "")" }
      try AllowListFile.write(header: Self.allowlistHeader, lines: lines, to: allowlist)
      console.write("Wrote \(found.count) known files and words to \(allowlist.path). Give each new one a reason.")
      return .passed
    }

    let allowed = try Self.readAllowlist(at: allowlist).entries
    var failed = false
    var seen = Set<Entry>()

    for violation in found {
      let key = Entry(path: violation.path, word: violation.word)
      seen.insert(key)

      if allowed.contains(key) {
        continue
      }

      failed = true
      console.write("\(violation.path):\(violation.line): names \(violation.word), a real product or operating flag")
      console.write("  Instead, take it from the catalog, or use an invented name in a test's own catalog.")
    }

    for entry in allowed.subtracting(seen).sorted(by: { AllowListFile.isOrdered($0.columns, before: $1.columns) }) {
      failed = true
      console.write("\(allowlist.lastPathComponent): no longer found, so remove it: \(entry.path)\t\(entry.word)")
    }

    if failed {
      return .failed
    }

    console.write("No real product or operating flag named (\(allowed.count) known, in \(allowlist.lastPathComponent)).")
    return .passed
  }

  struct Entry: Hashable {
    let path: String
    let word: String

    var columns: [String] { [path, word] }
  }

  static func readAllowlist(at url: URL) throws -> (entries: Set<Entry>, reasons: [Entry: String]) {
    var entries = Set<Entry>()
    var reasons: [Entry: String] = [:]

    for line in try AllowListFile.entryLines(at: url) {
      let parts = AllowListFile.columns(of: line)

      if parts.count != 3 || PythonText.strip(parts[2]).isEmpty {
        throw CheckFailure("\(url.path): not an entry, which is a path, a word and a reason separated by tabs: \(line)")
      }

      let key = Entry(path: parts[0], word: parts[1])
      entries.insert(key)
      reasons[key] = parts[2]
    }

    return (entries, reasons)
  }

  /// The words ruled out, from the catalog, with `explicit` and without `generic`.
  ///
  /// Each word is keyed by its first spelling found, and gives whether it matches in any case
  /// and every spelling the catalog has that differs from it only in case, sorted. A word matched
  /// in its own case matches each of its spellings.
  public static func forbiddenWords(catalog url: URL) throws -> [String: (anyCase: Bool, spellings: [String])] {
    let data = try Data(contentsOf: url)
    let catalog = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]

    // By case-folded form: the first spelling, whether any spelling matches in any case, and
    // every spelling.
    var folded: [String: (first: String, anyCase: Bool, spellings: Set<String>)] = [:]

    func add(_ value: Any?, anyCase: Bool) {
      guard let word = value as? String, !word.isEmpty else {
        return
      }
      let key = fold(word)
      if generic.contains(key) {
        return
      }
      var entry = folded[key] ?? (word, false, [])
      entry.anyCase = entry.anyCase || anyCase
      entry.spellings.insert(word)
      folded[key] = entry
    }

    for word in explicit.sorted(by: { PythonText.isOrdered($0, before: $1) }) {
      add(word, anyCase: true)
    }

    var transportSets = Set<String>()
    var otherSets = Set<String>()

    for device in catalog["devices"] as? [[String: Any]] ?? [] {
      let kinds = Set((device["capabilities"] as? [[String: Any]] ?? []).compactMap { $0["kind"] as? String })
      let named = Set((device["commandSets"] as? [[String: Any]] ?? []).compactMap { $0["commandSet"] as? String })

      if !kinds.isDisjoint(with: transportCapabilities) {
        transportSets.formUnion(named)
        continue
      }

      otherSets.formUnion(named)

      add(device["name"], anyCase: false)
      add(device["model"], anyCase: false)
      for alias in device["aliases"] as? [Any] ?? [] {
        add(alias, anyCase: false)
      }
    }

    let transportOnly = transportSets.subtracting(otherSets)

    for commandSet in catalog["commandSets"] as? [[String: Any]] ?? [] {
      if let id = commandSet["id"] as? String, !transportOnly.contains(id) {
        add(id, anyCase: true)
      } else if !(commandSet["id"] is String) {
        add(commandSet["id"], anyCase: true)
      }

      for flag in commandSet["operatingFlags"] as? [[String: Any]] ?? [] {
        add(flag["name"], anyCase: true)
        add(flag["label"], anyCase: true)
      }

      let settings = commandSet["extendedSettings"] as? [String: Any]
      for value in settings?["values"] as? [[String: Any]] ?? [] {
        add(value["name"], anyCase: true)
      }
    }

    return Dictionary(
      uniqueKeysWithValues: folded.values.map {
        ($0.first, ($0.anyCase, $0.spellings.sorted { PythonText.isOrdered($0, before: $1) }))
      }
    )
  }

  /// `str.casefold()`.
  static func fold(_ word: String) -> String {
    word.folding(options: [.caseInsensitive], locale: nil)
  }

  /// A pattern that finds any of a word's spellings whole: not inside a longer word, name or number.
  static func pattern(spellings: [String], anyCase: Bool) -> PythonPattern {
    let alternatives = spellings
      .enumerated()
      .sorted { left, right in
        let (a, b) = (left.element.unicodeScalars.count, right.element.unicodeScalars.count)
        return a != b ? a > b : left.offset < right.offset
      }
      .map { NSRegularExpression.escapedPattern(for: $0.element) }
      .joined(separator: "|")

    return PythonPattern("(?<![A-Za-z0-9_])(?:\(alternatives))(?![A-Za-z0-9_])", caseInsensitive: anyCase)
  }

  /// Each file and word found, with the line of its first use, in path and then word order.
  public static func violations(
    in root: URL,
    words: [String: (anyCase: Bool, spellings: [String])]
  ) throws -> [DeviceNeutralViolation] {
    let patterns = words.mapValues { pattern(spellings: $0.spellings, anyCase: $0.anyCase) }
    let sortedWords = words.keys.sorted { PythonText.isOrdered($0, before: $1) }
    var found: [DeviceNeutralViolation] = []

    for directory in checked {
      let base = root.appendingPathComponent(directory, isDirectory: true)

      guard FileManager.default.fileExists(atPath: base.path) else {
        continue
      }

      for entry in try SourceFiles.entries(under: base, pruning: []) where !entry.isDirectory {
        let file = entry.url(under: base)
        guard let text = try? TextFile.read(file) else {
          continue
        }

        let relative = directory + "/" + entry.relativePath

        for word in sortedWords {
          if let match = patterns[word]!.search(text) {
            found.append(DeviceNeutralViolation(path: relative, word: word, line: line(of: match, in: text)))
          }
        }
      }
    }

    return found.sorted {
      if !PythonText.areEqual($0.path, $1.path) { return PythonText.isOrdered($0.path, before: $1.path) }
      if !PythonText.areEqual($0.word, $1.word) { return PythonText.isOrdered($0.word, before: $1.word) }
      return $0.line < $1.line
    }
  }

  private static func line(of match: PythonPattern.Match, in text: String) -> Int {
    let prefix = PythonPattern.ns(text).substring(to: match.startOffset)
    return PythonText.count(of: "\n", in: prefix) + 1
  }
}
