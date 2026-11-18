import Foundation
import RepoCheckSupport

/// A change to a text file, made on its lines.
public struct TextOperator: Sendable {
  public let name: String

  /// Changes the lines and says whether it could; a change that finds nothing to work on
  /// leaves the lines as they were and returns false.
  let apply: @Sendable (inout [String], inout SeededGenerator) -> Bool

  init(_ name: String, apply: @escaping @Sendable (inout [String], inout SeededGenerator) -> Bool) {
    self.name = name
    self.apply = apply
  }

  /// Applies one to three of the operators, chosen by the generator, to the text. Returns the
  /// changed text and the names of the operators that took effect, or nil if none did.
  public static func mutate(
    _ text: String,
    with operators: [TextOperator],
    using generator: inout SeededGenerator
  ) -> (text: String, names: [String])? {
    var lines = PythonText.splitLines(text)
    var names: [String] = []

    for _ in 0..<Int.random(in: 1...3, using: &generator) {
      for _ in 0..<8 {
        guard let candidate = operators.randomElement(using: &generator) else {
          break
        }
        var trial = lines
        if candidate.apply(&trial, &generator) {
          lines = trial
          names.append(candidate.name)
          break
        }
      }
    }

    guard !names.isEmpty else {
      return nil
    }
    return (lines.joined(separator: "\n"), names)
  }
}

extension Array where Element == String {
  /// A random index of a line the predicate accepts.
  func randomIndex(using generator: inout SeededGenerator, where predicate: (String) -> Bool) -> Int? {
    indices.filter { predicate(self[$0]) }.randomElement(using: &generator)
  }
}

extension String {
  /// The text with its first match of the regular expression replaced.
  func replacingFirst(of pattern: String, with replacement: String) -> String? {
    guard let range = range(of: pattern, options: .regularExpression) else {
      return nil
    }
    return replacingOccurrences(of: pattern, with: replacement, options: .regularExpression, range: range)
  }

  /// The number of leading spaces.
  var leadingSpaces: Int {
    prefix { $0 == " " }.count
  }
}
