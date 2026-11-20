import Foundation
import RepoCheckSupport

/// An async test without a time limit.
public struct MissingTimeLimit: Equatable {
  /// The file, from the repository's root or, outside it, from its root directory's parent.
  public let path: String
  public let line: Int
  public let name: String
}

/// Checks that every async test has a time limit.
///
/// An async test that waits on something that never comes, such as a clock that's never advanced,
/// hangs until CI's job limit rather than failing. So each `@Test` whose function is `async`
/// needs a `.timeLimit(...)` trait, in its own `@Test(...)` or in the `@Suite(...)` of a type that
/// encloses it. A test in an extension counts the `@Suite` of the extended type, when that type
/// is declared under one of the roots.
///
/// It reads the Swift files under `Packages/*/Tests` by default, leaving out comments and string
/// literals, and reports each async test without a time limit.
public struct TimeLimitsCheck: RepoCheck {
  /// The test directories to read; every package's `Tests` directory by default.
  public var roots: [URL]?

  /// The directory paths are shown from; the root given to `run` by default.
  public var repositoryRoot: URL?

  public init(roots: [URL]? = nil, repositoryRoot: URL? = nil) {
    self.roots = roots
    self.repositoryRoot = repositoryRoot
  }

  public func run(in root: URL, console: Console) throws -> CheckStatus {
    let found = try missing(in: root)

    for item in found {
      console.write("\(item.path):\(item.line): \(item.name) is async and has no time limit")
    }

    if !found.isEmpty {
      console.write(
        "\(found.count) async tests have no time limit. Add .timeLimit(.minutes(1)) to the test's "
          + "@Test(...) or to its type's @Suite(...), so a test that hangs fails instead."
      )
      return .failed
    }

    console.write("Every async test has a time limit.")
    return .passed
  }

  /// Each async test without a time limit, in file order.
  public func missing(in root: URL? = nil) throws -> [MissingTimeLimit] {
    let base = repositoryRoot ?? root
    let roots = try roots ?? Self.defaultRoots(in: root!)

    var files: [(root: URL, entry: SourceEntry, code: ScalarText)] = []

    for testsRoot in roots {
      guard FileManager.default.fileExists(atPath: testsRoot.path) else {
        continue
      }
      for entry in try SourceFiles.entries(under: testsRoot, pruning: []) where entry.components.last!.hasSuffix(".swift") {
        let text = try TextFile.read(entry.url(under: testsRoot))
        files.append((testsRoot, entry, SourceBlanker.blanked(ScalarText(text))))
      }
    }

    // Types declared under a `@Suite` with a time limit, by name, for the extensions of them.
    var limitedTypes = Set<String>()
    var scopesByFile: [[TypeScope]] = []

    for file in files {
      let scopes = TypeScope.scopes(in: file.code)
      scopesByFile.append(scopes)
      for scope in scopes where scope.hasTimeLimit {
        limitedTypes.insert(scope.name)
      }
    }

    var found: [MissingTimeLimit] = []

    for (index, file) in files.enumerated() {
      for test in TestFunction.tests(in: file.code) {
        if !test.isAsync || test.hasOwnLimit {
          continue
        }

        let enclosing = scopesByFile[index].filter { $0.start < test.position && test.position < $0.end }

        if enclosing.contains(where: { $0.hasTimeLimit || limitedTypes.contains($0.name) }) {
          continue
        }

        let line = file.code[0..<test.position].filter { $0 == "\n" }.count + 1
        found.append(MissingTimeLimit(path: Self.displayPath(file.root, file.entry, repositoryRoot: base), line: line, name: test.name))
      }
    }

    return found
  }

  /// A path from the repository's root, or from its root's parent outside the repository.
  static func displayPath(_ testsRoot: URL, _ entry: SourceEntry, repositoryRoot: URL?) -> String {
    if let repositoryRoot {
      let base = repositoryRoot.standardizedFileURL.path
      let full = entry.url(under: testsRoot).standardizedFileURL.path
      if full.hasPrefix(base + "/") {
        return String(full.dropFirst(base.count + 1))
      }
    }
    return testsRoot.lastPathComponent + "/" + entry.relativePath
  }

  /// Every package's `Tests` directory, in path order.
  static func defaultRoots(in root: URL) throws -> [URL] {
    let packages = root.appendingPathComponent("Packages")
    let names = (try? FileManager.default.contentsOfDirectory(atPath: packages.path)) ?? []
    return names
      .sorted { PythonText.isOrdered($0, before: $1) }
      .map { packages.appendingPathComponent($0).appendingPathComponent("Tests") }
      .filter { FileManager.default.fileExists(atPath: $0.path) }
  }
}

/// Source with its comments and the insides of its string literals turned into spaces.
enum SourceBlanker {
  /// The text with comments and the insides of string literals turned into spaces.
  ///
  /// Newlines are kept, and so is every other scalar's position, so an index into the result is
  /// an index into the text and line numbers match. A string's quotes are kept, and so is the
  /// code of its interpolations.
  static func blanked(_ text: ScalarText) -> ScalarText {
    var blanker = Blanker(text: text, output: text)
    _ = blanker.skipCode(from: 0, insideInterpolation: false)
    return blanker.output
  }

  private struct Blanker {
    let text: ScalarText
    var output: ScalarText

    mutating func blank(_ start: Int, _ end: Int) {
      var position = start
      while position < end {
        if output[position] != "\n" {
          output[position] = " "
        }
        position += 1
      }
    }

    /// The opening quotes of a string at the index, as the pattern `(#*)("""|")` finds them in
    /// the 64 scalars from the index: its `#` count and whether it is multiline, and the length.
    func opening(at index: Int) -> (hashes: Int, multiline: Bool, length: Int)? {
      let window = min(index + 64, text.count)
      var hashes = 0
      while index + hashes < window, text[index + hashes] == "#" {
        hashes += 1
      }
      guard index + hashes < window, text[index + hashes] == "\"" else {
        return nil
      }
      let quotes = index + hashes + 2 < window && text[index + hashes + 1] == "\"" && text[index + hashes + 2] == "\""
      return (hashes, quotes, hashes + (quotes ? 3 : 1))
    }

    /// Scans a string's contents from `start`; returns the index after its closing quotes.
    mutating func skipString(from start: Int, hashes: Int, multiline: Bool) -> Int {
      var index = start
      let hashRun = String(repeating: "#", count: hashes)
      let closing = (multiline ? "\"\"\"" : "\"") + hashRun
      let escape = "\\" + hashRun
      let escapeLength = escape.unicodeScalars.count

      while index < text.count {
        if text.starts(with: escape + "(", at: index) {
          blank(index, index + escapeLength + 1)
          index = skipCode(from: index + escapeLength + 1, insideInterpolation: true)
          continue
        }

        if text.starts(with: escape, at: index) {
          blank(index, min(index + escapeLength + 1, text.count))
          index += escapeLength + 1
          continue
        }

        if text.starts(with: closing, at: index) {
          return index + closing.unicodeScalars.count
        }

        if text[index] == "\n" && !multiline {
          return index
        }

        blank(index, index + 1)
        index += 1
      }

      return index
    }

    /// Scans code from `start`; inside an interpolation, stops after its closing parenthesis.
    mutating func skipCode(from start: Int, insideInterpolation: Bool) -> Int {
      var index = start
      var depth = 0

      while index < text.count {
        if text.starts(with: "//", at: index) {
          let end = text.find("\n", from: index) ?? text.count
          blank(index, end)
          index = end
          continue
        }

        if text.starts(with: "/*", at: index) {
          let commentStart = index
          var nesting = 0

          while index < text.count {
            if text.starts(with: "/*", at: index) {
              nesting += 1
              index += 2
            } else if text.starts(with: "*/", at: index) {
              nesting -= 1
              index += 2
              if nesting == 0 {
                break
              }
            } else {
              index += 1
            }
          }

          blank(commentStart, index)
          continue
        }

        if let opening = opening(at: index) {
          index = skipString(from: index + opening.length, hashes: opening.hashes, multiline: opening.multiline)
          continue
        }

        let character = text[index]

        if insideInterpolation {
          if character == "(" {
            depth += 1
          } else if character == ")" {
            if depth == 0 {
              return index + 1
            }
            depth -= 1
          }
        }

        index += 1
      }

      return index
    }
  }
}

/// The index after the bracket that closes the one at `index`, or the end of the code.
func balanced(_ code: ScalarText, at index: Int, opening: Unicode.Scalar = "(", closing: Unicode.Scalar = ")") -> Int {
  var depth = 0
  var position = index
  while position < code.count {
    if code[position] == opening {
      depth += 1
    } else if code[position] == closing {
      depth -= 1
      if depth == 0 {
        return position + 1
      }
    }
    position += 1
  }
  return code.count
}

private let modifiers = [
  "public", "package", "internal", "fileprivate", "private", "open", "final", "nonisolated", "indirect", "static",
  "mutating", "override", "required", "convenience"
]

/// The index after any attributes, with their arguments, and modifiers from `index`.
func skipAttributesAndModifiers(_ code: ScalarText, from start: Int) -> Int {
  var index = start

  while true {
    while index < code.count, PythonText.isSpace(code[index]) {
      index += 1
    }

    if index < code.count, code[index] == "@" {
      var end = index + 1
      while end < code.count, code[end].isPythonWord || code[end] == "." {
        end += 1
      }
      if end > index + 1 {
        index = end
        if code.starts(with: "(", at: index) {
          index = balanced(code, at: index)
        }
        continue
      }
    }

    if let end = modifierEnd(code, at: index) {
      index = end
      continue
    }

    return index
  }
}

/// Where a modifier at the index ends, as the pattern `MODIFIER(?:\(\w+\))?\b` matches it,
/// backtracking from a parenthesized part that isn't followed by a word boundary.
private func modifierEnd(_ code: ScalarText, at index: Int) -> Int? {
  for word in modifiers where code.starts(with: word, at: index) {
    let end = index + word.unicodeScalars.count

    if code.starts(with: "(", at: end) {
      var close = end + 1
      while close < code.count, code[close].isPythonWord {
        close += 1
      }
      if close > end + 1, code.starts(with: ")", at: close), code.isWordBoundary(at: close + 1) {
        return close + 1
      }
    }

    if code.isWordBoundary(at: end) {
      return end
    }
  }
  return nil
}

/// A type declaration or extension, and the span of its body.
struct TypeScope {
  let name: String
  let start: Int
  let end: Int
  let hasTimeLimit: Bool

  private static let keywords = ["struct", "class", "actor", "enum", "extension"]

  /// Each type declaration and extension in the code, with whether its `@Suite` has a time limit.
  static func scopes(in code: ScalarText) -> [TypeScope] {
    var scopes: [TypeScope] = []
    var position = 0

    while position < code.count {
      guard let found = declaration(in: code, at: position) else {
        position += 1
        continue
      }
      position = found.end

      // The declaration's attributes come after the end of the previous declaration or
      // statement, which is at most a line or two back; look back to the last brace.
      let before = max(code.findLast("{", before: found.start) ?? -1, code.findLast("}", before: found.start) ?? -1)
      let attributesStart = before + 1
      var start = attributesStart

      // Only attributes and modifiers may come between that point and the keyword; anything
      // else, such as `let x = 1` on an earlier line, ends before the attributes start.
      var offset = attributesStart
      while offset < found.start {
        if code[offset] == "\n" {
          let lineEnd = offset + 1
          if skipAttributesAndModifiers(code, from: start) < lineEnd,
            !PythonText.strip(code.text(start..<lineEnd)).isEmpty
          {
            start = lineEnd
          }
        }
        offset += 1
      }

      if skipAttributesAndModifiers(code, from: start) != found.start {
        continue
      }

      guard let body = code.find("{", from: found.end) else {
        continue
      }

      scopes.append(
        TypeScope(
          name: String(found.name.split(separator: ".", omittingEmptySubsequences: false).last!),
          start: body,
          end: balanced(code, at: body, opening: "{", closing: "}"),
          hasTimeLimit: suiteHasTimeLimit(code, from: start, to: found.start)
        )
      )
    }

    return scopes
  }

  /// The match of `\b(?:struct|class|actor|enum|extension)\s+([A-Za-z_][\w.]*)` at the position.
  private static func declaration(in code: ScalarText, at position: Int) -> (start: Int, end: Int, name: String)? {
    guard code.isWordBoundary(at: position) else {
      return nil
    }

    for keyword in keywords where code.starts(with: keyword, at: position) {
      var index = position + keyword.unicodeScalars.count
      let spaceStart = index
      while index < code.count, PythonText.isSpace(code[index]) {
        index += 1
      }
      guard index > spaceStart, index < code.count else {
        continue
      }
      let first = code[index]
      guard first == "_" || (first.isASCII && first.properties.isAlphabetic) else {
        continue
      }
      var end = index + 1
      while end < code.count, code[end].isPythonWord || code[end] == "." {
        end += 1
      }
      return (position, end, code.text(index..<end))
    }

    return nil
  }

  /// Whether a `@Suite(...)` among the attributes before a declaration sets a time limit.
  private static func suiteHasTimeLimit(_ code: ScalarText, from attributesStart: Int, to keywordStart: Int) -> Bool {
    var index = attributesStart

    while index < keywordStart {
      var found: Int?
      var search = index
      while let candidate = code.find("@Suite", from: search, before: keywordStart) {
        let end = candidate + 6
        if end >= keywordStart || !code[end].isPythonWord {
          found = candidate
          break
        }
        search = candidate + 1
      }

      guard let found else {
        return false
      }

      index = found + 6

      if code.starts(with: "(", at: index) {
        let end = balanced(code, at: index)

        if code.find("timeLimit(", from: index, before: end) != nil {
          return true
        }

        index = end
      }
    }

    return false
  }
}

/// A `@Test` function.
struct TestFunction {
  let name: String
  let isAsync: Bool
  let hasOwnLimit: Bool
  let position: Int

  /// Each `@Test` function in the code, in order.
  static func tests(in code: ScalarText) -> [TestFunction] {
    var found: [TestFunction] = []
    var position = 0

    while let start = code.find("@Test", from: position) {
      position = start + 5

      guard code.isWordBoundary(at: start + 5) else {
        continue
      }

      var index = start + 5
      var arguments = ScalarText()

      if code.starts(with: "(", at: index) {
        let end = balanced(code, at: index)
        arguments = Array(code[index..<end])
        index = end
      }

      index = skipAttributesAndModifiers(code, from: index)

      guard let function = functionName(in: code, at: index) else {
        continue
      }

      index = function.end

      if code.starts(with: "<", at: index) {
        index = balanced(code, at: index, opening: "<", closing: ">")
      }

      guard let open = code.find("(", from: index) else {
        continue
      }

      let parametersEnd = balanced(code, at: open)
      let body = code.find("{", from: parametersEnd)
      let effectsEnd = body ?? code.count
      var effects = ScalarText(code[parametersEnd..<max(parametersEnd, effectsEnd)])

      // The effects come before any return type, which may be a closure type that's async.
      if let arrow = effects.find("->") {
        effects = Array(effects[..<arrow])
      }

      found.append(
        TestFunction(
          name: function.name,
          isAsync: containsWord("async", in: effects),
          hasOwnLimit: arguments.find("timeLimit(") != nil,
          position: start
        )
      )
    }

    return found
  }

  /// The match of ``func\s+(\w+|`[^`]+`)\s*`` at the index.
  private static func functionName(in code: ScalarText, at index: Int) -> (name: String, end: Int)? {
    guard code.starts(with: "func", at: index) else {
      return nil
    }
    var position = index + 4
    let spaceStart = position
    while position < code.count, PythonText.isSpace(code[position]) {
      position += 1
    }
    guard position > spaceStart, position < code.count else {
      return nil
    }

    var nameEnd = position
    if code[position].isPythonWord {
      while nameEnd < code.count, code[nameEnd].isPythonWord {
        nameEnd += 1
      }
    } else if code[position] == "`" {
      nameEnd = position + 1
      while nameEnd < code.count, code[nameEnd] != "`" {
        nameEnd += 1
      }
      guard nameEnd < code.count, nameEnd > position + 1 else {
        return nil
      }
      nameEnd += 1
    } else {
      return nil
    }

    let name = code.text(position..<nameEnd)
    while nameEnd < code.count, PythonText.isSpace(code[nameEnd]) {
      nameEnd += 1
    }
    return (name, nameEnd)
  }

  private static func containsWord(_ word: String, in text: ScalarText) -> Bool {
    var from = 0
    while let found = text.find(word, from: from) {
      if text.isWordBoundary(at: found), text.isWordBoundary(at: found + word.unicodeScalars.count) {
        return true
      }
      from = found + 1
    }
    return false
  }
}
