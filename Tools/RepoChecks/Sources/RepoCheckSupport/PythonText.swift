/// String operations with the meaning Python gives them.
///
/// Swift compares and splits text by extended grapheme cluster and canonical equivalence; the
/// scripts this tool replaces worked on code points. These helpers work on Unicode scalars so
/// that a line holding `"\r\n"` or a combining mark is read as the scripts read it.
public enum PythonText {
  /// Whether Python's `str.isspace` is true for the scalar.
  public static func isSpace(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x09...0x0D, 0x1C...0x1F, 0x20, 0x85, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000:
      return true
    default:
      return false
    }
  }

  /// `text.lstrip()`.
  public static func lstrip(_ text: String) -> String {
    String(text.unicodeScalars.drop(while: isSpace))
  }

  /// `text.rstrip()`.
  public static func rstrip(_ text: String) -> String {
    var scalars = Substring(text).unicodeScalars
    while let last = scalars.last, isSpace(last) {
      scalars.removeLast()
    }
    return String(scalars)
  }

  /// `text.strip()`.
  public static func strip(_ text: String) -> String {
    lstrip(rstrip(text))
  }

  /// `text.strip(characters)`.
  public static func strip(_ text: String, characters: String) -> String {
    let set = Set(characters.unicodeScalars)
    var scalars = Substring(text).unicodeScalars.drop(while: set.contains)
    while let last = scalars.last, set.contains(last) {
      scalars.removeLast()
    }
    return String(scalars)
  }

  /// `text.rstrip(characters)`.
  public static func rstrip(_ text: String, characters: String) -> String {
    let set = Set(characters.unicodeScalars)
    var scalars = Substring(text).unicodeScalars
    while let last = scalars.last, set.contains(last) {
      scalars.removeLast()
    }
    return String(scalars)
  }

  /// `text.startswith(prefix)`, by code point.
  public static func hasPrefix(_ text: String, _ prefix: String) -> Bool {
    text.unicodeScalars.starts(with: prefix.unicodeScalars)
  }

  /// `a == b`, by code point.
  public static func areEqual(_ a: String, _ b: String) -> Bool {
    a.unicodeScalars.elementsEqual(b.unicodeScalars)
  }

  /// `len(text)`, the number of code points.
  public static func length(_ text: String) -> Int {
    text.unicodeScalars.count
  }

  /// `text.split("\n")`: the lines of text, with an empty last element after a final newline.
  public static func splitLines(_ text: String) -> [String] {
    var lines: [String] = []
    var current = String.UnicodeScalarView()
    for scalar in text.unicodeScalars {
      if scalar == "\n" {
        lines.append(String(current))
        current = String.UnicodeScalarView()
      } else {
        current.append(scalar)
      }
    }
    lines.append(String(current))
    return lines
  }

  /// Whether the first text sorts before the second, by code point as Python's `str` does.
  public static func isOrdered(_ a: String, before b: String) -> Bool {
    a.unicodeScalars.lexicographicallyPrecedes(b.unicodeScalars) { $0.value < $1.value }
  }
}
