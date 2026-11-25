extension PythonText {
  /// `text.split()`: the pieces between runs of Python whitespace.
  public static func splitWhitespace(_ text: String) -> [String] {
    var pieces: [String] = []
    var current = String.UnicodeScalarView()
    for scalar in text.unicodeScalars {
      if isSpace(scalar) {
        if !current.isEmpty {
          pieces.append(String(current))
          current = String.UnicodeScalarView()
        }
      } else {
        current.append(scalar)
      }
    }
    if !current.isEmpty {
      pieces.append(String(current))
    }
    return pieces
  }

  /// `" ".join(text.split())`: the text with each run of whitespace made one space.
  public static func collapsingWhitespace(_ text: String) -> String {
    splitWhitespace(text).joined(separator: " ")
  }

  /// `Path(name).suffix`: the last dot and what follows it, or empty for a name that starts
  /// or ends with its only dot.
  public static func pathSuffix(_ name: String) -> String {
    let scalars = Array(name.unicodeScalars)
    guard let dot = scalars.lastIndex(of: "."), dot > 0, dot < scalars.count - 1 else {
      return ""
    }
    return String(String.UnicodeScalarView(scalars[dot...]))
  }

  /// `text.count(needle)`: the non-overlapping occurrences of the needle.
  public static func count(of needle: String, in text: String) -> Int {
    let haystack = Array(text.unicodeScalars)
    let pattern = Array(needle.unicodeScalars)
    var total = 0
    var index = 0
    while index + pattern.count <= haystack.count {
      if haystack[index..<index + pattern.count].elementsEqual(pattern) {
        total += 1
        index += pattern.count
      } else {
        index += 1
      }
    }
    return total
  }
}
