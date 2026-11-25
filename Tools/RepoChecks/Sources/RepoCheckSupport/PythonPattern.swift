import Foundation

/// Regular expressions with the meaning Python's `re` gives a `str` pattern.
///
/// ICU, behind `NSRegularExpression`, defines `\s`, `\w` and `\b` by other rules and treats
/// more characters as line ends. The pattern strings here spell Python's classes out, and the
/// options make `.` and `$` see only `"\n"` as a line end.
public struct PythonPattern {
  /// The members of Python's `\s` for a `str`, ready to put inside `[...]`.
  public static let spaceMembers = #"\t-\r\x1c-\x1f \x85\xa0\x{1680}\x{2000}-\x{200a}\x{2028}\x{2029}\x{202f}\x{205f}\x{3000}"#

  /// Python's `\s`.
  public static let space = "[\(spaceMembers)]"

  /// Python's `\S`.
  public static let nonSpace = "[^\(spaceMembers)]"

  /// The members of Python's `\w`, ready to put inside `[...]`.
  public static let wordMembers = #"\p{L}\p{N}_"#

  /// Python's `\d`.
  public static let digit = #"\p{Nd}"#

  private let expression: NSRegularExpression

  /// A pattern in ICU syntax. It crashes on one that doesn't compile, since the patterns are
  /// literals.
  public init(_ pattern: String, caseInsensitive: Bool = false) {
    var options: NSRegularExpression.Options = [.useUnixLineSeparators]
    if caseInsensitive {
      options.insert(.caseInsensitive)
    }
    do {
      expression = try NSRegularExpression(pattern: pattern, options: options)
    } catch {
      preconditionFailure("The pattern \(pattern) doesn't compile: \(error)")
    }
  }

  /// A pattern written as Python writes it, with `\w`, `\d`, `\s` and `\b` given Python's
  /// meaning for a `str`, which ICU defines otherwise.
  public init(python pattern: String) {
    self.init(Self.translating(pattern))
  }

  /// A match, with its named groups.
  public struct Match {
    fileprivate let text_: String
    fileprivate let result: NSTextCheckingResult

    /// The whole match, as `group(0)`.
    public var text: String {
      PythonPattern.ns(text_).substring(with: result.range)
    }

    /// The UTF-16 offset where the match starts.
    public var startOffset: Int {
      result.range.location
    }

    /// The text of a numbered group, or nil if it didn't take part in the match.
    public func group(_ number: Int) -> String? {
      let range = result.range(at: number)
      guard range.location != NSNotFound else {
        return nil
      }
      return PythonPattern.ns(text_).substring(with: range)
    }

    /// The text of a named group, or nil if it didn't take part in the match.
    public func group(_ name: String) -> String? {
      let range = result.range(withName: name)
      guard range.location != NSNotFound else {
        return nil
      }
      return PythonPattern.ns(text_).substring(with: range)
    }
  }

  /// The first match anywhere in the text, as `re.search` finds it.
  public func search(_ text: String) -> Match? {
    let range = NSRange(text.startIndex..., in: text)
    return expression.firstMatch(in: text, options: [], range: range).map { Match(text_: text, result: $0) }
  }

  /// The match at the start of the text, as `re.match` finds it.
  public func match(_ text: String) -> Match? {
    let range = NSRange(text.startIndex..., in: text)
    return expression.firstMatch(in: text, options: [.anchored], range: range).map { Match(text_: text, result: $0) }
  }
}

extension PythonPattern {
  /// The text of every non-overlapping match, as `re.findall` gives for a pattern without
  /// groups.
  public func allMatches(in text: String) -> [String] {
    let nsText = PythonPattern.ns(text)
    return expression.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
      .map { nsText.substring(with: $0.range) }
  }

  /// The text with each match replaced by the literal replacement, as `re.sub`.
  public func replacingAll(in text: String, with replacement: String) -> String {
    expression.stringByReplacingMatches(
      in: text,
      options: [],
      range: NSRange(location: 0, length: PythonPattern.ns(text).length),
      withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
    )
  }

  /// Spells out `\w`, `\d`, `\s` and `\b` as the classes Python gives them.
  static func translating(_ python: String) -> String {
    let word = "[\(wordMembers)]"
    let boundary = "(?:(?<=\(word))(?!\(word))|(?<!\(word))(?=\(word)))"
    var result = ""
    var inClass = false
    var scalars = python.unicodeScalars.makeIterator()

    while let scalar = scalars.next() {
      switch scalar {
      case "\\":
        guard let next = scalars.next() else {
          result.append("\\")
          continue
        }
        switch next {
        case "w": result += inClass ? wordMembers : word
        case "d": result += digit
        case "s": result += inClass ? spaceMembers : space
        case "b": result += boundary
        default:
          result.append("\\")
          result.unicodeScalars.append(next)
        }
      case "[" where !inClass:
        inClass = true
        result.unicodeScalars.append(scalar)
      case "]" where inClass:
        inClass = false
        result.unicodeScalars.append(scalar)
      default:
        result.unicodeScalars.append(scalar)
      }
    }
    return result
  }
}

// A compiled `NSRegularExpression` is immutable and documented as safe to share between threads.
extension PythonPattern: @unchecked Sendable {}

extension PythonPattern {
  /// The start of each non-overlapping match, as a UTF-16 offset, with the text before it.
  public func allMatchPrefixes(in text: String) -> [String] {
    let nsText = PythonPattern.ns(text)
    return expression.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
      .map { nsText.substring(to: $0.range.location) }
  }
}

extension PythonPattern {
  /// An `NSString` with exactly the text's UTF-16 code units. `NSString(string:)` drops a leading
  /// byte order mark, which would put the regular expression's ranges out of step with it.
  public static func ns(_ text: String) -> NSString {
    let units = Array(text.utf16)
    return NSString(characters: units, length: units.count)
  }
}
