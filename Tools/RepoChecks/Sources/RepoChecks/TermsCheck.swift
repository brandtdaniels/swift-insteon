import Foundation
import RepoCheckSupport

/// Checks the docs and comments for the terms CONVENTIONS.md rules out.
///
/// It reads Swift comments and Markdown, leaving out code spans, code blocks and string
/// literals, and reports each line that uses a ruled-out form with the form to use instead.
/// CONVENTIONS.md, which names the ruled-out forms, isn't read, and nor are other file types.
public struct TermsCheck: RepoCheck {
  public init() {}

  /// A ruled-out form, as a pattern in Python's syntax, and what to write instead.
  public static let rules: [(pattern: String, replacement: String)] = [
    (#"\bINSTEON\b"#, "Insteon"),
    (#"(?<![.\w/])[iI]2cs\b|\bI2CS\b"#, "i2CS"),
    (#"\b[Aa]cknowledgement"#, "acknowledgment"),
    (#"\b[Pp]ower [Ll]ine"#, "powerline"),
    (#"\b[Oo]n levels?\b"#, "on-level"),
    (#"\b(2242|2245) Hub\b"#, "Hub 2242, Hub 2245"),
    // A model in parentheses after a name. Models run from 2200 to 2999; a year in parentheses,
    // as in a citation, is fine.
    (#"\b[A-Za-z][\w-]* \(2[2-9]\d\d(?!\d)[A-Z0-9-]*[^)]*\)"#, "the name, then the model, without parentheses"),
    (#"\bAll-Link|\ball-link"#, "ALL-Link"),
    (#"(?<!ALL-)\b[Ll]ink database"#, "ALL-Link database"),
    (#"\bclean-up"#, "cleanup"),
    // A user's set of devices, names, scenes and schedules is a network; a house is only a place.
    (#"\b[Hh]ome (?:backup|name)\b"#, "network backup, network name"),
    (#"\b[Hh]ome's (?:scenes?|devices?|modem|Hub|network|backup|schedules?)\b"#, "the network's scenes, devices, modem and so on"),
    (#"\b[Ss]et button\b"#, "SET button"),
    (
      #"(?<!Insteon )(?<!Modem )(?<!Hub )\b[Dd]eveloper'?s? [Gg]uides?\b|\b[Tt]he guide\b"#,
      "the document's title, such as Insteon Developer's Guide"
    ),
    // Temporal wording ties the prose to when it was written, which a reader can't know. Say
    // what's true, as of no time. A parameter named `now` is fine, as in "- now: The time".
    (#"\b[Cc]urrently\b|\b[Pp]reviously\b"#, "what's true, without a time"),
    (#"\b[Nn]o longer\b"#, "what's true, without a time, such as doesn't"),
    (#"(?<!- )\b[Nn]ow\b(?!:)"#, "what's true, without a time"),
    (
      #"\b[Nn]ew (?:in|API|APIs|option|options|behavior|method|methods|parameter|parameters)\b|\b[Nn]ewly\b"#,
      "what's true, without a time, rather than what changed"
    )
  ]

  private let compiledRules = Self.rules.map { (PythonPattern(python: $0.pattern), $0.replacement) }
  private let fence = PythonPattern(python: #"^\s*(?:///?\s*)?(```|~~~)"#)
  private let codeSpan = PythonPattern(python: #"(`+).+?\1"#)
  private let stringLiteral = PythonPattern(python: #""(?:\\.|[^"\\])*""#)
  private let lineComment = PythonPattern(python: #"//.*$"#)

  public func run(in root: URL, console: Console) throws -> CheckStatus {
    let found = try problems(in: root)

    console.write(found.isEmpty ? "No ruled-out terms." : found.joined(separator: "\n"))

    return CheckStatus(findings: found)
  }

  /// Every ruled-out form in the Swift comments and Markdown under the root, one message each.
  public func problems(in root: URL) throws -> [String] {
    var found: [String] = []

    for entry in try SourceFiles.entries(under: root) {
      let name = entry.components[entry.components.count - 1]
      let suffix = PythonText.pathSuffix(name)

      if (suffix != ".swift" && suffix != ".md") || name == "CONVENTIONS.md" {
        continue
      }

      let text = try TextFile.read(entry.url(under: root))

      for (number, line) in prose(in: text, isMarkdown: suffix == ".md") {
        for (pattern, replacement) in compiledRules {
          if let match = pattern.search(line) {
            found.append("\(entry.relativePath):\(number): \(PythonRepr.of(match.text)): use \(replacement)")
          }
        }
      }
    }

    return found
  }

  /// Each line number and the prose on it: a Swift file's comments, or a Markdown file's text.
  public func prose(in text: String, isMarkdown: Bool) -> [(number: Int, text: String)] {
    var found: [(Int, String)] = []
    var inFence = false
    var inString = false

    for (offset, line) in PythonText.splitLines(text).enumerated() {
      let number = offset + 1

      if fence.match(line) != nil {
        inFence.toggle()
        continue
      }

      if isMarkdown {
        // Indented code blocks start with four spaces outside a list.
        if inFence || (PythonText.hasPrefix(line, "    ") && !startsLikeListItem(PythonText.lstrip(line))) {
          continue
        }

        found.append((number, codeSpan.replacingAll(in: line, with: "")))
        continue
      }

      if inString {
        inString = PythonText.count(of: "\"\"\"", in: line) == 0
        continue
      }

      let code = stringLiteral.replacingAll(in: line, with: "\"\"")

      if PythonText.count(of: "\"\"\"", in: code) % 2 == 1 {
        inString = true
        continue
      }

      if let comment = lineComment.search(code), !inFence {
        found.append((number, codeSpan.replacingAll(in: comment.text, with: "")))
      }
    }

    return found
  }

  private func startsLikeListItem(_ text: String) -> Bool {
    ["-", "*", "1", "2", "3", "4", "5", "6", "7", "8", "9"].contains { PythonText.hasPrefix(text, $0) }
  }
}
