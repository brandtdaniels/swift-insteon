import Foundation

/// Mutants aimed at `check-device-neutral`: words from the tree's own catalog put into the
/// directories it reads, in the cases and settings that decide whether they are found, and
/// changes to the catalog and to the allow-list.
public enum DeviceNeutralMutations {
  static let catalogPath = "Packages/InsteonDeviceCatalog/Sources/InsteonDeviceCatalog/Resources/catalog.json"
  static let allowlistPath = "Scripts/check-device-neutral-allowlist.txt"
  static let directories = ["Packages/InsteonCore/", "Packages/InsteonCLI/", "Packages/InsteonTestSupport/Sources/InsteonLinkingTestSupport/"]

  /// Strings of the catalog the check takes words from, and words it leaves alone.
  static func vocabulary(from tree: MutableTree) throws -> [String] {
    let data = try tree.read(catalogPath)
    let catalog = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    var words: [String] = []
    for device in (catalog["devices"] as? [[String: Any]] ?? []).prefix(60) {
      words.append(contentsOf: [device["name"], device["model"]].compactMap { $0 as? String })
      words.append(contentsOf: (device["aliases"] as? [String] ?? []).prefix(2))
    }
    for set in (catalog["commandSets"] as? [[String: Any]] ?? []).prefix(40) {
      words.append(contentsOf: [set["id"]].compactMap { $0 as? String })
      for flag in (set["operatingFlags"] as? [[String: Any]] ?? []).prefix(3) {
        words.append(contentsOf: [flag["name"], flag["label"]].compactMap { $0 as? String })
      }
    }
    words += ["I/O Linc", "IOLinc", "IO Linc", "iolinc", "io linc", "heartbeat", "onLevel", "rampRate", "Beeper", "configuration", "grouped"]
    return words
  }

  static func caseVariants(_ word: String) -> [String] {
    [word, word.lowercased(), word.uppercased(), word.capitalized, word.replacingOccurrences(of: " ", with: "")]
  }

  static func sourceOperators(words: [String]) -> [TextOperator] {
    let suffixes = ["", "s", "_", "2", "Way", "x", "\u{301}", "\u{E9}", "-", "."]
    return [
      TextOperator("insertWord") { lines, generator in
        guard !lines.isEmpty else { return false }
        let word = caseVariants(words.randomElement(using: &generator)!).randomElement(using: &generator)!
        lines.insert(["// \(word)", "let x = \"\(word)\"", "\(word)", "/// A \(word), then.", "`\(word)`"].randomElement(using: &generator)!, at: Int.random(in: 0...lines.count, using: &generator))
        return true
      },
      TextOperator("insertWordInIdentifier") { lines, generator in
        let word = words.randomElement(using: &generator)!
        let around = ["pre\(word)", "\(word)suffix", "_\(word)", "\(word)_", "x\(word)y", "9\(word)", "\(word)9", "\(word)\(suffixes.randomElement(using: &generator)!)"]
          .randomElement(using: &generator)!
        lines.insert("let a = \(around)", at: Int.random(in: 0...lines.count, using: &generator))
        return true
      },
      TextOperator("repeatWordLater") { lines, generator in
        guard !lines.isEmpty else { return false }
        let word = words.randomElement(using: &generator)!
        lines.insert("// \(word)", at: Int.random(in: 0...lines.count, using: &generator))
        lines.insert("// \(word) again", at: Int.random(in: 0...lines.count, using: &generator))
        return true
      }
    ] + CommonOperators.all
  }

  static let catalogOperators: [TextOperator] = [
    TextOperator("renameString") { lines, generator in
      guard let index = lines.randomIndex(using: &generator, where: { $0.contains("\"name\": \"") || $0.contains("\"label\": \"") || $0.contains("\"id\": \"") }) else { return false }
      let value = ["Zeta Relay", "\u{C9}clair", "pulseZ", "Garden Relay", "HEARTBEAT", "StraSSe", "Stra\u{DF}e", "I/O Linc", "x y"].randomElement(using: &generator)!
      guard let changed = lines[index].replacingFirst(of: "(?<=\": \")[^\"]*", with: value) else { return false }
      lines[index] = changed
      return true
    },
    TextOperator("dropLine") { lines, generator in
      guard let index = lines.randomIndex(using: &generator, where: { $0.contains("\"commandSet\"") || $0.contains("\"kind\"") }) else { return false }
      lines.remove(at: index)
      return true
    },
    TextOperator("swapKind") { lines, generator in
      guard let index = lines.randomIndex(using: &generator, where: { $0.contains("\"kind\": \"") }),
        let changed = lines[index].replacingFirst(of: "(?<=\"kind\": \")[^\"]*", with: ["modem", "hub", "onOff", "dimmer"].randomElement(using: &generator)!)
      else { return false }
      lines[index] = changed
      return true
    },
    TextOperator("emptyAString") { lines, generator in
      guard let index = lines.randomIndex(using: &generator, where: { $0.contains("\"name\": \"") }),
        let changed = lines[index].replacingFirst(of: "(?<=\"name\": \")[^\"]*", with: "")
      else { return false }
      lines[index] = changed
      return true
    }
  ]

  static let allowListOperators =
    CodeMutations.allowListOperators(
      columns: 3,
      samples: [
        ["Packages/InsteonCore/Sources/InsteonCore/X.swift", "pulse", "A reason."],
        ["Packages/InsteonCLI/README.md", "IOLinc", "Another."],
        ["Packages/Nope/x", "Zeta", "r"]
      ]
    ) + CommonOperators.all

  public static func generator(tree: MutableTree) throws -> MutantGenerating {
    let words = try vocabulary(from: tree)
    let sources = try tree.filesWithSuffixes([""]).filter { path in directories.contains { path.hasPrefix($0) } }
    return WeightedMutations([
      (try TextFileMutations(tree: tree, paths: sources, operators: sourceOperators(words: words)), 8),
      (try TextFileMutations(tree: tree, paths: [catalogPath], operators: catalogOperators), 1),
      (try TextFileMutations(tree: tree, paths: [allowlistPath], operators: allowListOperators), 1)
    ])
  }
}
