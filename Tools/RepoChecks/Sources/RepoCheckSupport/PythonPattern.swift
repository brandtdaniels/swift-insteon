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

  /// A pattern. It crashes on one that doesn't compile, since the patterns are literals.
  public init(_ pattern: String) {
    do {
      expression = try NSRegularExpression(pattern: pattern, options: [.useUnixLineSeparators])
    } catch {
      preconditionFailure("The pattern \(pattern) doesn't compile: \(error)")
    }
  }

  /// A match, with its named groups.
  public struct Match {
    fileprivate let text: String
    fileprivate let result: NSTextCheckingResult

    /// The text of a named group, or nil if it didn't take part in the match.
    public func group(_ name: String) -> String? {
      let range = result.range(withName: name)
      guard range.location != NSNotFound else {
        return nil
      }
      return NSString(string: text).substring(with: range)
    }
  }

  /// The first match anywhere in the text, as `re.search` finds it.
  public func search(_ text: String) -> Match? {
    let range = NSRange(text.startIndex..., in: text)
    return expression.firstMatch(in: text, options: [], range: range).map { Match(text: text, result: $0) }
  }

  /// The match at the start of the text, as `re.match` finds it.
  public func match(_ text: String) -> Match? {
    let range = NSRange(text.startIndex..., in: text)
    return expression.firstMatch(in: text, options: [.anchored], range: range).map { Match(text: text, result: $0) }
  }
}
