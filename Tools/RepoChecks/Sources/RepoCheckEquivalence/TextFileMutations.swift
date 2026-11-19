import Foundation
import RepoCheckSupport

/// Mutants of text files of a tree, made by applying text operators to one file, with a share
/// of whole-file changes: a file added, removed, emptied, with a byte that isn't UTF-8, or with
/// a byte order mark.
public struct TextFileMutations: MutantGenerating {
  private let paths: [String]
  private let originals: [String: Data]
  private let operators: [TextOperator]
  private let addableNames: [String]
  private let addableDirectory: String

  /// - Parameters:
  ///   - paths: The files the mutants change, relative to the tree.
  ///   - operators: The changes made to a file's lines.
  ///   - addDirectory: The directory a mutant may add a copy of a file to, with the names
  ///     it may use; nil if no file is added.
  public init(
    tree: MutableTree,
    paths: [String],
    operators: [TextOperator],
    addDirectory: String? = nil,
    addNames: [String] = []
  ) throws {
    self.paths = paths
    var originals: [String: Data] = [:]
    for path in paths {
      originals[path] = try tree.read(path)
    }
    self.originals = originals
    self.operators = operators
    addableDirectory = addDirectory ?? ""
    addableNames = addDirectory == nil ? [] : addNames
  }

  public func makeMutant(in tree: MutableTree, using generator: inout SeededGenerator) throws -> Mutant {
    guard let path = paths.randomElement(using: &generator), let original = originals[path] else {
      return Mutant(description: "no change", edits: [])
    }
    let text = String(decoding: original, as: UTF8.self)

    switch Int.random(in: 0..<100, using: &generator) {
    case 0:
      return Mutant(description: "\(path): empties the file", edits: [.write(path: path, data: Data())])
    case 1:
      var bytes = Array(original)
      bytes.insert(0xFF, at: Int.random(in: 0...bytes.count, using: &generator))
      return Mutant(description: "\(path): puts a byte that isn't UTF-8 in the file", edits: [.write(path: path, data: Data(bytes))])
    case 2:
      return Mutant(
        description: "\(path): starts the file with a byte order mark",
        edits: [.write(path: path, data: Data([0xEF, 0xBB, 0xBF]) + original)]
      )
    case 3 where !addableNames.isEmpty:
      let name = addableNames.randomElement(using: &generator)!
      let mutated = TextOperator.mutate(text, with: operators, using: &generator)?.text ?? text
      return Mutant(
        description: "adds \(addableDirectory)/\(name), a mutated copy of \(path)",
        edits: [.write(path: "\(addableDirectory)/\(name)", data: Data(mutated.utf8))]
      )
    case 4 where !addableNames.isEmpty:
      return Mutant(description: "removes \(path)", edits: [.remove(path: path)])
    default:
      break
    }

    guard let mutated = TextOperator.mutate(text, with: operators, using: &generator) else {
      return Mutant(description: "\(path): no change", edits: [])
    }
    var result = mutated.text
    var names = mutated.names
    if Int.random(in: 0..<12, using: &generator) == 0 {
      let ending = Bool.random(using: &generator) ? "\r\n" : "\r"
      result = result.replacingOccurrences(of: "\n", with: ending)
      names.append(ending == "\r" ? "loneCR" : "crlf")
    }
    return Mutant(description: "\(path): \(names.joined(separator: " + "))", edits: [.write(path: path, data: Data(result.utf8))])
  }
}

/// Operators that suit any text file.
public enum CommonOperators {
  public static let all: [TextOperator] = [
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
    TextOperator("unicodeNoise") { lines, generator in
      guard !lines.isEmpty else { return false }
      let noise = unicodeNoise.randomElement(using: &generator)!
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
      lines[Int.random(in: 0..<lines.count, using: &generator)] += [" ", "\t", "   ", "\u{A0}", "\u{3000}"].randomElement(using: &generator)!
      return true
    },
    TextOperator("blankLines") { lines, generator in
      let blank = ["", "   ", "\t", "\u{A0}"].randomElement(using: &generator)!
      lines.insert(contentsOf: [blank, blank], at: Int.random(in: 0...lines.count, using: &generator))
      return true
    },
    TextOperator("insertAfterRandomLine") { lines, generator in
      guard !lines.isEmpty else { return false }
      lines.insert(contentsOf: snippets.randomElement(using: &generator)!, at: Int.random(in: 0...lines.count, using: &generator))
      return true
    }
  ]

  static let unicodeNoise = ["\u{E9}", "\u{A0}", "\u{2028}", "\u{85}", "\u{200B}", "\u{301}", "\u{1F600}", "\u{FEFF}", "\u{3000}", "\u{1C}", "\u{B}", "\u{C}", "\u{1680}", "\u{661}", "\u{2167}", "\u{130}", "\u{17F}"]

  private static let snippets: [[String]] = [
    ["```", "x", "```"], ["~~~"], ["\"\"\""], ["/*", "*/"], ["/* /* */"], ["#\"\"\""], ["\"\"\"#"], [""], ["}"], ["{"]
  ]
}
