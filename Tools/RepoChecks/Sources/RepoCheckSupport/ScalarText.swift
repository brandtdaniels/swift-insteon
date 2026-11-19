/// Text as an array of Unicode scalars, which is what Python indexes, with the character
/// classes Python's `re` gives `\w` and `\s`.
public typealias ScalarText = [Unicode.Scalar]

extension Unicode.Scalar {
  /// Whether Python's `\w` matches the scalar: a letter, a number or the underscore.
  public var isPythonWord: Bool {
    if self == "_" {
      return true
    }
    switch properties.generalCategory {
    case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
      .decimalNumber, .letterNumber, .otherNumber:
      return true
    default:
      return false
    }
  }
}

extension Array where Element == Unicode.Scalar {
  /// Scalars of a string.
  public init(_ text: String) {
    self = Array(text.unicodeScalars)
  }

  /// The text of a range of scalars.
  public func text(_ range: Range<Int>) -> String {
    String(String.UnicodeScalarView(self[range]))
  }

  /// Whether the scalars at the index are the text.
  public func starts(with text: String, at index: Int) -> Bool {
    let pattern = Array(text.unicodeScalars)
    guard index >= 0, index + pattern.count <= count else {
      return false
    }
    return self[index..<index + pattern.count].elementsEqual(pattern)
  }

  /// The index of the first occurrence of the text at or after `from`, or nil.
  public func find(_ text: String, from: Int = 0, before end: Int? = nil) -> Int? {
    let limit = Swift.min(end ?? count, count)
    var position = Swift.max(from, 0)
    let length = text.unicodeScalars.count
    while position + length <= limit {
      if starts(with: text, at: position) {
        return position
      }
      position += 1
    }
    return nil
  }

  /// The index of the last occurrence of the scalar before `end`, or nil.
  public func findLast(_ scalar: Unicode.Scalar, before end: Int) -> Int? {
    var position = Swift.min(end, count) - 1
    while position >= 0 {
      if self[position] == scalar {
        return position
      }
      position -= 1
    }
    return nil
  }

  /// Whether Python's `\b` holds at the index.
  public func isWordBoundary(at index: Int) -> Bool {
    let before = index > 0 && self[index - 1].isPythonWord
    let after = index < count && self[index].isPythonWord
    return before != after
  }
}
