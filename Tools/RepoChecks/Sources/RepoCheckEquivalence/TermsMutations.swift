import Foundation

/// Mutants aimed at `check-terms`: phrases the rules rule out, and phrases they allow, put into
/// comments, Markdown prose, code spans, fences, strings and block comments.
public enum TermsMutations {
  private static let phrases = [
    "INSTEON", "I2CS", "i2cs", "an acknowledgement", "power line", "Power Line", "on level", "on levels",
    "the 2242 Hub", "the PowerLinc Modem (2413U)", "Dimmer (2477D)", "Hub (2245)", "Bob (2010)", "an All-Link group",
    "all-link", "the link database", "ALL-Link database", "clean-up", "the Set button", "press Set button",
    "the guide", "Developer's guide", "Insteon Developer's Guide", "Hub Developers Guides", "currently",
    "Previously", "no longer", "now", "Now:", "- now: x", "a new option", "new API", "newly", "new link",
    "caf\u{E9} INSTEON", "\u{E9}INSTEON", "e\u{301}INSTEON", "INSTEON\u{301}", "INSTEON_", "_INSTEON", "x.i2cs",
    "/i2cs", "Insteon", "i2CS", "the clean-up of INSTEON now", "it's now", "\"INSTEON\"", "`INSTEON`",
    "``a`` INSTEON ``b``", "`unclosed INSTEON", "Set  button", "Set\tbutton", "All\u{2011}Link"
  ]

  private static let wrappers: [@Sendable (String) -> String] = [
    { "// \($0)" }, { "/// \($0)" }, { "//\($0)" }, { "let x = 1 // \($0)" }, { "let x = \"\($0)\"" },
    { "let x = \"a\" // \($0)" }, { "/* \($0) */" }, { "/* \($0)" }, { "\($0)" }, { "    \($0)" },
    { "- \($0)" }, { "* \($0)" }, { "1. \($0)" }, { "    - \($0)" }, { "> \($0)" }, { "# \($0)" },
    { "`\($0)`" }, { "``\($0)``" }, { "\"\"\"\($0)" }, { "\($0)\"\"\"" }, { "let y = \"\\\"\" // \($0)" },
    { "let y = #\"x\"# // \($0)" }, { "/// ```\n/// \($0)\n/// ```" }, { "```\n\($0)\n```" }, { "~~~\n\($0)\n~~~" },
    { "\"\"\"\n\($0)\n\"\"\"" }, { "\t\($0)" }, { "  /// \($0)" }, { "///\t\($0)" }
  ]

  public static let operators: [TextOperator] =
    [
      TextOperator("insertPhrase") { lines, generator in
        let phrase = phrases.randomElement(using: &generator)!
        let wrapped = wrappers.randomElement(using: &generator)!(phrase)
        lines.insert(wrapped, at: Int.random(in: 0...lines.count, using: &generator))
        return true
      },
      TextOperator("appendPhrase") { lines, generator in
        guard !lines.isEmpty else { return false }
        let index = Int.random(in: 0..<lines.count, using: &generator)
        lines[index] += [" ", "  // ", " /// ", " "].randomElement(using: &generator)! + phrases.randomElement(using: &generator)!
        return true
      },
      TextOperator("replaceWordWithPhrase") { lines, generator in
        guard let index = lines.indices.filter({ lines[$0].contains(" ") }).randomElement(using: &generator) else { return false }
        var words = lines[index].components(separatedBy: " ")
        words[Int.random(in: 0..<words.count, using: &generator)] = phrases.randomElement(using: &generator)!
        lines[index] = words.joined(separator: " ")
        return true
      }
    ] + CommonOperators.all
}
