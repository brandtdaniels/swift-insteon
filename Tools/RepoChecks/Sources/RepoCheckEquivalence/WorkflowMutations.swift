import Foundation
import RepoCheckSupport

/// Mutants of the workflow files, aimed at what `check-workflows` reads: the `uses:`,
/// `container:` and `image:` values, the version comments, `jobs:` and each job's keys.
public struct WorkflowMutations: MutantGenerating {
  private static let directory = ".github/workflows"

  private let paths: [String]
  private let originals: [String: String]

  /// Reads the tree's workflow files, which the mutants are made from.
  public init(tree: MutableTree) throws {
    paths = try tree.files(under: Self.directory)
    var originals: [String: String] = [:]
    for path in paths {
      originals[path] = String(decoding: try tree.read(path), as: UTF8.self)
    }
    self.originals = originals
  }

  public func makeMutant(in tree: MutableTree, using generator: inout SeededGenerator) throws -> Mutant {
    let roll = Int.random(in: 0..<10, using: &generator)

    if roll < 7, let path = paths.randomElement(using: &generator), let original = originals[path] {
      if let mutated = TextOperator.mutate(original, with: Self.textOperators, using: &generator) {
        var text = mutated.text
        var names = mutated.names
        if Int.random(in: 0..<12, using: &generator) == 0 {
          let ending = Bool.random(using: &generator) ? "\r\n" : "\r"
          text = text.replacingOccurrences(of: "\n", with: ending)
          names.append(ending == "\r" ? "loneCR" : "crlf")
        }
        return Mutant(
          description: "\(path): \(names.joined(separator: " + "))",
          edits: [.write(path: path, data: Data(text.utf8))]
        )
      }
    }

    return structural(using: &generator)
  }

  private func structural(using generator: inout SeededGenerator) -> Mutant {
    let base = Self.directory + "/"
    let source = paths.first.flatMap { originals[$0] } ?? "jobs:\n"

    switch Int.random(in: 0..<7, using: &generator) {
    case 0:
      let name = ["extra.yaml", "z.yml", "a.yml", ".yml", ".yaml", "up.YML", "notes.txt", "x.yml.bak"]
        .randomElement(using: &generator)!
      let mutated = TextOperator.mutate(source, with: Self.textOperators, using: &generator)?.text ?? source
      return Mutant(description: "adds \(name), a mutated copy", edits: [.write(path: base + name, data: Data(mutated.utf8))])
    case 1:
      let path = paths.randomElement(using: &generator) ?? base + "ci.yml"
      return Mutant(description: "removes \(path)", edits: [.remove(path: path)])
    case 2:
      let path = paths.randomElement(using: &generator) ?? base + "ci.yml"
      var bytes = Array((originals[path] ?? source).utf8)
      bytes.insert(contentsOf: [0xFF], at: Int.random(in: 0...bytes.count, using: &generator))
      return Mutant(description: "\(path): puts a byte that isn't UTF-8 in the file", edits: [.write(path: path, data: Data(bytes))])
    case 3:
      return Mutant(description: "adds a directory named dir.yml", edits: [.makeDirectory(path: base + "dir.yml")])
    case 4:
      let path = paths.randomElement(using: &generator) ?? base + "ci.yml"
      return Mutant(description: "\(path): empties the file", edits: [.write(path: path, data: Data())])
    case 5:
      let path = paths.randomElement(using: &generator) ?? base + "ci.yml"
      let text = originals[path] ?? source
      return Mutant(
        description: "\(path): starts the file with a byte order mark",
        edits: [.write(path: path, data: Data([0xEF, 0xBB, 0xBF] + Array(text.utf8)))]
      )
    default:
      return Mutant(
        description: "removes every workflow",
        edits: paths.map { .remove(path: $0) }
      )
    }
  }

  // MARK: Operators

  static let textOperators: [TextOperator] = [
    TextOperator("shaToTag") { lines, generator in
      guard let index = lines.randomIndex(using: &generator, where: { $0.contains("uses:") }),
        let changed = lines[index].replacingFirst(of: "(?<=@)[0-9a-f]{40}", with: ["v4", "v4.4.0", "main", "11d5960", "latest"].randomElement(using: &generator)!)
      else { return false }
      lines[index] = changed
      return true
    },
    TextOperator("resizeSha") { lines, generator in
      guard let index = lines.randomIndex(using: &generator, where: { $0.contains("uses:") && $0.contains("@") }),
        let changed = lines[index].replacingFirst(
          of: "(?<=@)[0-9a-f]{40}",
          with: Bool.random(using: &generator) ? String(repeating: "a", count: Int.random(in: 1...39, using: &generator)) : String(repeating: "b", count: 41)
        )
      else { return false }
      lines[index] = changed
      return true
    },
    TextOperator("upperCaseSha") { lines, generator in
      guard let index = lines.randomIndex(using: &generator, where: { $0.contains("uses:") && $0.contains("@") }),
        let range = lines[index].range(of: "(?<=@)[0-9a-f]{40}", options: .regularExpression)
      else { return false }
      lines[index].replaceSubrange(range, with: lines[index][range].uppercased())
      return true
    },
    TextOperator("dropVersionComment") { lines, generator in
      guard let index = lines.randomIndex(using: &generator, where: { $0.contains("uses:") && $0.contains("#") }),
        let changed = lines[index].replacingFirst(of: "\\s*#.*$", with: "")
      else { return false }
      lines[index] = changed
      return true
    },
    TextOperator("rewordVersionComment") { lines, generator in
      let comments = [
        "# latest", "#v4", "#  4.4", "# v", "# v1.x", "# V4", "#1", "# version 4", "# v1.2.3-rc1", "# 4.4.0 (pinned)",
        "#\u{A0}v1", "#\u{2003}v1.2", "# v\u{661}", "# v1.2\u{301}", "# vv1", "#v1.", "# v1_2", "# v1.\u{E9}"
      ]
      guard let index = lines.randomIndex(using: &generator, where: { $0.contains("uses:") && $0.contains("#") }),
        let changed = lines[index].replacingFirst(of: "#.*$", with: comments.randomElement(using: &generator)!)
      else { return false }
      lines[index] = changed
      return true
    },
    TextOperator("dropTimeout") { lines, generator in
      guard let index = lines.randomIndex(using: &generator, where: { $0.contains("timeout-minutes:") }) else { return false }
      lines.remove(at: index)
      return true
    },
    TextOperator("moveTimeout") { lines, generator in
      guard let index = lines.randomIndex(using: &generator, where: { $0.contains("timeout-minutes:") }) else { return false }
      let shift = [-2, -1, 1, 2, 4].randomElement(using: &generator)!
      let spaces = lines[index].leadingSpaces
      lines[index] = String(repeating: " ", count: max(0, spaces + shift)) + lines[index].drop { $0 == " " }
      return true
    },
    TextOperator("emptyTimeout") { lines, generator in
      guard let index = lines.randomIndex(using: &generator, where: { $0.contains("timeout-minutes:") }) else { return false }
      lines[index] = lines[index].components(separatedBy: ":")[0] + [":", ": ", ":   ", ": # none", ":\u{A0}"].randomElement(using: &generator)!
      return true
    },
    TextOperator("indentWithTabs") { lines, generator in
      guard let index = lines.randomIndex(using: &generator, where: { $0.leadingSpaces > 0 }) else { return false }
      let spaces = lines[index].leadingSpaces
      let tabs = Bool.random(using: &generator) ? String(repeating: "\t", count: spaces / 2) : "\t"
      lines[index] = tabs + lines[index].dropFirst(spaces)
      return true
    },
    TextOperator("quoteValue") { lines, generator in
      guard let index = lines.randomIndex(using: &generator, where: { $0.contains("uses:") || $0.contains("image:") || $0.contains("container:") }),
        let colon = lines[index].range(of: ":")
      else { return false }
      let quote = ["'", "\"", "''", "\"'"].randomElement(using: &generator)!
      let rest = lines[index][colon.upperBound...].drop { $0 == " " }
      guard let end = rest.firstIndex(where: { $0 == " " || $0 == "#" }) ?? Optional(rest.endIndex) else { return false }
      let value = rest[..<end]
      guard !value.isEmpty else { return false }
      lines[index] = lines[index][..<colon.upperBound] + " " + quote + value + String(quote.reversed()) + rest[end...]
      return true
    },
    TextOperator("addJob") { lines, generator in
      guard let jobs = lines.firstIndex(of: "jobs:") else { return false }
      let shape = Int.random(in: 0..<5, using: &generator)
      var job = ["  extra:", "    runs-on: ubuntu-latest"]
      if shape != 0 { job.append("    timeout-minutes: 5") }
      if shape == 2 { job.insert("    timeout-minutes: 7", at: 1) }
      if shape == 3 { job += ["    steps:", "      - uses: actions/checkout@v4", "        timeout-minutes: 3"] }
      if shape == 4 { job += ["    container: ubuntu:22.04", "    services:", "      db:", "        image: postgres"] }
      let position = lines[(jobs + 1)...].firstIndex { !$0.isEmpty && !$0.hasPrefix(" ") && !$0.hasPrefix("#") } ?? lines.count
      lines.insert(contentsOf: job, at: Bool.random(using: &generator) ? jobs + 1 : position)
      return true
    },
    TextOperator("addRunLineWithUses") { lines, generator in
      guard let index = lines.randomIndex(using: &generator, where: { $0.contains("steps:") }) else { return false }
      let indent = String(repeating: " ", count: lines[index].leadingSpaces + 2)
      let added = [
        [indent + "- run: echo uses: actions/checkout@v4"],
        [indent + "- name: x", indent + "  run: |", indent + "    uses: actions/cache@v3", indent + "    image: redis:7"],
        [indent + "- run: echo \"container: swift:6\""],
        [indent + "- name: uses: nothing"]
      ].randomElement(using: &generator)!
      lines.insert(contentsOf: added, at: index + 1)
      return true
    },
    TextOperator("appendStep") { lines, generator in
      guard let index = lines.randomIndex(using: &generator, where: { $0.contains("steps:") }) else { return false }
      let indent = String(repeating: " ", count: lines[index].leadingSpaces + 2)
      let sha = String(repeating: "0123456789abcdef", count: 2) + "01234567"
      let step = [
        "- uses: docker://alpine:3.20",
        "- uses: docker://alpine:3.20@sha256:" + String(repeating: "ab", count: 32),
        "- uses: docker://alpine:3.20@sha256:" + String(repeating: "ab", count: 31),
        "- uses: ./local/action",
        "- uses: ./",
        "- uses: .github/actions/x@v1",
        "- uses: actions/x@\(sha) # v1",
        "-   uses:   actions/x@\(sha)   #v1.2",
        "- uses:actions/x@v1",
        "-uses: actions/x@v1",
        "- uses: actions/x@\(sha)#v1",
        "- uses: Actions/X.Y@\(sha) # v1",
        "- uses: a/b/c/d@\(sha) # v1",
        "- uses: /b@\(sha) # v1",
        "- uses: a@\(sha) # v1",
        "- uses: \u{E9}/x@\(sha) # v1",
        "- uses: a/x@\(sha) # v1 \u{2028}",
        "- name: n\n\(indent)  uses: x/y@v1",
        "- uses: ${{ matrix.action }}",
        "- uses: \"x/y@v1\"",
        "- uses: 'x/y@\(sha)' # v2",
        "- uses: x/y@v1 # v1",
        "  uses: x/y@v1",
        "- uses:",
        "- uses: # nothing"
      ].randomElement(using: &generator)!
      lines.insert(indent + step, at: index + 1)
      return true
    },
    TextOperator("deleteLine") { lines, generator in
      guard !lines.isEmpty else { return false }
      lines.remove(at: Int.random(in: 0..<lines.count, using: &generator))
      return true
    },
    TextOperator("duplicateLine") { lines, generator in
      guard !lines.isEmpty else { return false }
      let index = Int.random(in: 0..<lines.count, using: &generator)
      lines.insert(lines[index], at: index)
      return true
    },
    TextOperator("swapLines") { lines, generator in
      guard lines.count > 1 else { return false }
      lines.swapAt(Int.random(in: 0..<lines.count, using: &generator), Int.random(in: 0..<lines.count, using: &generator))
      return true
    },
    TextOperator("commentOut") { lines, generator in
      guard let index = lines.randomIndex(using: &generator, where: { !$0.isEmpty }) else { return false }
      let spaces = lines[index].leadingSpaces
      lines[index] = Bool.random(using: &generator)
        ? "#" + lines[index]
        : String(repeating: " ", count: spaces) + "# " + lines[index].dropFirst(spaces)
      return true
    },
    TextOperator("stripDigest") { lines, generator in
      guard let index = lines.randomIndex(using: &generator, where: { $0.contains("@sha256:") }) else { return false }
      let changed: String?
      switch Int.random(in: 0..<4, using: &generator) {
      case 0: changed = lines[index].replacingFirst(of: "@sha256:[0-9a-f]+", with: "")
      case 1: changed = lines[index].replacingFirst(of: "(?<=@sha256:)[0-9a-f]{64}", with: String(repeating: "0", count: Int.random(in: 0...63, using: &generator)))
      case 2: changed = lines[index].replacingFirst(of: "(?<=@sha256:)[0-9a-f]{64}", with: String(repeating: "A", count: 64))
      default: changed = lines[index].replacingFirst(of: "@sha256:", with: "@sha1:")
      }
      guard let changed else { return false }
      lines[index] = changed
      return true
    },
    TextOperator("expressionImage") { lines, generator in
      guard let index = lines.randomIndex(using: &generator, where: { $0.contains("container:") || $0.contains("image:") }),
        let colon = lines[index].firstIndex(of: ":")
      else { return false }
      let value = ["${{ matrix.image }}", "\"${{ x }}\"", "${{x}}@sha256:00", "$${{ x }}", "${ x }"].randomElement(using: &generator)!
      lines[index] = lines[index][...colon] + " " + value
      return true
    },
    TextOperator("bareContainer") { lines, generator in
      guard let index = lines.randomIndex(using: &generator, where: { $0.contains("container:") && !$0.hasSuffix(":") }),
        let colon = lines[index].firstIndex(of: ":")
      else { return false }
      let value = lines[index][lines[index].index(after: colon)...].drop { $0 == " " }
      let indent = String(repeating: " ", count: lines[index].leadingSpaces + 2)
      lines[index] = String(lines[index][...colon])
      lines.insert(indent + "image: " + value, at: index + 1)
      return true
    },
    TextOperator("unicodeNoise") { lines, generator in
      guard !lines.isEmpty else { return false }
      let noise = ["\u{E9}", "\u{A0}", "\u{2028}", "\u{85}", "\u{200B}", "\u{301}", "\u{1F600}", "\u{FEFF}", "\u{3000}", "\u{1C}", "\u{B}", "\u{C}", "\u{1680}", "\u{661}", "\u{2167}"]
        .randomElement(using: &generator)!
      let index = Int.random(in: 0..<lines.count, using: &generator)
      let scalars = Array(lines[index].unicodeScalars)
      let position = Int.random(in: 0...scalars.count, using: &generator)
      var view = String.UnicodeScalarView(scalars[..<position])
      view.append(contentsOf: noise.unicodeScalars)
      view.append(contentsOf: scalars[position...])
      lines[index] = String(view)
      return true
    },
    TextOperator("trailingSpace") { lines, generator in
      guard !lines.isEmpty else { return false }
      let index = Int.random(in: 0..<lines.count, using: &generator)
      lines[index] += [" ", "\t", "   ", "\u{A0}", "\u{3000}"].randomElement(using: &generator)!
      return true
    },
    TextOperator("jobsKey") { lines, generator in
      guard let index = lines.firstIndex(of: "jobs:") else { return false }
      lines[index] = ["jobs: ", "jobs:  # jobs", "\"jobs\":", "Jobs:", "jobs: {}", " jobs:", "jobs:\t", "jobs :", "jobs:\u{A0}"].randomElement(using: &generator)!
      return true
    },
    TextOperator("topLevelAfterJobs") { lines, generator in
      let added = [["env:", "  uses: a/b@v1"], ["permissions:", "  contents: read"], ["x: 1"], ["jobs:", "  again:", "    runs-on: x"], ["# end"]]
        .randomElement(using: &generator)!
      lines.append(contentsOf: added)
      return true
    },
    TextOperator("reindent") { lines, generator in
      guard let jobs = lines.firstIndex(of: "jobs:") else { return false }
      let extra = String(repeating: " ", count: Int.random(in: 1...3, using: &generator))
      let end = lines[(jobs + 1)...].firstIndex { !$0.isEmpty && !$0.hasPrefix(" ") && !$0.hasPrefix("#") } ?? lines.count
      for index in (jobs + 1)..<end where !lines[index].isEmpty {
        lines[index] = extra + lines[index]
      }
      return true
    },
    TextOperator("renameJob") { lines, generator in
      guard let index = lines.randomIndex(using: &generator, where: { $0.hasPrefix("  ") && $0.hasSuffix(":") && !$0.hasPrefix("   ") && !$0.contains("jobs") }) else { return false }
      lines[index] = lines[index] + [":", " # job", "\u{E9}", "  "].randomElement(using: &generator)!
      return true
    },
    TextOperator("blankLines") { lines, generator in
      lines.insert(contentsOf: Array(repeating: ["", "   ", "\t", "\u{A0}", "#"].randomElement(using: &generator)!, count: 2), at: Int.random(in: 0...lines.count, using: &generator))
      return true
    },
    TextOperator("dropFinalNewline") { lines, _ in
      guard lines.last == "" else { return false }
      lines.removeLast()
      return true
    },
    TextOperator("spaceAfterColon") { lines, generator in
      guard let index = lines.randomIndex(using: &generator, where: { $0.contains("uses: ") || $0.contains("image: ") || $0.contains("container: ") }) else { return false }
      let separator = ["", "\t", "  ", "\u{A0}", "\u{2003}"].randomElement(using: &generator)!
      guard let changed = lines[index].replacingFirst(of: "(uses|image|container): ", with: "$1:" + separator) else { return false }
      lines[index] = changed
      return true
    }
  ]
}
