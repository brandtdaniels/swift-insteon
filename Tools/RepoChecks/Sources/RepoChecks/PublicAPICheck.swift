import Foundation
import RepoCheckSupport

/// Checks that InsteonCore's public declarations match the list committed beside the checks.
///
/// InsteonCore is what a front end, such as an app or the `insteon` command, builds on, so a
/// change to what it makes public is a change to every front end. The list holds one line per
/// public declaration, such as `struct ProductCatalogStore`, `func ProductCatalogStore.save(json:version:)`
/// or `case ProductCatalogStoreError.writeFailed`, so a pull request that adds, removes or
/// renames one shows it in the list's diff, where a reviewer sees it.
///
/// It reads the Swift files under `Packages/InsteonCore/Sources/InsteonCore`, leaving out
/// comments and string literals, and finds each declaration marked `public` or `open`, each
/// member of a `public` or `open` extension that doesn't say `internal`, `fileprivate`, `private`
/// or `package`, each requirement of a public protocol, and each case of a public enum. A
/// declaration in a type that isn't public is left out. A declaration a module opts into with
/// `@_spi(Name)` is listed with that attribute.
///
/// The list holds names, not whole signatures: functions, initializers, subscripts and enum
/// cases by their argument labels, and properties by name, with a setter that isn't public
/// marked.
public struct PublicAPICheck: RepoCheck {
  /// InsteonCore's sources; under the root by default.
  public var sources: URL?

  /// The committed list; `Scripts/insteoncore-public-api.txt` under the root by default.
  public var list: URL?

  /// Whether to write the list from the sources instead of checking them.
  public var update: Bool

  public init(sources: URL? = nil, list: URL? = nil, update: Bool = false) {
    self.sources = sources
    self.list = list
    self.update = update
  }

  static let listHeader = """
    # InsteonCore's public declarations, as `repo-check public-api` lists them. CI fails when the
    # sources and this list differ, so a change to InsteonCore's public API shows here in review.
    # After a deliberate change, run `repo-check public-api --update` and commit this
    # file with it.

    """

  public func run(in root: URL, console: Console) throws -> CheckStatus {
    let sources = sources ?? root.appendingPathComponent("Packages/InsteonCore/Sources/InsteonCore", isDirectory: true)
    let list = list ?? root.appendingPathComponent("Scripts/insteoncore-public-api.txt")
    let found = try Self.publicAPI(under: sources)

    if update {
      try AllowListFile.write(header: Self.listHeader, lines: found, to: list)
      console.write("Wrote \(found.count) public declarations to \(list.path).")
      return .passed
    }

    let listed = try Self.readList(at: list)
    let foundSet = Set(found)
    let listedSet = Set(listed)
    let added = foundSet.subtracting(listedSet).sorted { PythonText.isOrdered($0, before: $1) }
    let removed = listedSet.subtracting(foundSet).sorted { PythonText.isOrdered($0, before: $1) }

    for line in added {
      console.write("public, not in \(list.lastPathComponent): \(line)")
    }

    for line in removed {
      console.write("in \(list.lastPathComponent), not public: \(line)")
    }

    if !added.isEmpty || !removed.isEmpty {
      console.write(
        "InsteonCore's public API differs from its list. If the change is deliberate, run "
          + "`repo-check public-api --update` and commit the list with it."
      )
      return .failed
    }

    console.write("InsteonCore's public API matches its list (\(found.count) declarations, in \(list.lastPathComponent)).")
    return .passed
  }

  static func readList(at url: URL) throws -> [String] {
    guard FileManager.default.fileExists(atPath: url.path) else {
      return []
    }
    return PythonText.splitLines(try TextFile.read(url)).filter {
      !PythonText.strip($0).isEmpty && !PythonText.hasPrefix($0, "#")
    }
  }

  /// Every public declaration under a directory, sorted.
  public static func publicAPI(under sources: URL) throws -> [String] {
    var found = Set<String>()

    if FileManager.default.fileExists(atPath: sources.path) {
      for entry in try SourceFiles.entries(under: sources, pruning: []) where entry.components.last!.hasSuffix(".swift") {
        found.formUnion(declarations(in: try TextFile.read(entry.url(under: sources))))
      }
    }

    return found.sorted { PythonText.isOrdered($0, before: $1) }
  }

  // MARK: Reading declarations

  private static let typeKeywords: Set<String> = ["struct", "enum", "class", "actor", "protocol", "extension"]
  private static let declarationKeywords: Set<String> = typeKeywords.union([
    "func", "var", "let", "init", "subscript", "case", "typealias", "associatedtype"
  ])

  /// Modifiers that keep a member of a `public` extension from being public.
  private static let restricting: Set<String> = ["internal", "fileprivate", "private", "package"]

  private static let modifierWords: Set<String> = [
    "public", "open", "internal", "fileprivate", "private", "package", "static", "class", "final",
    "mutating", "nonmutating", "nonisolated", "override", "convenience", "required", "indirect", "lazy", "weak", "unowned",
    "dynamic", "optional", "isolated", "distributed", "consuming", "borrowing"
  ]

  private static let accessWords: Set<String> = ["public", "internal", "fileprivate", "private", "package"]

  /// A type or extension whose body declares members.
  private final class Context {
    let kind: String
    let name: String
    let isPublic: Bool
    let spi: String?
    var bodyDepth = 0
    /// A `public` or `open` extension makes its members public unless they say otherwise.
    let membersPublic: Bool

    init(kind: String, name: String, isPublic: Bool, spi: String?, membersPublic: Bool) {
      self.kind = kind
      self.name = name
      self.isPublic = isPublic
      self.spi = spi
      self.membersPublic = membersPublic
    }
  }

  private enum Event {
    case open
    case close
    case keyword(String, end: Int)
  }

  /// Each public declaration in a file's text, as its line in the list.
  static func declarations(in text: String) -> Set<String> {
    let code = ScalarText(SwiftCodeScanner.lines(in: text).map(\.code).joined(separator: "\n"))
    var events: [(position: Int, event: Event)] = []

    var index = 0
    while index < code.count {
      if code[index] == "{" {
        events.append((index, .open))
      } else if code[index] == "}" {
        events.append((index, .close))
      }

      if code[index].isPythonWord {
        var end = index
        while end < code.count, code[end].isPythonWord {
          end += 1
        }
        let word = code.text(index..<end)
        if declarationKeywords.contains(word) {
          events.append((index, .keyword(word, end: end)))
        }
        index = end
      } else {
        index += 1
      }
    }

    var found = Set<String>()
    var stack: [Context] = []
    var depth = 0
    var pending: Context?

    for (position, event) in events {
      switch event {
      case .open:
        depth += 1
        if let context = pending {
          context.bodyDepth = depth
          stack.append(context)
          pending = nil
        }
        continue

      case .close:
        if let last = stack.last, last.bodyDepth == depth {
          stack.removeLast()
        }
        depth -= 1
        continue

      case .keyword(let keyword, let end):
        let context = stack.last
        let atMemberLevel = (context == nil && depth == 0) || (context != nil && depth == context!.bodyDepth)

        if !atMemberLevel {
          continue
        }

        // `case` and `let` in a pattern, or `class` used as a modifier, aren't declarations.
        if keyword == "class", classIsModifier(code, after: end) {
          continue
        }

        if keyword == "case", context == nil || context!.kind != "enum" {
          continue
        }

        let modifiers = modifiersBefore(code, position)
        let spi = modifiers.first { $0.hasPrefix("@_spi") } ?? context?.spi
        let explicit = modifiers.contains("public") || modifiers.contains("open")
        let isStatic = modifiers.contains("static") || modifiers.contains("class")
        let restricted = modifiers.contains { restricting.contains($0) }

        let isPublic: Bool
        if let context {
          if context.kind == "protocol" {
            isPublic = context.isPublic
          } else if keyword == "case" {
            isPublic = context.isPublic
          } else if context.membersPublic {
            isPublic = explicit || !restricted
          } else {
            isPublic = explicit && context.isPublic
          }
        } else {
          isPublic = explicit
        }

        let owner = context.map { "\($0.name)." } ?? ""

        if typeKeywords.contains(keyword) {
          guard let name = typeName(code, after: end) else {
            continue
          }

          if keyword == "extension" {
            // An extension isn't listed itself. Its members are public when they say so, or
            // when the extension is `public` or `open` and they don't say otherwise.
            pending = Context(kind: "extension", name: name, isPublic: true, spi: spi, membersPublic: explicit)
            continue
          }

          let qualified = owner + name
          pending = Context(kind: keyword, name: qualified, isPublic: isPublic, spi: spi, membersPublic: false)

          if isPublic {
            found.insert(entry(spi, keyword, qualified))
          }
          continue
        }

        if !isPublic {
          continue
        }

        let setter = modifiers.first { $0.hasSuffix("(set)") && !$0.hasPrefix("public") && !$0.hasPrefix("open") }
        let prefix = isStatic ? "static " : ""

        switch keyword {
        case "func":
          if let name = functionName(code, after: end) {
            let (parameters, _) = balancedText(code, from: name.parenthesis)
            found.insert(entry(spi, prefix + "func", "\(owner)\(PythonText.strip(name.text, characters: "`"))(\(labels(parameters)))"))
          }

        case "init", "subscript":
          if let opening = initializerOpening(code, after: end) {
            let (parameters, _) = balancedText(code, from: opening)
            let failable = failableMark(code, after: end) ? "?" : ""
            found.insert(entry(spi, prefix + keyword, "\(context?.name ?? "")\(failable)(\(labels(parameters)))"))
          }

        case "var", "let":
          if let name = identifierAfterSpace(code, after: end) {
            let kind = (setter.map { $0 + " " } ?? "") + prefix + keyword
            found.insert(entry(spi, kind, owner + PythonText.strip(name, characters: "`")))
          }

        case "typealias", "associatedtype":
          if let name = identifierAfterSpace(code, after: end) {
            found.insert(entry(spi, keyword, owner + PythonText.strip(name, characters: "`")))
          }

        case "case":
          var lineEnd = end
          while lineEnd < code.count, code[lineEnd] != "\n" {
            lineEnd += 1
          }
          let line = code.text(end..<lineEnd)

          for element in splitTopLevel(line) {
            let head = String(element.unicodeScalars.prefix { $0 != "=" }.map(Character.init))
            if let (name, values) = caseElement(ScalarText(head)) {
              let suffix = values.map { "(\(labels($0)))" } ?? ""
              found.insert(entry(spi, "case", owner + PythonText.strip(name, characters: "`") + suffix))
            }
          }

        default:
          break
        }
      }
    }

    return found
  }

  /// A declaration's line in the list.
  static func entry(_ spi: String?, _ kind: String, _ name: String) -> String {
    "\(spi.map { $0 + " " } ?? "")\(kind) \(name)"
  }

  // MARK: Matching at a position, as the script's regular expressions do

  private static func skipSpaces(_ code: ScalarText, _ index: Int) -> Int {
    var position = index
    while position < code.count, PythonText.isSpace(code[position]) {
      position += 1
    }
    return position
  }

  /// `\s+` then a word; whether the next word after one or more spaces is one of the words.
  private static func classIsModifier(_ code: ScalarText, after end: Int) -> Bool {
    let start = skipSpaces(code, end)
    guard start > end else { return false }
    var wordEnd = start
    while wordEnd < code.count, code[wordEnd].isPythonWord {
      wordEnd += 1
    }
    return ["func", "var", "let", "subscript", "override"].contains(code.text(start..<wordEnd))
  }

  /// `\s+([A-Za-z_][A-Za-z0-9_.]*)`.
  private static func typeName(_ code: ScalarText, after end: Int) -> String? {
    let start = skipSpaces(code, end)
    guard start > end, start < code.count, isIdentifierStart(code[start]) else { return nil }
    var stop = start + 1
    while stop < code.count, isIdentifierPart(code[stop]) || code[stop] == "." {
      stop += 1
    }
    return code.text(start..<stop)
  }

  private static func isIdentifierStart(_ scalar: Unicode.Scalar) -> Bool {
    scalar == "_" || (scalar.isASCII && scalar.properties.isAlphabetic)
  }

  private static func isIdentifierPart(_ scalar: Unicode.Scalar) -> Bool {
    isIdentifierStart(scalar) || ("0"..."9").contains(scalar)
  }

  /// The pattern `` `?[A-Za-z_][A-Za-z0-9_]*`? `` at the index.
  private static func identifier(_ code: ScalarText, at index: Int) -> (text: String, end: Int)? {
    var start = index
    if start < code.count, code[start] == "`" {
      start += 1
    }
    guard start < code.count, isIdentifierStart(code[start]) else {
      return nil
    }
    var end = start + 1
    while end < code.count, isIdentifierPart(code[end]) {
      end += 1
    }
    if end < code.count, code[end] == "`" {
      end += 1
    }
    return (code.text(index..<end), end)
  }

  private static func identifierAfterSpace(_ code: ScalarText, after end: Int) -> String? {
    let start = skipSpaces(code, end)
    guard start > end else { return nil }
    return identifier(code, at: start)?.text
  }

  /// `\s*(?:<[^>]*>)?\s*\(`, from the index: the index of the parenthesis.
  private static func genericsThenParenthesis(_ code: ScalarText, from index: Int) -> Int? {
    var position = skipSpaces(code, index)
    if position < code.count, code[position] == "<", let close = code.find(">", from: position + 1) {
      position = skipSpaces(code, close + 1)
    }
    return position < code.count && code[position] == "(" ? position : nil
  }

  /// `\s+(IDENTIFIER|[^\s(<]+)\s*(?:<[^>]*>)?\s*\(`: the name and the parenthesis' index.
  private static func functionName(_ code: ScalarText, after end: Int) -> (text: String, parenthesis: Int)? {
    let start = skipSpaces(code, end)
    guard start > end else { return nil }

    if let id = identifier(code, at: start), let open = genericsThenParenthesis(code, from: id.end) {
      return (id.text, open)
    }

    var stop = start
    while stop < code.count, !PythonText.isSpace(code[stop]), code[stop] != "(", code[stop] != "<" {
      stop += 1
    }
    guard stop > start, let open = genericsThenParenthesis(code, from: stop) else {
      return nil
    }
    return (code.text(start..<stop), open)
  }

  /// `\s*[?!]?\s*(?:<[^>]*>)?\s*\(`: the parenthesis' index.
  private static func initializerOpening(_ code: ScalarText, after end: Int) -> Int? {
    var position = skipSpaces(code, end)
    if position < code.count, code[position] == "?" || code[position] == "!" {
      position += 1
    }
    return genericsThenParenthesis(code, from: position)
  }

  /// `\s*\?`.
  private static func failableMark(_ code: ScalarText, after end: Int) -> Bool {
    let position = skipSpaces(code, end)
    return position < code.count && code[position] == "?"
  }

  /// `\s*(IDENTIFIER)\s*(\(.*\))?` on an element of a case line: the name and the text between
  /// the outer parentheses.
  private static func caseElement(_ element: ScalarText) -> (String, String?)? {
    let start = skipSpaces(element, 0)
    guard let id = identifier(element, at: start) else {
      return nil
    }
    let afterSpaces = skipSpaces(element, id.end)
    guard afterSpaces < element.count, element[afterSpaces] == "(",
      let close = element.findLast(")", before: element.count), close > afterSpaces
    else {
      return (id.text, nil)
    }
    return (id.text, element.text((afterSpaces + 1)..<close))
  }

  // MARK: Modifiers and parameters

  /// The modifiers and attributes written before the keyword at `start`, reading back over
  /// whole words and over lines that hold only attributes.
  private static func modifiersBefore(_ code: ScalarText, _ start: Int) -> [String] {
    var words: [String] = []
    var index = start

    while true {
      var end = index
      while end > 0, code[end - 1] == " " || code[end - 1] == "\t" {
        end -= 1
      }
      let lineStart = (code.findLast("\n", before: end) ?? -1) + 1
      let tokens = modifierTokens(Array(code[lineStart..<end]))
      var taken: [String] = []

      for token in tokens.reversed() {
        if !isModifier(token) {
          // Another token, such as a type's opening line or `;`, ends the modifiers.
          return Array(taken.reversed()) + words
        }
        taken.append(token)
      }

      words = Array(taken.reversed()) + words

      // Every word on the line was a modifier: keep reading the line above, which may hold
      // attributes such as `@_spi(Raw)` or `@discardableResult`.
      if lineStart == 0 {
        return words
      }

      index = lineStart - 1
    }
  }

  private static func isModifier(_ token: String) -> Bool {
    if token.hasPrefix("@") || modifierWords.contains(token) {
      return true
    }
    if token.hasSuffix("(set)") {
      return accessWords.contains(String(token.dropLast(5)))
    }
    return false
  }

  /// `re.findall(r"@\w+(?:\([^)]*\))?|\w+\(set\)|\w+", segment)`.
  private static func modifierTokens(_ segment: ScalarText) -> [String] {
    var tokens: [String] = []
    var index = 0

    while index < segment.count {
      let scalar = segment[index]

      if scalar == "@" {
        var end = index + 1
        while end < segment.count, segment[end].isPythonWord {
          end += 1
        }
        if end > index + 1 {
          if end < segment.count, segment[end] == "(", let close = segment.find(")", from: end + 1) {
            end = close + 1
          }
          tokens.append(segment.text(index..<end))
          index = end
          continue
        }
      }

      if scalar.isPythonWord {
        var end = index
        while end < segment.count, segment[end].isPythonWord {
          end += 1
        }
        if segment.starts(with: "(set)", at: end) {
          end += 5
        }
        tokens.append(segment.text(index..<end))
        index = end
        continue
      }

      index += 1
    }

    return tokens
  }

  /// The text inside the parentheses that open at `start`, and the index after them.
  private static func balancedText(_ code: ScalarText, from start: Int) -> (String, Int) {
    var depth = 0
    var index = start
    while index < code.count {
      if code[index] == "(" {
        depth += 1
      } else if code[index] == ")" {
        depth -= 1
        if depth == 0 {
          return (code.text((start + 1)..<index), index + 1)
        }
      }
      index += 1
    }
    return (code.text(min(start + 1, code.count)..<code.count), code.count)
  }

  /// Splits a parameter list at the commas outside brackets.
  private static func splitTopLevel(_ text: String) -> [String] {
    let scalars = ScalarText(text)
    var parts: [String] = []
    var depth = 0
    var current = String.UnicodeScalarView()

    for (index, character) in scalars.enumerated() {
      if "([<{".unicodeScalars.contains(character) {
        depth += 1
      } else if ")]>}".unicodeScalars.contains(character), !(character == ">" && index > 0 && scalars[index - 1] == "-") {
        // The `>` of a function type's `->` closes nothing.
        depth -= 1
      }

      if character == ",", depth == 0 {
        parts.append(String(current))
        current = String.UnicodeScalarView()
      } else {
        current.append(character)
      }
    }

    if !PythonText.strip(String(current)).isEmpty {
      parts.append(String(current))
    }

    return parts
  }

  /// The argument labels of a parameter list, such as `json:version:` or `_:`.
  private static func labels(_ parameters: String) -> String {
    var result = ""

    for parameter in splitTopLevel(parameters) {
      guard let colon = parameter.unicodeScalars.firstIndex(of: ":") else {
        // An enum case's unlabeled associated value, such as the `Int` in `case code(Int)`.
        result += "_:"
        continue
      }

      let head = ScalarText(String(parameter.unicodeScalars[..<colon]))
      var names: [String] = []
      var index = 0
      while index < head.count {
        if let id = identifier(head, at: index) {
          names.append(id.text)
          index = id.end
        } else {
          index += 1
        }
      }

      names = names.filter { !["inout", "borrowing", "consuming", "isolated", "sending"].contains($0) }

      if let first = names.first {
        result += PythonText.strip(first, characters: "`") + ":"
      }
    }

    return result
  }
}
