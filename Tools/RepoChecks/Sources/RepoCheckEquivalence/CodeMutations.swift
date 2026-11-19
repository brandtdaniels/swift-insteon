import Foundation

/// Operators that put snippets of Swift, or of what a rule looks for, into source files in the
/// forms that hide or show them: bare, in comments, in strings, in interpolations, in raw and
/// multiline strings, and after other code.
public enum CodeMutations {
  /// How a snippet can be written into a source line.
  static let wrappers: [@Sendable (String) -> [String]] = [
    { [$0] }, { ["    \($0)"] }, { ["// \($0)"] }, { ["/// \($0)"] }, { ["let a = 1 // \($0)"] },
    { ["/* \($0) */"] }, { ["/* \($0)", "*/"] }, { ["/* a /* \($0) */ b */"] }, { ["/* a /* b */ \($0) */"] },
    { ["/* a /* b */ c */ \($0)"] },
    { ["let s = \"\($0)\""] }, { ["let s = \"a \\(\($0)) b\""] }, { ["let s = \"a \\(f(\($0))) b\""] },
    { ["let s = \"a \\(\"inner \\(\($0))\") b\""] },
    { ["let s = #\"\($0)\"#"] }, { ["let s = #\"a \\#(\($0)) b\"#"] }, { ["let s = ##\"\($0)\"# \"##"] },
    { ["let s = \"\"\"", "\($0)", "\"\"\""] }, { ["let s = \"\"\"", "a \\(\($0)) b", "\"\"\""] },
    { ["let s = #\"\"\"", "\($0)", "\"\"\"#"] }, { ["let s = \"a \\(", "\($0))\""] },
    { ["let s = \"a \\(\($0)"] }, { ["let s = \"a\\\"\" + \($0)"] }, { ["let s = \"\\\\\" // \($0)"] },
    { ["if \($0) { }"] }, { ["let c = \($0) // x"] }, { ["let c = \"q\"; \($0)"] }, { ["foo(\($0), \"\($0)\")"] },
    { ["\($0) \($0)"] }
  ]

  /// An operator that inserts one of the snippets, wrapped, at a random place.
  public static func insertSnippet(from snippets: [String], named name: String = "insertSnippet") -> TextOperator {
    TextOperator(name) { lines, generator in
      let snippet = snippets.randomElement(using: &generator)!
      let wrapped = wrappers.randomElement(using: &generator)!(snippet)
      lines.insert(contentsOf: wrapped, at: Int.random(in: 0...lines.count, using: &generator))
      return true
    }
  }

  /// An operator that appends one of the snippets to a random line.
  public static func appendSnippet(from snippets: [String], named name: String = "appendSnippet") -> TextOperator {
    TextOperator(name) { lines, generator in
      guard !lines.isEmpty else { return false }
      let index = Int.random(in: 0..<lines.count, using: &generator)
      lines[index] += [" ", "; ", " // ", " /* ", ", "].randomElement(using: &generator)! + snippets.randomElement(using: &generator)!
      return true
    }
  }

  /// Operators for the lines of an allow-list file: entries added, malformed, repeated or
  /// removed.
  public static func allowListOperators(columns: Int, samples: [[String]]) -> [TextOperator] {
    [
      TextOperator("addEntry") { lines, generator in
        let sample = samples.randomElement(using: &generator)!
        lines.insert(sample.joined(separator: "\t"), at: Int.random(in: 0...lines.count, using: &generator))
        return true
      },
      TextOperator("addMalformedEntry") { lines, generator in
        let sample = samples.randomElement(using: &generator)!
        let kept = sample.prefix(Int.random(in: 1..<max(2, columns), using: &generator))
        lines.insert(kept.joined(separator: "\t"), at: Int.random(in: 0...lines.count, using: &generator))
        return true
      },
      TextOperator("addSpacesEntry") { lines, generator in
        let sample = samples.randomElement(using: &generator)!
        lines.insert(sample.joined(separator: " "), at: Int.random(in: 0...lines.count, using: &generator))
        return true
      },
      TextOperator("addEmptyReason") { lines, generator in
        let sample = samples.randomElement(using: &generator)!
        lines.insert(sample.dropLast().joined(separator: "\t") + "\t   ", at: Int.random(in: 0...lines.count, using: &generator))
        return true
      }
    ]
  }
}
